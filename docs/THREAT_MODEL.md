# Threat model and trust boundaries

## Assets and principals
- Vault holds only QUSDC on QIE chain 1990. Owner is the highest-trust principal.
- Executor is a hot-key agent service. It cannot authorize its own spending.
- Owner EIP-712 signatures authorize exact amounts, recipients, token, executor, nonce, and deadline.
- PolicyGuard is immutable relative to the vault and allows only vault-initiated updates.
- Owner can update limits and allowlist and fully recover when paused. This is a **trusted privileged role**, not a trustless multisig.

## Attacks and mitigations
| Attack | Defense |
|---|---|
| Malicious LLM suggests large payments | Per-payment cap and daily limit enforced on-chain |
| Compromised executor | Owner signature, allowlist, limits, short expiry, revoke/replace executor |
| Signature replay | Domain-separated EIP-712 digest and nonce bitmap |
| Cross-vault or cross-chain replay | EIP-712 verifying contract and chain ID |
| ERC-20 callback reentry | NonReentrant and state updates before safe transfer |
| Token transfer reverts | Full transaction rollback including policy spend and nonce |
| Stale signed instructions | Deadline, nonce invalidation, owner/executor rotation |
| Emergency | Owner pause plus owner-controlled recovery to specified recipient |
| Malicious recipient | Owner allowlisting; signing alone is insufficient |
| Approval abuse | No token approvals to arbitrary external contracts |

## Remaining risks
1. **Owner compromise is catastrophic.** Use a hardware wallet or properly administered multisig for the owner; deployer and executor are distinct.
2. **On-chain policy is intentionally narrow.** The owner must approve each exact payment. The agent is autonomous in planning and submission, not independent in spending authority.
3. **No external security audit.** Tests and fuzz/invariant campaigns do not replace an independent audit. Limit funding to amounts you can afford to lose.
4. **Trusted chain and stablecoin.** QIE RPC, consensus, QUSDC contract behavior, and any token admin powers are external dependencies.
5. **Budget semantics.** Budgets are UTC block-timestamp days. Lowering a limit below already spent amounts yields zero remaining budget until the next day; raising a limit is an owner-privileged action.
6. **QUSDC token assumptions.** Standard ERC-20 behavior; no fee-on-transfer accounting. Fixed token address is verified on mainnet deployment script but actual runtime bytecode/admin risk still needs independent inspection.
7. **Recovery is an intentional bypass.** It is only callable by the owner after pause, and is not constrained by agent policy.
8. **Agent telemetry is not proof.** Cryptographic evidence is derived from transaction receipts and chain events.
9. **Recipient confidentiality.** Wallet addresses, limits, and payments are public.
