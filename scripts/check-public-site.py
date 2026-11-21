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

# v1.1: evidence must not regress to stale claims or omit historical receipts.
assert "source-verified" in html.lower()
assert "verification is pending" not in html.lower()
assert '0xf26e8863da1d116399bcf3d5cfb8efad378897446da585c16afb2eeaef3d9442' in html
assert '0x196dce5ce2ad7ad2f327eb5ff9d41c171dd0535bbcdb001742832b1862a5d59a' in html
assert '0x95f122e6b4679727751dd8e111ed4a5892fd9d85d07aa0554fcb1a52127c1b48' in html
assert html.count('class="verified-link"') >= 2
assert 'independent customer adoption' in html
assert 'HISTORICAL AGENT WORKFLOW' in html
assert 'Read-only' in html

print('Public site checks passed: live RPC only, verified contracts, 3 receipts, no signing or admin endpoints.')
