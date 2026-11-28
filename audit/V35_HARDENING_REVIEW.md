# Sentinel 3.5 — Experimental role and token-transfer hardening

**Status: local security prototype, NOT deployed, NOT audited, NOT suitable for real assets.** Changes are limited to the experimental `feat/v2-owner-approval` branch. No existing vault, factory, token, submitted `main` code or production site is modified.

## New separate vault

`src/SentinelVaultV35.sol` is an independent prototype derived from `SentinelVaultV33`. EIP-712 domain changed to `QIE Sentinel Vault V4` version `4`; previous signatures are intentionally incompatible. There is no V35 deployment factory and no actual QIE transaction.

### Controls added

- **Persistent owner/executor separation:** Reject matching owner and executor at constructor and executor setter, and block ownership acceptance by the current executor. Ownership nomination may remain pending but cannot become effective while the conflict exists. Current owner retains all administrative/recovery powers. This is role separation, **not** protection against a compromised owner key.
- **Exact transfer checks:** For `execute`, measure both vault debit and recipient credit around ERC-20 transfer; revert unless both equal signed `payment.amount`. Reverts atomically roll back nonce, guard daily spend and token transfer. Vault-to-itself payments are explicitly rejected. This prevents a *well-behaved* fee-on-transfer token from silently delivering less than the signed amount.
- **Emergency recovery preserved:** Owner-only, while paused, bypasses policy recipient allowlist and daily limits as an explicit privileged escape hatch. This is still a material custody power and risk.

### Explicit limitations

- Balance checks add two external token `balanceOf` reads before and after each transfer. These can increase gas, cause gas griefing, or revert; nonstandard/malicious tokens can report deceptive values, alter other balances or supply, rebase asynchronously or use callbacks. Exact balance deltas **do not establish official QUSDC identity**.
- Strict balance-delta requirements may reject some otherwise legitimate tokens; token allowlisting and chain-specific provenance remain a necessary precondition.
- A malicious/ERC-1271 wallet can still lie about its `signerEpoch` as established in [the v3.4 wallet review](V34_WALLET_COMPATIBILITY.md). Owner and signer custody remain the highest-priority trust assumptions.
- Existing `SentinelEpochFactoryV30` still creates `SentinelVaultV29`, **not** V35. Do not conflate prototypes, test passing status or demonstration assets with real deployment readiness.
- This prototype does not solve ERC-20 reentrancy across other contracts, off-chain signing UX, wallet upgrades, executor infrastructure, chain fork replay or approval management without an independent audit.

### Regression evidence

`test/SentinelV35Hardening.t.sol` tests normal exact transfers, constructor and setter owner/executor conflicts, blocked ownership acceptance, valid transfer to independent owner, self-recipient rejection, mock 10% transfer fee with atomic rollback, pause-before-owner-recovery and unauthorized recovery. `test/mocks/MockV35FeeToken.sol` deliberately burns part of each transfer; it is a synthetic test fixture, not QUSDC.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV35HardeningTest -vv
bash scripts/verify-v2.sh
gh pr checks 1
```

**Release remains blocked:** independent auditor review, trusted wallet implementation, token verification, operational recovery design and test-only end-to-end integration. Never deploy from this experimental branch without a separately authorized release.
