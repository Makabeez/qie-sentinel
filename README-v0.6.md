# QIE Sentinel v0.6 — Natural-language payment interpreter

This is a **non-destructive overlay** over your working v0.5/v0.4/v0.3/v0.2 project. It does not replace your SQLite database, wallet scripts, contracts, or transaction history.

## What's included

- `interpreter.py`: deterministic, fail-closed natural-language payment request parser. Resolves the configured `approved service provider` alias to the known mainnet deployer wallet. Unknown aliases and ambiguous quantities are blocked. Explicit 0x recipients can be passed to the **live** recipient allowlist check.
- `server.py`: new `/api/agent/interpret` (preview) and `/api/agent/request` (persist unsigned proposal) POST endpoints. These use the existing local nonce selector, mainnet preflight evaluator and SQLite proposal ledger. No private keys loaded, signing or broadcasting in the HTTP process.
- `web/index.html`: natural-language agent form, evaluation results, and unsigned proposal submission.
- `showcase.py`: human-readable failed-check descriptions and optional separate on-chain events section using `/api/payments` data.
- `test_interpreter.py`, `test_showcase_v06.py`, `test_showcase.py`: local validation.

**No LLM is included or invoked.** This is a conservative local natural-language interpreter with explicitly coded rules; don't describe it as an LLM-powered AI. A future LLM integration must remain advisory only, with no authority to select destinations/amounts without independent validation.

## Install

```bash
cd /mnt/c/Github/qie-sentinel
export PATH="$HOME/.foundry/bin:$PATH"
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-v0.6.zip
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' -v
python3 -m py_compile sentinel-agent/*.py
```

Restart the existing process on port 8765 (to load the new code):

```bash
sudo fuser -k 8765/tcp || true
SENTINEL_PORT=8765 python3 -u sentinel-agent/server.py
```

Open `http://127.0.0.1:8765/index.html` and hard-refresh. Try:

```
Pay 0.05 QUSDC to the approved service provider for invoice 1042.
```

**Interpret & check policy** only reads chain state. **Save unsigned proposal** stores a new row in your existing approval queue, and cannot sign or transfer funds.

## CLI/API quick check

```bash
curl -fsS http://127.0.0.1:8765/api/agent/interpret \
 -H 'Content-Type: application/json' \
 -d '{"text":"Pay 0.05 QUSDC to the approved service provider for invoice 1042."}' \
 | python3 -m json.tool
```

## Generate showcase with additional on-chain payment evidence

Capture event data from the dashboard's live RPC-backed endpoint and render it into the static evidence report:

```bash
curl -fsS http://127.0.0.1:8765/api/payments -o sentinel-chain-payments.json
python3 sentinel-agent/evidence.py --output sentinel-evidence.json
python3 sentinel-agent/showcase.py --input sentinel-evidence.json \
 --chain-payments sentinel-chain-payments.json --output sentinel-showcase.html
explorer.exe sentinel-showcase.html
```

The `/api/payments` endpoint displays only the last 5,000 blocks, not necessarily all historic payments. The snapshot is informational; verify the individual hashes on the QIE explorer. Never confuse rejected **off-chain** proposals with reverted **on-chain** transactions.

## Security and operational limits

- The server binds loopback, refuses cross-origin POST requests, and never loads private keys.
- Recipient aliases are hard-coded to the documented **demo** address; no hidden address book or inferred recipient.
- Requests are not interpreted as owner approval, even if the text says “approved” or “urgent”.
- The parser extracts precisely one QUSDC amount. It rejects ambiguous/cross-token text, unknown recipient names, and basic policy-bypass instructions.
- Only contract `execute()` can enforce final authorization. Off-chain rules only provide preflight eligibility.
- Existing `agent.py approve ID` and `agent.py execute ID` remain the independent, deliberate operator steps.
