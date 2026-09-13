#!/usr/bin/env python3
"""Invoke one tool over the installed app's real stdio transport for local checks."""
import json, select, subprocess, sys

binary, name, raw = sys.argv[1:4]
with subprocess.Popen([binary, '--mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                      stderr=sys.stderr, text=True, bufsize=1) as process:
    def request(index, method, params):
        process.stdin.write(json.dumps(dict(jsonrpc='2.0', id=index, method=method, params=params)) + '\n')
        process.stdin.flush()
        while True:
            if not select.select([process.stdout], [], [], 30)[0]: raise TimeoutError(method)
            line = process.stdout.readline()
            if not line: raise RuntimeError('MCP exited before responding')
            response = json.loads(line)
            if response.get('id') == index: return response
    try:
        initialized = request(1, 'initialize', {'protocolVersion':'2025-06-18', 'capabilities':{},
                              'clientInfo':{'name':'DaydoLocalCheck','version':'1.0'}})
        if 'error' in initialized: raise RuntimeError(initialized['error'])
        process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n'); process.stdin.flush()
        response = request(2, 'tools/call', {'name':name, 'arguments':json.loads(raw)})
        print(json.dumps(response, ensure_ascii=False, indent=2))
    finally:
        process.stdin.close()
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
