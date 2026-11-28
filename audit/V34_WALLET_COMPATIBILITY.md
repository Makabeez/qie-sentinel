# Sentinel 3.4 — ERC-1271 compatibility decision and hostile-wallet test evidence

**Status:** experimental only; NOT externally audited, NOT deployed, NOT approved for assets.
**Scope:** `SentinelVaultV33` prototype and optional `ISentinelOwnerSignerEpoch` interface, not the original deployed QIE vault.

## Key result: an epoch getter is NOT sufficient to prove safety

In `test/SentinelV34WalletCompatibility.t.sol`, a deliberately dishonest contract wallet freezes its `signerEpoch()` while rotating signing keys away and back. This allows an old, unexpired and unconsumed payment authorization to become valid again. V33 **cannot** detect this if the contract wallet lies or fails to increment its reported epoch. The passing test `testV34FrozenEpochRevivesPriorSignature_RiskConfirmed` is **an explicit vulnerability demonstration**, not a security success.

The earlier V33 signer-epoch mitigation is effective **only for trusted, compatible wallet implementations** where all changes that affect authorization MUST monotonically advance the epoch (including signer/module/validator/threshold/upgrade/recovery changes). A wallet can report a constant epoch while satisfying the function signature, so a superficial capability check cannot validate that requirement.

## Compatibility policy — proposed, NOT enforced on chain

| Owner wallet class | Current experimental V33 behavior | Production decision |
|---|---|---|
| EOA, with demonstrably controlled private key | Uses `signerEpoch=0`, owner/executor epochs still apply | Candidate subject to regular custody / signing review |
| Known, independently audited ERC-1271 wallet with non-resettable epoch on *all* authorization mutations | Current epoch included in signed payment | Candidate **only** following exact-code verification and signer lifecycle threat analysis |
| ERC-1271 lacking `signerEpoch()` or reverting on read | V33 reverts `UnsupportedContractOwner` for execution | Reject |
| ERC-1271 that freezes, resets, lies, allows arbitrary modules to sign without increasing epoch, or exposes unreviewed upgrades | May revive historical signatures | Reject — high-severity blocker |
| Unknown account-abstraction / proxy wallet or modular validator | No reliable monotonicity guarantee from interface alone | Reject pending independent implementation-specific assessment |
| Wallet with unavailable/reverting ERC-1271 signature check | Payment fails closed, no nonce or budget consumed | Operational outage, require owner recovery procedure |
| Wallet that returns incorrect ERC-1271 magic value | Payment rejected without burning nonce | Reject/diagnose |

## Controls that still work for a dishonest contract-wallet owner

- Explicit `invalidateNonces` marks particular payment nonces used, even when signer history reverts. Requires owner/admin path to be available.
- `pause` prevents execution and permits **owner-only** `emergencyRecover` beyond the recipient allowlist and guard spending limits. This is powerful custody authority and remains a separately disclosed risk.
- Reverting epoch getter prevents payment execution; reverting signature checker and incorrect magic values also result in rejected payment and unchanged budget.
- These controls do not prevent a **compromised owner controller** from changing its wallet behavior and authorizing transfers. They do not prove a hostile wallet cannot lie about authorization state.

## Release blockers

1. Define a reviewed and immutable (or strictly upgrade-controlled) wallet implementation; require verified runtime bytecode/implementation address and independent audit. UI must never use `signerEpoch()` support as the sole eligibility test.
2. Test authorization epochs against all signer, module, threshold, validator and account-recovery operations for the exact supported wallet implementation, including rotations away and back.
3. Require explicit owner nonce cancellation (or separate vault-owned revocation epochs) during risky wallet changes, backed by a trustworthy administrative path; test against wallet recovery and compromised admin cases.
4. Independently review EIP-712 encoding and typed-data display, ERC-1271 calls, reentrancy, malicious token behavior, gas griefing and factory owner controls.
5. Document service availability and break-glass recovery when signer-epoch reads fail. No silent fallback to unsigned or stale intents.
6. **No new factory or mainnet deployment**; the existing V30 factory still deploys V29, and the original main branch remains the hackathon submission.

## Local verification

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV34WalletCompatibilityTest -vv
bash scripts/verify-v2.sh
gh pr checks 1
```

All test wallets, assets and signature keys are disposable in the local Foundry EVM. A green result certifies **test assertions only**, not production security.
