# QIE Sentinel 2.5 — Offline authorization security lab

**Experimental branch only:** `feat/v2-owner-approval`. Original submitted `main`, verified Mainnet vault and owners are unchanged.

### What is implemented

1. **Pure-browser integrity lab:** `v2/crypto-lab.html` accepts an already unsigned Section 06 packet from your Downloads folder, computes its EIP-712 digest using the standalone Keccak module and demonstrates why changing amount, nonce, recipient, deadline or executor changes the commitment. Wrong chain or vault addresses are rejected. This runs entirely in the browser with **no wallet, signing or RPC**.
2. **Foundry EOA security tests:** `test/SentinelOfflineSignature.t.sol` uses disposable deterministic test keys to verify signatures and reject modified fields, wrong chain, wrong vault and wrong owner.
3. **Foundry ERC-1271 contract wallet tests:** `test/SentinelSignatureLab.t.sol` creates a separate test-only vault owned by a mock revocable ERC-1271 contract; exercises valid signatures, revocation, signer rotation, wrong signer, changed amounts, replay, expiry, nonce invalidation and controller isolation. Test transactions are simulated on local Foundry EVM, **not broadcast on QIE Mainnet**.

### Test locally on your Windows machine

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
node --test v2/test-*.mjs
node --check v2/lab-v25.mjs
export PATH="$HOME/.foundry/bin:$PATH"
bash scripts/install-deps.sh
forge test --match-contract SentinelSignatureLabTest -vv
forge test --match-contract SentinelOfflineSignatureTest -vv
bash scripts/verify-v2.sh
```

Open [the local crypto lab](http://127.0.0.1:8766/v2/crypto-lab.html) with your existing server on port 8766. Use `C:\Users\VPS\Downloads\sentinel-v2-unsigned-eip712.json`, then select a mutation and click **Compare EIP-712 commitments**.

**Important:** The browser only proves that data tampering alters the digest. It **does not** verify a signature. The Foundry tests verify signatures strictly using nonproduction test keys. There is no production signing, no mainnet execution and no signature payload exported to an executor.

### Remaining security gates

- Independent code review and contract audit before any user-owned vault deployment.
- Real user-owned vault onboarding isolated from the submission vault.
- Explicit, audited EIP-712 wallet consent UX, plus authenticated signature validation and revocation.
- Secure executor design and scoped, durable audit records.
