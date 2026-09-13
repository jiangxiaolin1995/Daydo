#!/usr/bin/env python3
"""Check the intent metadata actually shipped in the app and widget extension."""
import json
import sys
from pathlib import Path

app = Path(sys.argv[1])
targets = [app, app / 'Contents/PlugIns/DaydoWidget.appex']
report = []
for target in targets:
    metadata = json.loads((target / 'Contents/Resources/Metadata.appintents/extract.actionsdata').read_text())
    action = metadata['actions']['CompleteTaskIntent']
    report.append({
        'bundle': target.name,
        'openAppWhenRun': action['openAppWhenRun'],
        'supportedModes': action['supportedModes'],
        'systemProtocols': action['systemProtocols'],
    })
print(json.dumps(report, ensure_ascii=False, indent=2))
assert all(item['openAppWhenRun'] is False for item in report), 'Completion must not open the app'
assert all(item['systemProtocols'] == [] for item in report), 'Completion must not require an app-process protocol'
assert all(item['supportedModes'] == 1 for item in report), 'Completion must support only background execution'
