#!/usr/bin/env python3
"""Black-box stdio verification. --exercise writes and then archives a dedicated test list."""
import argparse
import datetime
import json
import pathlib
import queue
import subprocess
import threading
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("binary")
parser.add_argument("--exercise", action="store_true")
parser.add_argument("--background-pid", type=int,
                    help="Verify this already-windowless GUI process stays out of the Dock during MCP writes.")
parser.add_argument("--report", default="artifacts/mcp-report.json")
args = parser.parse_args()
report_path = pathlib.Path(args.report)
report_path.parent.mkdir(parents=True, exist_ok=True)
stderr_path = report_path.with_suffix(".stderr.log")
messages = queue.Queue()
with stderr_path.open("w") as stderr:
    process = subprocess.Popen([args.binary, "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1)
    def receive():
        for line in process.stdout:
            try: messages.put(json.loads(line))
            except Exception as error: messages.put(error)
    reader = threading.Thread(target=receive, daemon=True)
    reader.start()
    request_id = 0
    def request(method, params):
        global request_id
        request_id += 1
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}) + "\n")
        process.stdin.flush()
        while True:
            result = messages.get(timeout=30)
            if isinstance(result, Exception): raise result
            if result.get("id") == request_id:
                if "error" in result: raise RuntimeError(result["error"])
                return result["result"]
    def tool(name, arguments):
        result = request("tools/call", {"name": name, "arguments": arguments})
        content = json.loads(result["content"][0]["text"])
        if args.background_pid and name in ["create_list", "update_list", "create_task", "update_task", "set_task_completion"]:
            record_presentation(name)
        return content, bool(result.get("isError"))
    def record_presentation(step):
        output = subprocess.check_output(
            ["lsappinfo", "info", "-only", "pid,ApplicationType", str(args.background_pid)], text=True)
        background_checks.append({"step": step, "process": output.strip()})
        return '"ApplicationType"="UIElement"' in output and f'"pid"={args.background_pid}' in output
    report = {}
    background_checks = []
    test_list = None
    try:
        if args.background_pid:
            assert args.exercise, "--background-pid requires --exercise"
            assert record_presentation("before"), "Close all Daydo windows before this check"
        init = request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {"experimental": {"codex/auth-change": {}}, "elicitation": {"form": {}, "url": {}}}, "clientInfo": {"name": "DaydoAcceptance", "version": "1.0"}})
        report["protocolVersion"] = init["protocolVersion"]
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        process.stdin.flush()
        names = sorted(t["name"] for t in request("tools/list", {})["tools"])
        expected = sorted(["get_status", "list_lists", "create_list", "update_list", "list_tasks", "get_task", "create_task", "update_task", "set_task_completion"])
        assert names == expected, names
        report["tools"] = names
        status, failed = tool("get_status", {})
        assert not failed, status
        report["status"] = status
        assert status["signInRequired"] is False, status
        if not status["ready"]:
            locked, failed = tool("list_lists", {})
            assert failed, locked
            report["unauthenticatedRead"] = locked.get("code")
            locked_write, failed = tool("create_task", {"fields": {"title": "此任务不应被创建"}})
            assert failed, locked_write
            report["unauthenticatedWrite"] = locked_write.get("code")
            report["taskExercise"] = "not_run: store is not ready"
        elif args.exercise:
            test_list, failed = tool("create_list", {"name": "Daydo MCP 验收", "requestId": "acceptance-list-" + str(uuid.uuid4())})
            assert not failed, test_list
            fields = {"title": "MCP 创建验收", "listID": test_list["id"], "day": datetime.date.today().isoformat(), "timeZoneID": "Asia/Shanghai"}
            create = {"fields": fields, "requestId": str(uuid.uuid4())}
            task, failed = tool("create_task", create)
            assert not failed, task
            repeat, failed = tool("create_task", create)
            assert not failed and repeat["id"] == task["id"]
            updated, failed = tool("update_task", {"taskId": task["id"], "expectedRevision": task["revision"], "fields": {"title": "MCP 编辑验收"}})
            assert not failed and updated["fields"]["title"] == "MCP 编辑验收", updated
            stale, failed = tool("update_task", {"taskId": task["id"], "expectedRevision": task["revision"], "fields": {"title": "过旧修改"}})
            assert failed and stale["code"] == "VERSION_CONFLICT", stale
            for _ in range(2):
                complete, failed = tool("set_task_completion", {"taskId": task["id"], "completed": True})
                assert not failed and complete["completed"], complete
            page, failed = tool("list_tasks", {"listId": test_list["id"], "completed": True})
            assert not failed and page["total"] == 1, page
            report["taskExercise"] = "passed: create, deduplicate, update, stale revision, complete, retry, query without app sign-in"
        else:
            _, failed = tool("list_lists", {})
            assert not failed
            report["taskExercise"] = "not_requested"
        if args.background_pid:
            assert all('"ApplicationType"="UIElement"' in item["process"] for item in background_checks), \
                "MCP brought the background coordinator back into the Dock"
        report["success"] = True
    except Exception as error:
        report["success"] = False
        report["error"] = str(error)
    finally:
        if test_list:
            try:
                _, failed = tool("update_list", {"listId": test_list["id"], "expectedRevision": test_list["revision"], "isArchived": True})
                report["testListArchived"] = not failed
            except Exception as error: report["cleanupError"] = str(error)
        if args.background_pid:
            report["backgroundCoordinator"] = {"pid": args.background_pid, "checks": background_checks}
            if not all('"ApplicationType"="UIElement"' in item["process"] for item in background_checks):
                report["success"] = False
        process.stdin.close()
        try:
            process.wait(timeout=10)
            report["exitedOnEOF"] = True
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            report["exitedOnEOF"] = False
        report["exitCode"] = process.returncode
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report.get("success") or not report["exitedOnEOF"]:
        raise SystemExit(1)
