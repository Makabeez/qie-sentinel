# QIE Sentinel 3.2 — External Security Review Package

**Review status:** internally prepared; **NOT externally audited, NOT production ready, NOT deployed**. 
**Repository:** `Makabeez/qie-sentinel` · **branch:** `feat/v2-owner-approval` · **PR:** #1 (draft).
**Scope:** review only the proposed v2.9/v3.0 architecture listed below. `main` and the historical QIE Mainnet v1.1 demo are not being upgraded.

## Scope and source inventory

| Source | Purpose | Principal trust assumptions |
|---|---|---|
| `src/SentinelEpochFactoryV30.sol` | Permissionless deployment of isolated user-owned V29 vaults; creator history | Constructor token address is genuine; creator is legitimate wallet and uses an independent executor |
| `src/SentinelVaultV29.sol` | Holds one ERC-20, verifies EIP-712 owner signature, enforces epochs and nonces; transfers and emergency recovery | Owner key / ERC-1271 wallet trustworthy; executor key separate; ERC-20 token conforms to expected behavior |
| `src/PolicyGuard.sol` | Per-vault recipient allowlist, per-transfer limit, UTC-day budget | Vault is the only policy controller; timestamp policy is acceptable |
| OpenZeppelin v5 dependencies | Ownership (Ownable2Step), EIP712, SignatureChecker, SafeERC20, Pausable, ReentrancyGuard | Exact pinned dependency source and compiler outputs are verified by reviewer |

**Out of scope but relevant:** old `src/SentinelVault.sol` and `src/SentinelVaultFactory.sol`, original hackathon v1.1 website, experimental read-only `v2/` interface, a hypothetical production executor, live RPC, wallet adapters, infrastructure, token/chain governance and custody operations. These areas **must** be independently evaluated before any production launch.

**Protocol:** EVM-compatible chain; local tests set `block.chainid=1990` but send **no QIE network transactions**. Experimental V29 EIP-712 domain is name `QIE Sentinel Vault V2`, version `2`, runtime chain ID and vault address. The `Payment` type additionally signs token, recipient, amount, nonce, deadline, executor, ownerEpoch and executorEpoch. It is **not** backward-compatible with the deployed legacy vault.

## Authority and privileged-role matrix

| Actor | May create vault | May configure allowlist/limits | May rotate executor / transfer ownership | May sign payment | May submit payment | May pause and recover |
|---|---|---|---|---|---|---|
| Any external wallet | Yes, for itself | No for another owner's vault | No for another owner's vault | Only if current vault owner or valid ERC-1271 owner signature | Only if configured executor | No for another owner's vault |
| Current vault owner (EOA or ERC-1271 contract) | Yes | Yes | Yes (two-step transfer) | Yes | Only if also configured executor; factory rejects owner=executor **at creation** | **Yes**, owner recovery bypasses guard budget/allowlist |
| Current configured executor | Yes, for itself | No | No | No owner-signing rights by role alone | **Yes**, with valid signed intent only | No |
| Factory contract | No independent user authority | No | No | No | No | No |
| PolicyGuard | No | Only its particular vault can call mutators | No | No | No | No |
| Advisory AI / web UI | No on-chain rights by itself | No | No | No | No | No |

**Important:** V29 `setExecutor` currently permits assigning the owner as executor *after deployment*. This does not bypass signature checks but changes intended separation-of-duties. An external reviewer must decide whether separation should be enforced for every rotation and how to enforce it for contract owners.

## Open risk register (NOT resolved by passing tests)

