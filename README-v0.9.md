# QIE Sentinel v0.9 — Truth in Claims + Read-only On-chain Lab

## Scope

This overlay modifies `site/index.html`, `site/app.js`, `site/vercel.json`, and `scripts/check-public-site.py` only. No contracts, keys, backend, database, or live payments are touched.

## Lab behavior

- `eth_chainId` confirms 1990, `eth_getBlockByNumber` obtains chain time.
- `eth_call` queries `PolicyGuard.validate(recipient, amount)`, `SentinelVault.isNonceUsed(nonce)` and `paused()`.
- For `PolicyGuard.validate()` custom-error reverts, the app decodes known error selectors, falling back to the guard's getter values if the node hides revert data.
- Expiry is assessed against the on-chain block timestamp, not a vault execute() call.
- Read-only checks are **not equivalent to failed on-chain transactions**. A complete signed `execute` can still fail for additional reasons, including signature, executor, token or balance.
- CORS or RPC failures produce **UNAVAILABLE**, not a fake rejection. If the public RPC does not permit browser-origin POST, consider a separate restricted, read-only Vercel proxy with explicit method and contract allowlists. Do not use the local Python dashboard as proxy.

## Installation

```bash
cd /mnt/c/Github/qie-sentinel
unzip -o /mnt/c/Users/VPS/Downloads/qie-sentinel-v0.9-trust-fixes.zip
python3 scripts/check-public-site.py
node --check site/app.js
bash scripts/check-publish.sh
# Review changes first
git diff -- site/ scripts/check-public-site.py
git add site/index.html site/app.js site/vercel.json scripts/check-public-site.py
git commit -m "Make policy demo read-only on-chain and correct evidence claims"
git push origin main
```

## Still necessary before submission

1. **Verify source on explorer**: https://mainnet.qie.digital/contract-verification — first SentinelVault (constructor creates PolicyGuard), then PolicyGuard. Match compiler 0.8.24, optimizer and constructor args to original deployment; be careful not to declare it verified until the explorer confirms.
2. **Real user adoption**: onboard consenting independent recipients and record genuine usage; don't circulate payments to yourself as 'traction'. This requires separate owner-only recipient allowlisting and true economic activity.
3. **AI-agent demo**: show actual local proposal/audit record, optionally a redacted screencast. Public site remains read-only.
4. **Earlier 0.25 QUSDC payment**: add once the complete transaction hash is verified; do not guess from a partial `0xf26e...`.
5. **Check in browser**: Both permitted RPC endpoints might block cross-origin browser calls. The site explicitly reports unavailability rather than simulating an answer.
