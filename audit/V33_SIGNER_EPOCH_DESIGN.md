# Sentinel 3.3 — ERC-1271 signer epoch design (experimental)

**Status: experimental, not deployed, not audited.** Existing source-verified v1.1 on QIE Mainnet, legacy `SentinelVault.sol`, `SentinelVaultV29.sol`, factories and submitted `main` are unchanged.

## Problem

The v3.2 test `testV32ContractWalletSignerRestorationReactivatesUncancelledIntent` proves that an ERC-1271 wallet may rotate its signer away and back without any ownership event on the vault. An older, unconsumed, unexpired signature can then verify again. The V29 owner/executor epoch counters cannot detect these wallet-internal changes.

## Experimental v3.3 compatibility contract

- New `src/SentinelVaultV33.sol` is a **separate vault**, not an upgrade or replacement of any existing deployment.
- Contract-wallet owners MUST implement `src/interfaces/ISentinelOwnerSignerEpoch.sol` and return a monotonically increasing `signerEpoch()`. The vault rejects owner contracts lacking the interface.
- Payment signatures bind `signerEpoch` alongside `ownerEpoch`, `executorEpoch` and all previously bound fields.
- Domain is deliberately changed to `QIE Sentinel Vault V3`, version `3`, preserving chain-ID and verifying-contract separation. Legacy signatures are incompatible.
- EOA owners use a signer epoch of zero and retain owner/executor epoch protections.
- The test-only `MockV33EpochWallet` increases its signer epoch on **every** signer rotation, even if an earlier signer is restored. Replaying a signature from an earlier signer epoch is rejected without burning nonce or spending tokens.
- The existing `SentinelEpochFactoryV30` **does not** deploy v3.3. There is no production factory, wallet integration, or on-chain execution for this experiment.

## Trust limitation and outstanding risks

**This only works for compatible, trustworthy contract wallets.** A vault cannot observe arbitrary ERC-1271 internal signer or module changes if the owner wallet does not publish a truthful, monotonic version. A malicious or poorly implemented wallet can lie, reset the counter, or reenable old signatures, so `signerEpoch()` is not a universal cure. A production onboarding process would need explicit wallet compatibility validation, trusted reviewed wallet implementations, signer-change monitoring and a fail-closed policy.

The mock changes its epoch on signer rotation only. Actual production wallets must increment on **every authorization-relevant change**, including enable/disable modules, upgrade of validators, threshold changes, policy changes and recovery. Review account-abstraction and upgrade paths separately.

Test ERC-1271 compatibility, token behavior, ownership transfer, recovery, reentrancy, EIP-712 off-chain encoding, owner/executor distinction, and formal invariants before any production use. An independent audit is still mandatory.

## Local tests (no keys, signatures or transactions on QIE Mainnet)

```bash
cd /mnt/c/Github/qie-sentinel-v2
git pull --ff-only origin feat/v2-owner-approval
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV33SignerEpochTest -vv
bash scripts/verify-v2.sh
gh pr checks 1
```

**Do not deploy this version to Mainnet, merge the draft PR or use real tokens.**