| ID | Priority | Finding / assumption | Required auditor question / remediation |
|---|---|---|---|
| R1 | High | Factory constructor verifies token has code, **not** official QUSDC identity, decimals, token upgradeability or fee/rebase behavior | Evaluate token allowlisting, chain-specific deployments, governance and unusual ERC-20 callbacks |
| R2 | High | Contract-wallet/ERC-1271 signature validity can change without a V29 `ownerEpoch` change, e.g. signing key rotates away and back inside the owner wallet | Determine how to permanently revoke previously signed intents for contract wallets; vault owner/admin or wallet must explicitly cancel nonces/advance epoch |
| R3 | High | Owner may pause and recover *any amount* to an arbitrary nonzero address, bypassing allowlist/daily limit | Validate owner custody disclosure, multisig/timelock policy, safe recovery UX, key compromise procedures |
| R4 | Medium | `setExecutor` accepts owner itself post-deployment; the factory enforces distinct accounts only at creation | Decide and test ongoing separation-of-duty invariant |
| R5 | Medium | Signing scope binds exact transaction fields and epochs, **not** payment reason, invoice or intended business purpose | Review phishing/misleading-proposal risks; determine need for payment metadata commitment |
| R6 | Medium | Daily limit is defined by UTC `block.timestamp / 1 days`; per-day budget resets at UTC midnight | Validate expected business semantics, timestamp tolerance, race conditions around boundary |
| R7 | Medium | Factory's creator-history mapping is not a reliable current ownership portfolio after Ownable2Step transfer | Index owner events/read `owner()` at a pinned block; avoid misleading UI |
| R8 | Medium | ERC-20 transfer failure reverts nonce/budget atomically; unusual tokens, hooks, fees, or upgradeable behavior not modeled comprehensively | Audit adversarial token mocks and reentrancy/external-call ordering |
| R9 | Medium | No authenticated executor backend, transaction simulation, signer attestation, risk engine, queue management, idempotency or alerting | Production infrastructure architecture + adversarial operational threat model are separate review gates |
| R10 | Medium | **Test coverage is finite** and mostly synthetic EOA and simple mock ERC-1271 owners; CI invariant handler has `fail_on_revert=false` | Strengthen negative tests and explicit failure assertions; add independent Echidna/Medusa tests as appropriate |
| R11 | Low/Medium | EIP-712 domain and Payment schema changed from v1.1; incompatible signatures are expected | Verify external signing libraries with canonical vectors and exact byte-for-byte typed-data hashes |
| R12 | Low/Medium | Vault owner/contract wallet may renounce or lose controls; funds could become inaccessible | Review Ownable2Step renounce behavior and recovery paths |

## Verified local test coverage — evidence, not an audit

- `test/SentinelV29Epoch.t.sol`: owner/executor epochs, signature validity after rotations and restoration, domain separation, cancellation.
- `test/SentinelV30Factory.t.sol`: per-user ownership, guard isolation, no factory admin, invalid setup, cross-vault non-replay.
- `test/invariant/SentinelV31Invariant.t.sol`: stateful two-vault conservation, policy separation and nonce/epoch tracking.
- `test/SentinelV32ContractOwner.t.sol`: V29 / V30 contract-owner EIP-1271 signatures, revocation, signer and executor rotation, access control, cross-vault replay.
- Older `test/SentinelV28SecurityReview.t.sol` intentionally demonstrates historical legacy signature-revival weaknesses in V1 **for regression comparison**, not a passing security property of the legacy contract.

**Not yet demonstrated:** real-world ERC-1271 account-abstraction wallet compatibility; revocation of wallet-internal previously signed intents through all signer history paths; malicious token behavior and economic balance accounting; public chain replay under forks/chain-ID shifts; live end-to-end executor and UI; off-chain key management; formal verification. Review these prior to production.

## Reproducible review instructions

**Requirements:** working WSL/Ubuntu, Node, Python, installed pinned Foundry toolchain at `$HOME/.foundry/bin/forge`, repository dependencies initialized through `scripts/install-deps.sh`. Use a clean feature-branch checkout; never load production secrets.

```bash
cd /mnt/c/Github/qie-sentinel-v2
git fetch origin
git switch feat/v2-owner-approval
git pull --ff-only origin feat/v2-owner-approval
git rev-parse HEAD
git status --short
bash scripts/install-deps.sh
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge build --sizes
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV29EpochTest -vv
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV30FactoryTest -vv
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV31InvariantTest -vv
FOUNDRY_PROFILE=ci $HOME/.foundry/bin/forge test --match-contract SentinelV32ContractOwnerTest -vv
bash scripts/verify-v2.sh
```

The `ci` profile in `foundry.toml` specifies `fuzz.runs=1024`, `invariant.runs=256`, `invariant.depth=64`, and `fail_on_revert=false`. The invariant handler uses internal low-level calls to assert that deliberately unauthorized payments are rejected; a reported zero handler reverts is not a claim that no unauthorized calls were attempted.

Record the commit SHA, compiler version, installed OpenZeppelin commit and all failed commands in the auditor's report. **Do not include local wallet secrets or keys.**

## Mandatory release gates

1. Resolve or explicitly accept each R1–R12 risk after independent expert review; **do not silently waive high-priority items**.
2. Independently audit factory, vault, guard, nonstandard token behavior, EIP-712 signing and ERC-1271 signer lifecycle.
3. Enforce verified official token identity / chain selection and create a separately reviewed versioned deployment pipeline.
4. Demonstrate authenticated owner-controlled wallet onboarding and explicit risk disclosure in a no-value test environment.
5. Design secure executor service, event monitoring, cancellation, replay resilience and emergency runbook.
6. Re-run all reproducible tests on the exact audited commit; retain compilation artifacts and source hashes.
7. Obtain explicit separate approval for *any* live deployment, signing integration or value-bearing operation.

This document is a review handoff, **not** certification of security or permission to deploy.
