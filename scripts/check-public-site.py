#!/usr/bin/env python3
"""Public-site safety regression: ensures pages are static and contain no runtime API or secrets."""
from pathlib import Path
import json
import re
root=Path(__file__).resolve().parents[1]
site=root/'site'
for filename in ('index.html','style.css','app.js','vercel.json'):
    assert (site/filename).is_file(), f'Missing {filename}'
html=(site/'index.html').read_text()
js=(site/'app.js').read_text()
config=json.loads((site/'vercel.json').read_text())
assert 'SIMULATION' in html and 'simulation' in js.lower()
assert 'mainnet.qie.digital/tx/' in html
assert config['framework'] is None
assert any(h['key']=='Content-Security-Policy' and "connect-src 'none'" in h['value'] for rule in config['headers'] for h in rule['headers'])
for body in (html,js):
    assert not re.search(r'OPENAI_API_KEY|PRIVATE_KEY|SENTINEL_OWNER_KEY|fetch\(|XMLHttpRequest|api/agent|api/proposals',body,re.I), 'Unsafe public bundle content'
print('Public site checks passed: static-only, no API connectivity, on-chain receipt links included.')
