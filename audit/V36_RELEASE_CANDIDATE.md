# QIE Sentinel 3.6 — Frozen Audit Candidate and Release Decision

**Status: AUDIT CANDIDATE ONLY — NOT PRODUCTION READY.**
**Scope branch:** `feat/v2-owner-approval` · **PR:** #1 (must stay DRAFT).
**Intended use:** independent code review and local mock-token reproduction. No live signing or on-chain deployment is authorized by this document.

## Product state and explicit finalization boundary

The **2026 hackathon v1.1** is the submitted and historically deployed demonstration. Its original main branch, verified QIE Mainnet vault + guard, original owner/executor, public website and curated on-chain receipts are outside this candidate. No implication is made that the original contract is upgraded or that the v3.6 candidate has users, production funding or a running agent service.

The **experimental branch** includes multiple research contracts intentionally preserved for security regression tests, but **only one is the proposed audit target**:

| Source | Disposition | Reason |
|---|---|---|
| `src/SentinelVaultV35.sol` | **PROPOSED AUDIT TARGET** | Owner/executor separation, signer/owner/executor epochs, exact-delivery pre/post balance checks |
| `src/PolicyGuard.sol` | **PROPOSED AUDIT TARGET** | Per-vault allowlist, max-per-transfer, UTC-day budget |
| `src/interfaces/ISentinelOwnerSignerEpoch.sol` | **AUDIT INTERFACE** | Contract-owner signer epoch dependency, not a certification of wallets |
| `src/SentinelEpochFactoryV36.sol` | **PROPOSED AUDIT TARGET** | Separate permissionless test factory deploying **V35**, not deployed; records creators, not current owners |
| `src/SentinelEpochFactoryV30.sol` | **HISTORICAL EXPERIMENT, NOT RELEASE FACTORY** | Deploys `SentinelVaultV29`, **not** V35; never use for candidate |
| `src/SentinelVault.sol` / `src/SentinelVaultFactory.sol` | **LEGACY REFERENCE** | Original v1.1-era signed schema; never silently substitute |
| `src/SentinelVaultV29.sol`, `src/SentinelVaultV33.sol` | **EXPERIMENTAL PREDECESSORS** | Distinct signatures, earlier security designs; not audit target |
| `v2/` browser UI | **PREVIEW ONLY** | Read-only original-chain verification and unsigned demonstrations; does not sign for V35 |
| `test/` and `audit/` | **EVIDENCE & AUDIT NOTES** | Tests are reproducible evidence, not a proof or auditor certification |

**The separate V36 factory deploys V35 in local tests**, but remains unaudited, undeployed, and does not attest that the constructor token is official QUSDC. **No V35 production EIP-712 frontend or secure executor exists.** The candidate can therefore be finalized as a **security research deliverable**, not launched as a multi-user treasury product.

## Frozen candidate contract specification

- **Compiler:** Solidity 0.8.24, EVM Paris, optimizer 200. Pin the actual Foundry/OZ/Forge Std revisions in the external auditor report.
- **Domain:** `QIE Sentinel Vault V4`, version `4`, runtime chain ID, *individual V35 vault address*.
- **Signed Payment:** `token,recipient,amount,nonce,deadline,executor,ownerEpoch,executorEpoch,signerEpoch` in that order.
- **Owner:** one EOA or ERC-1271 contract owner, controlled externally. Contract owners must implement a truthful monotonic `signerEpoch()`; unsupported wallets fail closed for payment execution.
- **Executor:** distinct from current owner on construction, rotation, and completed ownership transfer. Executor cannot sign merely by holding its role.
- **PolicyGuard:** new instance per vault; owner manages recipients and limits through vault; policy budget uses UTC `block.timestamp / 1 days`.
- **Nonce:** permanent bitmap consumption, explicit cancellation available even when paused. Ownership/executor rotation increments signed epochs.
- **Transfer:** nonce and policy budget consumed atomically with token `safeTransfer`; checks before/after recipient and vault balances for exact payment amount; rejects self-recipient.
- **Recovery:** owner may pause and transfer assets to an arbitrary nonzero recipient, outside the payment policy. This is by design and a privileged custody risk.
- **Factory:** `SentinelEpochFactoryV36.sol` is selected for audit **only**; deploys V35 per caller, uses an arbitrary constructor token, keeps historical creator registration. Do not deploy or reuse V30.

## Findings / release blockers and owners

| Gate | Status | Required work before real value |
|---|---|---|
| G1 Independent external audit of V35/Guard/interface + token behavior | **OPEN** | Third-party review, remediation, re-audit and signed report |
| G2 Trustworthy compatible ERC-1271 wallet | **OPEN** | Verify exact wallet implementation; monotonic epoch across signer/validator/module/recovery/upgrade changes; disallow unknown wallets |
| G3 V35 factory and chain/token validation | **PARTIAL — OPEN** | V36 factory/source and local integration tests added; independent audit, chain/token identity checks, and versioned deployment process still required |
| G4 Human-readable EIP-712 V4 signing UX | **OPEN** | Independent vectors, phishing defense, correct domain/field rendering and owner approval |
| G5 Authenticated executor and key operations | **OPEN** | Non-custodial design, key rotation, idempotency, incident monitoring, rate limiting, secrets management |
| G6 Adversarial token and callback review | **OPEN** | Nonstandard balances, fee/rebase/hook/reentrancy/gas-griefing tests; actual QUSDC verification |
| G7 Owner emergency recovery and access loss | **OPEN** | Security runbook, guardian/multisig assessment, lost-owner mitigation and handling of renounce |
| G8 Local unit, randomized and regression suites | **AUTOMATED** | Must be green on frozen SHA, including `SentinelV35HardeningTest` and signer-epoch attack demonstrations |
| G9 Production web / user onboarding and operational rollout | **OPEN** | No real wallet signing, funding or deployment until all previous gates explicitly approved |

**Critical caveat:** adversarial `testV34FrozenEpochRevivesPriorSignature_RiskConfirmed` intentionally succeeds in demonstrating that a *dishonest* ERC-1271 wallet can revive an old signature. It is not an invariant that V35 can solve for arbitrary wallets. Never describe all tests passing as a guarantee for unknown smart accounts.

## Release decision

**Decision: NO-GO FOR MAINNET / LIVE FUNDS.** The experimental contracts are **audit candidate** code only. Keep PR #1 **draft and unmerged**, retain the original mainnet v1.1 as the publicly demonstrated artifact, and do not run `forge script --broadcast` or supply private keys, seed phrases or production RPC credentials.

**Definition of project finalization at this stage:** one identified auditable vault specification, honest account of open release gates, reproducible tests, a local V36 factory integration, a controlled audit manifest, and a clean preserved public demonstration. This is a meaningful finished R&D deliverable, distinct from final authorization to launch a treasury service.

## Verify in offline-only mode

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
bash scripts/verify-v2.sh
bash scripts/check-rc-v36.sh
gh pr checks 1
```

`check-rc-v36.sh` is a local gate, not a signed attestation: it checks the selected scope and runs Foundry build/tests and project checks, never deploys or signs. Record `git rev-parse HEAD`, CI links and any findings in the independent audit report.

## Source of truth

- [v3.5 hardening](V35_HARDENING_REVIEW.md)
- [v3.4 wallet compatibility](V34_WALLET_COMPATIBILITY.md)
- [v3.3 signer epoch trust model](V33_SIGNER_EPOCH_DESIGN.md)
- [v3.2 auditor inventory](V32_AUDITOR_HANDOFF.md)

This document intentionally does **not** declare an external audit, asset protection guarantee, official token certification, customer onboarding or product deployment.
