"""Seed an isolated UI review profile; never touches real meetings."""
import json
from pathlib import Path
import sys
import uuid

root = Path(sys.argv[1]).resolve()
standard = Path.home() / 'Library/Application Support/Minutes'
if root == standard.resolve():
    raise SystemExit('Use a separate profile')
root.mkdir(parents=True, exist_ok=True)
fixtures = [
    ('Website launch review', 'The team agreed to launch the new website on Thursday with the existing pricing page. The revised pricing proposal needs another review before it can ship.\n\nDecisions\n• Launch Thursday with the current pricing page.\n\nAction items\n☐ Maya will finish the launch checklist by Wednesday.\n☐ Leo will share the revised pricing proposal for review.\n\nOpen questions\n• Should annual plans include a discount?', 1472, 'ready'),
    ('Design check-in', 'The navigation direction looks promising, but no design was approved. The next review will compare the two remaining options.', 624, 'ready'),
    ('Planning discussion', '', 1025, 'failed'),
]
for index, (title, body, duration, state) in enumerate(fixtures):
    uid = str(uuid.uuid5(uuid.NAMESPACE_DNS, 'minutes-review-' + title)).upper()
    folder = root / 'meetings' / uid
    folder.mkdir(parents=True, exist_ok=True)
    meeting = dict(id=uid, date=810586800 - index * 86400, duration=duration, title=title, body=body, state=state, processor='Local · qwen3:8b')
    if state == 'failed':
        meeting['error'] = 'The local model is not running. Start Ollama, then retry.'
    (folder / 'meeting.json').write_text(json.dumps(meeting))
    (folder / 'transcript.txt').write_text('[00:01] Microphone: Let’s launch Thursday with the current pricing.\n[00:06] System: Agreed. Maya will finish the checklist by Wednesday.\n[00:13] Microphone: Leo will send the revised proposal. The annual discount is still an open question.')
(root / 'settings.json').write_text(json.dumps(dict(provider='local', model='qwen3:8b', configured=True)))
print(root)
