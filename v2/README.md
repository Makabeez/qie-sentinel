# QIE Sentinel v2.7 — Experimental Independent Vault & Authorization Lifecycle Lab

**Current milestone:** v2.7. The experimental multi-user vault factory is **undeployed**. The browser previews, live digest verification, and offline integrity lab do **not** authorize payments, verify real wallet signatures, or broadcast transactions. Disposable-key EOA and ERC-1271 signature verification runs only in Foundry tests.

**Entry points:** `v2/index.html` (policy / unsigned proposal), `v2/verify.html` (pinned on-chain digest check), `v2/crypto-lab.html` (offline tamper lab) and `v2/owner-review.html` (digest-bound human risk acknowledgement, **not authorization**). See [Signature Lab](SIGNATURE_LAB_README.md), [Verifier](VERIFY_README.md), and [Threat Model](THREAT_MODEL.md).

**Branch:** `feat/v2-owner-approval` — v1.1 submitted hackathon release remains on `main`.

This remains an **experimental development branch**, not a live approval or multi-tenant treasury application. Open `v2/index.html` using a local HTTP server to ensure ES modules load. The app requires direct internet connectivity to QIE Mainnet RPC and does not send data to any other server.

## Windows folder conventions

- Working project: **`C:\Github\qie-sentinel`** (WSL: **`/mnt/c/Github/qie-sentinel`**).
- Any new projects or separate worktrees: **`C:\Github\<project-folder>`**.
- Downloads: **`C:\Users\VPS\Downloads`** (WSL: **`/mnt/c/Users/VPS/Downloads`**).
- Keep the original submitted repository on `main` and create a separate working tree at **`C:\Github\qie-sentinel-v2`**. This avoids changing files used by your running local PM2 dashboard.

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

## v2.2 — exact EIP-712 authorization preview (UNSIGNED)

After connecting the **recorded demonstration-vault owner wallet** and completing an eligible live policy review, section 06 can export an **unsigned EIP-712 Payment packet**. This packet uses exactly the deployed `SentinelVault.Payment` field order and `EIP712("QIE Sentinel Vault","1")` domain:

- Domain: QIE Mainnet chain 1990, existing verified demonstration vault `0xb752F05a55059C89a43a289d5d055F303B6DD96E`.
- Message: `token, recipient, amount (raw six-decimal units), nonce, deadline (Unix seconds), executor`.
- State: `UNSIGNED_NOT_AUTHORIZED`, `signature: null`, `notBroadcast: true`.
- Editing any input invalidates the live review; a new evaluation is required.
- The payment reason/invoice description is **not** part of the signed Solidity Payment and is not cryptographically bound.
- The owner and executor are the *historically recorded* demo-vault participants; they must be checked again on-chain before any future real transaction.
- This is **not** a wallet signing tool, transaction simulation, durable approval queue, or actual authorization. No external account can sign for the existing demo vault.

Tests:

```bash
cd /mnt/c/Github/qie-sentinel-v2
node --test v2/test-*.mjs
node --check v2/app.mjs
bash scripts/verify-v2.sh
```

## Next development stage (not yet implemented)
Onboard independently controlled vaults via audited factory, wallet EIP-712 typed-data approval and an authorized executor service with authentication, replay-safe audit storage, explicit user consent and transaction previews. No use of submitted vault's owner keys for third-party accounts.


## v2.6 — Human risk review (no signing)

The experimental `owner-review.html` imports both an **unsigned EIP-712 packet** and its **v2.4 verification JSON**, checks digest/domain binding and six explicit user risk acknowledgements, then exports `ACKNOWLEDGED_NOT_AUTHORIZED`. Both files are user-controlled and may be fabricated or stale; no wallet ownership or real authorization is established. It never calls a wallet or broadcasts a transaction.

Do not confuse a generated checklist with an owner signature. Tests: `node --test v2/test-owner-review*.mjs`.


## v2.7 — Disposable-key owner authorization lifecycle

The Foundry test suite `test/SentinelV27Lifecycle.t.sol` creates two **distinct, locally simulated** user-owned vaults through the experimental factory, with separate owners, executors, PolicyGuards and simulated token balances. It demonstrates EIP-712 owner signing and executor-submitted payment **only inside the local test EVM**. Tests reject unauthorized executor, wrong owner, cross-vault signatures, replay/cancelled nonces, expired intent, rotated executor, paused vault, exceeded daily budget and unauthorized policy changes. No real owner key is requested or imported.

Run from WSL in `C:\\Github\\qie-sentinel-v2`:

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
python3 scripts/run-v27-lab.py
```

The last command **actually runs** the 11 Foundry lifecycle tests before producing `C:\\Users\\VPS\\Downloads\\sentinel-v27-local-authorization-report.json` (via WSL mount). The JSON contains test names, commit, timestamp, Foundry version and explicit `LOCAL_FOUNDRY_EVM_ONLY` provenance. The report is user-generated and not cryptographically signed.

**Not implemented:** production wallet signing, a mainnet factory, authenticated executor, custody management, real-user deployment or a live payment. Keep PR #1 a draft until independent audit and a separate production architecture review.
