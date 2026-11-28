# Sentinel 2.4 verification

The browser verifier is at **http://127.0.0.1:8766/v2/verify.html**.

In WSL:
```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
node --test v2/test-*.mjs
node --check v2/verify-v24.mjs
```
Keep your server on port 8766 running, then open the link above.

Import `C:\Users\VPS\Downloads\sentinel-v2-unsigned-eip712.json`.

This is a read-only check of QIE Mainnet contract digest, domain, owner, executor, token, nonce, PolicyGuard, deadline and balance at a single block. The v2.4 browser independently computes Ethereum Keccak-256, the EIP-712 domain separator, the Payment struct hash and the final digest; both the digest and domain separator must match on-chain. **No signature, wallet control or transaction is verified.** The off-chain digest and domain separator are independently calculated in the browser; regression tests compare them with recorded QIE Mainnet evidence and standard Ethereum Keccak test vectors. Isolated Foundry tests separately validate signatures with disposable test keys. The user-controlled import is not an authorization. A `CURRENT_UNSIGNED` result requires a new check before any future signature.
