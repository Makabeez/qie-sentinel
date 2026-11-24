# QIE Sentinel v2 — independent reviewer prototype

**Branch:** `feat/v2-owner-approval` — v1.1 submitted hackathon release remains on `main`.

This is the **first read-only stage**, not a live approval or multi-tenant treasury application. Open `v2/index.html` using a local HTTP server to ensure ES modules load. The app requires direct internet connectivity to QIE Mainnet RPC and does not send data to any other server.

## Windows folder conventions

- Working project: **`C:\\Github\\qie-sentinel`** (WSL: **`/mnt/c/Github/qie-sentinel`**).
- Any new projects or separate worktrees: **`C:\\Github\\<project-folder>`**.
- Downloads: **`C:\\Users\\VPS\\Downloads`** (WSL: **`/mnt/c/Users/VPS/Downloads`**).
- Keep the original submitted repository on `main` and create a separate working tree at **`C:\\Github\\qie-sentinel-v2`**. This avoids changing files used by your running local PM2 dashboard.

## Try it
```bash
cd /mnt/c/Github/qie-sentinel
git fetch origin
git worktree add /mnt/c/Github/qie-sentinel-v2 feat/v2-owner-approval
cd /mnt/c/Github/qie-sentinel-v2
node --test v2/test-*.mjs
node --check v2/app.mjs
python3 -m http.server 8766 --bind 127.0.0.1
# Browse http://127.0.0.1:8766/v2/
```

Try allowed recipient `0xce99cF8EdfD199dB02b830445d89E746B8c1C7ff`, `0.05` QUSDC, unused nonce `3` (subject to actual chain state). Then try unknown recipient, `1.000001` QUSDC, used nonce `1`, and expired deadline.

Review the JSON download, especially `disclaimer`, `block`, `viewer`, and `result`.

## Security boundary
- Optional EIP-1193 wallet `eth_requestAccounts` **only on explicit button click**, checks chain ID 1990. No signing, permissions to spend, wallet network change, or transaction call.
- Policy reads use a **pinned block** and directly query existing verified QIE Mainnet contracts.
- Invalid inputs, outages, unknown reverts or chain mismatch **fail closed**. Browser never creates a signed payment.
- Read-only assessment is *not* an execution simulation: signature, executor authorization, token/contract changes and other constraints may prevent execution.
- Reviewer address is informational only. The **existing vault still belongs to its existing owner**. This release does not deploy user vaults or allow unrelated wallets to authorize the existing vault.
- Browser can export a **user-controlled local JSON review**; no server-side audit storage or payment-history database.
- No independent security audit, no production custody and no user onboarding claim.

## Testing
```bash
node --test v2/test-policy.mjs
node --check v2/app.mjs
python3 scripts/check-public-site.py
```

## v2.1 independent vault planning (experimental)

The page now includes a **user-owned vault configuration preview**. Connect a QIE Mainnet EVM wallet (account identity only), enter a **different** executor wallet, and set a per-transfer and UTC-day QUSDC limit. The form checks address validity, owner/executor separation, amount precision and spending constraints and downloads a `PREVIEW_ONLY_NOT_DEPLOYED` JSON file.

A separate Solidity contract, [`SentinelVaultFactory`](../src/SentinelVaultFactory.sol), creates a new `SentinelVault` and `PolicyGuard` for each caller. This factory is **source code only** and has **not been deployed**. It neither funds nor administers a user's vault. The project's existing v1.1 vault is unchanged.

Check the [v2.1 threat model](THREAT_MODEL.md), especially factory/token identity, signature authority, cross-user isolation, and required audits.

```bash
cd /mnt/c/Github/qie-sentinel-v2
bash scripts/verify-v2.sh  # Runs Node tests, public-site checks, Foundry build and factory isolation tests
```

## Next development stage (not yet implemented)
Onboard independently controlled vaults via audited factory, wallet EIP-712 typed-data approval and an authorized executor service with authentication, replay-safe audit storage, explicit user consent and transaction previews. No use of submitted vault's owner keys for third-party accounts.
