#!/usr/bin/env bash
set -euo pipefail
DAYDO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DAYDO_MODE="${1:-run}"
DAYDO_BUNDLE="$DAYDO_ROOT/dist/Daydo.app"
DAYDO_INSTALLED="$HOME/Applications/Daydo.app"
DAYDO_BUILD="$HOME/Library/Developer/Xcode/DerivedData/Daydo-todo"
case "$DAYDO_MODE" in
  run|--build|--debug|--logs|--telemetry|--verify|--preview) ;;
  *) echo "Usage: $0 [--build|--debug|--logs|--telemetry|--verify|--preview]" >&2; exit 2 ;;
esac
cd "$DAYDO_ROOT"

# Only stop GUI processes launched from this project's own output directories.
python3 - "$DAYDO_ROOT" "$DAYDO_BUILD" <<'PY'
import os, signal, subprocess, sys, time
root = sys.argv[1]
prefixes = [root + '/dist/Daydo.app/Contents/MacOS/Daydo', sys.argv[2] + '/Build/Products/Debug/Daydo.app/Contents/MacOS/Daydo']
targets = []
for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) != 2:
        continue
    pid, command = int(fields[0]), fields[1]
    if '--mcp' in command.split():
        continue
    if any(command == path or command.startswith(path + ' ') for path in prefixes):
        targets.append(pid)
for pid in targets:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
deadline = time.monotonic() + 5
while targets and time.monotonic() < deadline:
    targets = [p for p in targets if subprocess.run(['ps', '-p', str(p)], stdout=subprocess.DEVNULL).returncode == 0]
    if targets: time.sleep(0.1)
if targets:
    raise SystemExit('Daydo GUI did not exit; inspect these exact PIDs before retrying: ' + str(targets))
PY

if command -v xcodegen >/dev/null; then xcodegen generate; fi
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1
xcodebuild -project Daydo.xcodeproj -scheme Daydo -configuration Debug \
  -derivedDataPath "$DAYDO_BUILD" -jobs 4 -skipPackageUpdates \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
mkdir -p "$DAYDO_ROOT/dist"
if [ -e "$DAYDO_BUNDLE" ]; then
  DAYDO_EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DAYDO_BUNDLE/Contents/Info.plist")
  [ "$DAYDO_EXISTING_ID" = "com.xiaolin.daydo" ] || { echo "Refusing to overwrite another app." >&2; exit 1; }
  rm -rf "$DAYDO_BUNDLE"
fi
ditto --noextattr --norsrc "$DAYDO_BUILD/Build/Products/Debug/Daydo.app" "$DAYDO_BUNDLE"
codesign --verify --deep --strict "$DAYDO_BUNDLE"
if [ "$DAYDO_MODE" != "--build" ] && [ "$DAYDO_MODE" != "--preview" ]; then
  # The GUI, desktop widget and MCP configuration use the same installed build.
  python3 - "$DAYDO_INSTALLED" <<'PY'
import os, plistlib, signal, subprocess, sys, time
from pathlib import Path
app = Path(sys.argv[1])
if app.exists():
    with (app / 'Contents/Info.plist').open('rb') as source:
        if plistlib.load(source).get('CFBundleIdentifier') != 'com.xiaolin.daydo':
            raise SystemExit('Refusing to replace another application: ' + str(app))
executables = [str(app / 'Contents/MacOS/Daydo'),
               str(app / 'Contents/PlugIns/DaydoWidget.appex/Contents/MacOS/DaydoWidget')]
targets = []
for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) != 2 or '--mcp' in fields[1].split():
        continue
    if any(fields[1] == exe or fields[1].startswith(exe + ' ') for exe in executables):
        targets.append(int(fields[0]))
for pid in targets:
    try: os.kill(pid, signal.SIGTERM)
    except ProcessLookupError: pass
deadline = time.monotonic() + 5
while targets and time.monotonic() < deadline:
    targets = [pid for pid in targets if subprocess.run(['ps', '-p', str(pid)], stdout=subprocess.DEVNULL).returncode == 0]
    if targets: time.sleep(0.1)
if targets:
    raise SystemExit('Daydo is still running; inspect these exact PIDs: ' + str(targets))
PY
  mkdir -p "$(dirname "$DAYDO_INSTALLED")"
  ditto --noextattr --norsrc "$DAYDO_BUNDLE" "$DAYDO_INSTALLED"
  codesign --verify --deep --strict "$DAYDO_INSTALLED"
fi
case "$DAYDO_MODE" in
  --build) echo "$DAYDO_BUNDLE" ;;
  --preview) open -n "$DAYDO_BUNDLE" --args --ui-preview ;;
  --debug)
    open "$DAYDO_INSTALLED"
    sleep 2
    DAYDO_GUI_PID=$(python3 - "$DAYDO_INSTALLED/Contents/MacOS/Daydo" <<'PY'
import subprocess, sys
pids = [line.split(None, 1)[0] for line in subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True).splitlines()
        if len(line.split(None, 1)) == 2 and line.split(None, 1)[1].strip() == sys.argv[1]]
if len(pids) != 1: raise SystemExit('Expected one installed Daydo GUI, found ' + str(pids))
print(pids[0])
PY
    )
    lldb -p "$DAYDO_GUI_PID"
    ;;
  --logs) open "$DAYDO_INSTALLED"; /usr/bin/log stream --info --style compact --predicate 'process == "Daydo"' ;;
  --telemetry) open "$DAYDO_INSTALLED"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.xiaolin.daydo"' ;;
  --verify)
    open "$DAYDO_INSTALLED"
    sleep 2
    python3 - "$DAYDO_INSTALLED/Contents/MacOS/Daydo" <<'PY'
import subprocess, sys
commands = subprocess.check_output(['ps', '-axo', 'command='], text=True).splitlines()
if sys.argv[1] not in commands: raise SystemExit('Installed Daydo GUI is not running.')
print('Installed Daydo is running. No Daydo sign-in is required.')
PY
    ;;
  run) open "$DAYDO_INSTALLED" ;;
esac
