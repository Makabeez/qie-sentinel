#!/usr/bin/env python3
"""Regression for publicly accessible read-only RPC lab."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
site=root/'site'
for filename in ('index.html','style.css','app.js','vercel.json'):
    assert (site/filename).is_file(), filename
html=(site/'index.html').read_text(); js=(site/'app.js').read_text(); config=json.loads((site/'vercel.json').read_text())
assert 'https://github.com/Makabeez/qie-sentinel' in html
assert 'pause and unpause were exercised' in html
assert 'pause and recovery controls were exercised' not in html
assert 'SIMULATION · NO WALLET' not in html
assert 'LIVE READ-ONLY · NO WALLET' in html
assert '4 <small>test cases</small>' in html
assert "eth_call" in js and "eth_chainId" in js and "eth_getBlockByNumber" in js
assert 'fetch(' in js and 'No policy verdict inferred from failed RPC' in js
assert 'mainnet.qie.digital/tx/' in html
assert config['framework'] is None
csp=next(h['value'] for rule in config['headers'] for h in rule['headers'] if h['key']=='Content-Security-Policy')
assert 'connect-src https://rpc1mainnet.qie.digital https://mainnet.qie.digital' in csp
assert "script-src 'self'" in csp
for body in (html,js):
    assert not re.search(r'OPENAI_API_KEY|PRIVATE_KEY|SENTINEL_OWNER_KEY|api/agent|api/proposals|eth_sendTransaction|eth_sendRawTransaction|personal_sign|eth_signTypedData',body,re.I)
print('Public site checks passed: read-only RPC only, no signing or admin endpoints.')
