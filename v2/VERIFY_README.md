# Sentinel 2.3 verification

The browser verifier is at **http://127.0.0.1:8766/v2/verify.html**.

In WSL:
```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
node --test v2/test-*.mjs
node --check v2/verify-safe.mjs
```
Keep your server on port 8766 running, then open the link above.

Import `C:\Users\VPS\Downloads\sentinel-v2-unsigned-eip712.json`.

This is a read-only check of QIE Mainnet contract digest, domain, owner, executor, token, nonce, PolicyGuard, deadline and balance at a single block. **No signature, wallet control or transaction is verified.** The on-chain digest is not independently calculated off-chain; isolated Foundry tests separately reconstruct EIP-712 hashes with disposable test keys. The user-controlled import is not an authorization. A `CURRENT_UNSIGNED` result requires a new check before any future signature.
