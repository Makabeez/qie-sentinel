# QIE Sentinel — mainnet dashboard and policy evaluator

A **read-only**, standard-library Python app for the live SentinelVault on QIE Mainnet (chain ID 1990). Uses Foundry `cast sig` to derive Ethereum ABI function selectors and QIE JSON-RPC to read state. Contains **no owner or executor secrets**, and cannot sign or submit a transaction.

## Run

```bash
cd /mnt/c/Github/qie-sentinel
export PATH="$HOME/.foundry/bin:$PATH"
# Extract overlay zip into repository root (merges new sentinel-agent/ folder)
python3 sentinel-agent/server.py
```

Open **http://127.0.0.1:8765/** in your Windows browser (WSL loopback forwarding).

Alternative: `SENTINEL_PORT=8766 python3 sentinel-agent/server.py`.

## Features

- Verified owner, executor, token, guard, chain, balance, pause and spending limits directly from QIE RPC.
- 6 checks for each proposal (allowlist, per-transfer budget, remaining daily budget, balance, unused nonce, pause).
- Dynamic `PaymentExecuted` history for the latest 5000 blocks. Older history requires an indexer/backfill.
- Demonstration buttons for valid policy, disallowed recipient, excessive amount.
- Fails closed if RPC unavailable or contract configuration changes.

## Threat model and limitations

This is an **advisory simulator only**; 'eligible' is not a signed payment, and a payment may fail later if state changes. The authoritative safety policy lives in Solidity. Do not expose this local web app to the public internet or use it for unaudited high-value funds. Owner keys must remain outside the agent/backend. No API accepts a key or signature. No payments are submitted by this package.

Future execution workflow: owner signs scoped EIP-712 `Payment` intent through a separate wallet/approval interface; agent validates the signature and intent; executor submits `execute(payment, signature)`; backend monitors receipts and emits audit records. Do not put `sentinel-owner` keystore password on the agent host.
