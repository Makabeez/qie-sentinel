# QIE Sentinel v3.4 — Adversarial Wallet Compatibility

**Current milestone:** v3.4. The experimental multi-user vault factory is **undeployed**. The browser previews, live digest verification, and offline integrity lab do **not** authorize payments, verify real wallet signatures, or broadcast transactions. Disposable-key EOA and ERC-1271 signature verification runs only in Foundry tests.

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

Open [the 2.7 local test report viewer](http://127.0.0.1:8766/v2/lifecycle.html) in your existing localhost server and select the generated JSON. The viewer displays eleven test results but cannot authenticate an imported report.

The last command **actually runs** the 11 Foundry lifecycle tests before producing `C:\\Users\\VPS\\Downloads\\sentinel-v27-local-authorization-report.json` (via WSL mount). The JSON contains test names, commit, timestamp, Foundry version and explicit `LOCAL_FOUNDRY_EVM_ONLY` provenance. The report is user-generated and not cryptographically signed.

**Not implemented:** production wallet signing, a mainnet factory, authenticated executor, custody management, real-user deployment or a live payment. Keep PR #1 a draft until independent audit and a separate production architecture review.


## v2.8 — Security review and authorization-epoch finding

`test/SentinelV28SecurityReview.t.sol` exercises existing deployed-vault logic **only in the local Foundry EVM**: two-step ownership transfer, invalidation of old-owner signatures while a new owner remains active, policy revocation, lower spending limits, privileged paused recovery and full nonce/budget rollback on token transfer failure. It also demonstrates a **release-blocking design risk**: an unconsumed, unexpired signature may become executable again if the signer becomes owner once more, or if a previously authorized executor is reinstated. The current EIP-712 `Payment` payload has no authorization epoch. See [v2.8 threat findings](THREAT_MODEL.md) for proposed redesign requirements.

This is **not** an externally audited security assessment. The already deployed, verified v1.1 vault is unmodified; no on-chain issue is claimed to have occurred. **Do not** deploy the experimental factory or onboard real funds using this signed-data design before independent review and mitigation.

To run:

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
$HOME/.foundry/bin/forge test --match-contract SentinelV28SecurityReviewTest -vv
```


## v2.9 — Authorization epochs for irreversible signer rotation (NOT DEPLOYED)

The additional experimental `src/SentinelVaultV29.sol` introduces an epoch-bound EIP-712 `Payment` structure. A completed ownership transfer increases `ownerEpoch`, and each executor setter call increases `executorEpoch`. Both fields are cryptographically signed and checked during execution. Even if the earlier owner or executor is restored, their signatures from older epochs can no longer authorize payments. `test/SentinelV29Epoch.t.sol` exercises valid signatures, ownership and executor restoration, same-executor resets, tampering with the epochs, nonce revocation, and chain/vault domain separation using **only a local Foundry test EVM**.

This is a **new, incompatible** EIP-712 contract with domain `QIE Sentinel Vault V2`, version `2`; it does not upgrade or alter the deployed, verified v1.1 vault. The existing `SentinelVaultFactory` has deliberately **not** been rewired to deploy V29. There is no production signing or live deployment capability, and no independent audit.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
$HOME/.foundry/bin/forge test --match-contract SentinelV29EpochTest -vv
```

See the [v2.9 threat model](THREAT_MODEL.md) for outstanding release blockers.


## v3.0 — Independently owned epoch-protected vault factory (NOT DEPLOYED)

`src/SentinelEpochFactoryV30.sol` is a **separate experimental** factory which creates `SentinelVaultV29` vaults. It does not modify `SentinelVaultFactory.sol`, the submitted QIE Mainnet vault or existing PolicyGuard. Each local caller becomes the new vault owner, must specify a distinct executor, and receives an independent PolicyGuard with an empty initial recipient allowlist. The factory does not hold or transfer tokens, fund wallets, sign EIP-712 messages or own the resulting vaults.

`test/SentinelV30Factory.t.sol` checks two-user isolation, owner/executor roles, signature scope and replay prevention, restored owner/executor epoch invalidation, factory privilege restrictions, invalid inputs and creation history after ownership transfer. All assets are mock QUSDC; any `execute` calls occur only in Foundry's ephemeral EVM.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
$HOME/.foundry/bin/forge test --match-contract SentinelV30FactoryTest -vv
```

**Security boundary:** This factory and the 2.9 vault are unaudited and undeployed. Passing isolation tests does not establish safety of real assets or ownership onboarding. Do not merge into `main`, change the production website, sign transactions or deploy onto QIE Mainnet without independent audit and explicit new deployment plan.


## v3.1 — Stateful, randomized two-vault security invariants

The new Foundry `test/invariant/SentinelV31Invariant.t.sol` runs randomized **sequences** against both independent vaults using `test/invariant/SentinelV31Handler.sol`. The handler mixes legitimate owner-signed payments, executor rotations, two-step ownership transfers away and back, independent nonce cancellation, cross-owner signature attempts and unauthorized executor attempts. Whenever an attempt should be rejected, the handler asserts **no nonce or balance change**; state invariants compare both real balances against the accumulated successful-payment ledger.

The invariants continuously check **tenant isolation**, empty cross-tenant allowlists, each vault's daily budget, nonce/use accounting, conservation of mock QUSDC, independent owner/executor epochs and permanent invalidation of old owner signatures after a round-trip transfer.

The CI Foundry profile uses `fuzz.runs=1024` and `invariant.runs=256`, `depth=64`. These are finite simulations, **not formal proof and not an external audit**. All owners/keys and token balances are synthetic. The existing QIE Mainnet vault and production website are unchanged.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV31InvariantTest -vv
```


## v3.2 — Reproducible security audit handoff (not externally audited)

The [auditor handoff](../audit/V32_AUDITOR_HANDOFF.md) inventories the epoch-protected V29 vault, independent V30 factory, shared PolicyGuard, privileged roles and still-open deployment blockers. It includes a 12-item risk register and commands to reproduce the existing Foundry/Node tests. The assessment does **not** certify real-world safety or authorize live deployments.

The newly added `test/SentinelV32ContractOwner.t.sol` + `test/mocks/MockV32ContractOwner.sol` exercise ERC-1271 contract-wallet ownership on the epoch-protected V29 vault. Tests cover legitimate wallet signatures, wrong signer, revocation, signer rotation, executor epoch changes, nonce cancellation and cross-vault binding. It also deliberately demonstrates **R2**: rotating an ERC-1271 wallet's *internal* signer away and back may revive an unconsumed, unexpired signature without updating the vault owner epoch. Explicit nonce cancellation prevents this specific replay, but an audited design must address this more generally.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV32ContractOwnerTest -vv
bash scripts/verify-v2.sh
```

This project remains local-test-only, experimental and **NOT production ready**. No QIE Mainnet contract was changed.


## v3.3 — Compatible contract-wallet signer epoch binding (NOT DEPLOYED)

The independent `src/SentinelVaultV33.sol` prototype adds a signed `signerEpoch` field for contract-wallet owners. The required optional wallet interface is `src/interfaces/ISentinelOwnerSignerEpoch.sol`. A compatible wallet must expose a truthful monotonic `signerEpoch()` that advances on **every authorization-relevant wallet change**. Unrecognized ERC-1271 wallets fail closed. EOAs use signer epoch zero. The EIP-712 domain is deliberately changed to `QIE Sentinel Vault V3`, version `3`; signatures from earlier versions are incompatible.

`test/SentinelV33SignerEpoch.t.sol` and `test/mocks/MockV33EpochWallet.sol` demonstrate prevention of old signatures reviving after internal signer restoration, re-signing at the new epoch, tamper rejection, nonce cancellation, explicit owner/executor epochs and unsupported-wallet rejection. This is a **conditional mitigation**: a dishonest or buggy ERC-1271 wallet can expose false/nonmonotonic epochs. It does not prove support for arbitrary smart accounts.

The v3.0 factory still deploys the **V29** vault, not V33. There is no V33 factory, production onboarding, live signing or deployment. See [v3.3 design and remaining blockers](../audit/V33_SIGNER_EPOCH_DESIGN.md).

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV33SignerEpochTest -vv
bash scripts/verify-v2.sh
gh pr checks 1
```


## v3.4 — Adversarial ERC-1271 compatibility review (NOT DEPLOYED)

`test/mocks/MockV34AdversarialWallet.sol` simulates malicious or unavailable contract-wallet behavior. `test/SentinelV34WalletCompatibility.t.sol` demonstrates the **still-open** signer-epoch trust problem by freezing the reported epoch across a signing-key rotation and then accepting a revived historical signature. Other local tests assert rejection without state changes when epoch reads fail, ERC-1271 validation reverts, or the wallet returns an invalid signature; they also check explicit nonce cancellation, owner-only emergency recovery and controller restrictions.

The experimental V33 vault has **not** been changed or declared universally safe. A plain ERC-1271 contract reporting `signerEpoch()` is not enough to guarantee safe authorization. A versioned and independently reviewed wallet allowlist and implementation-specific security assessment are necessary before any live wallet integration. See [v3.4 compatibility and release criteria](../audit/V34_WALLET_COMPATIBILITY.md).

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV34WalletCompatibilityTest -vv
bash scripts/verify-v2.sh
gh pr checks 1
```

**No production assets, external signing, or QIE Mainnet deployments. Do not merge this draft PR.**
