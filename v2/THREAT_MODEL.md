# QIE Sentinel v2.1 — Threat model and release gates

**Status:** experimental design branch, not deployed; not audited; no third-party custody.

## Assets and trust boundaries

- **User owner key:** must stay in the user's wallet. The application never collects recovery phrases or private keys.
- **Executor key:** distinct from owner. Can submit *already owner-signed* intents; cannot bypass owner signature by itself.
- **User vault:** a separate `SentinelVault` instance per creator, with its own deployed `PolicyGuard`. The existing hackathon vault is untouched.
- **Factory:** permissionless deployment helper, stores creator history only. Cannot administer deployed vaults.
- **Token:** the factory constructor chooses an ERC-20 address. **That token must be independently validated as official QUSDC before any deployment**; a fake-token factory would be misleading. No factory deployment is approved by this branch.
- **Browser:** proposal review and JSON preview only. It is not an authorization service, durable audit ledger, execution engine or treasury account manager.
- **RPC:** all read-only data is untrusted until chain ID and contract identity are verified. Pinned-block reads reduce state inconsistencies, but node failure/staleness remains possible.
- **Advisory AI:** has no signing or privileged contract authority.

## Main risks and mitigations

| Risk | Planned mitigation and validation |
|---|---|
| Another user changes Alice's policies | `Ownable2Step` checks on every vault admin method; adversarial cross-user tests |
| Owner and executor are identical | Factory rejects equality at creation; UI rejects it when making a plan |
| Default recipients can receive funds | New guard has an empty allowlist; require explicit owner configuration |
| Factory secretly controls funds | Factory is never vault owner or executor by default; tests assert no admin access |
| Agent obtains owner signing authority | Distinct wallet approval channel; no key export or browser-stored secrets |
| Phishing through signing prompts | No signing in v2.1. Later show full EIP-712 domain, chain, vault, token, recipient, amount, nonce, expiry and executor before consent |
| Reused or expired payment | Nonce bitmap and deadlines checked by vault; add integration tests for each new owner |
| Malicious token or factory | Verify official QUSDC token and factory bytecode/constructor, publish addresses only after independently validating |
| Executor drains under granted approval | Every signature scopes exact payment, amount, nonce, executor and deadline; no unlimited approvals |
| Admin recovery abuse | Owner can pause and recover funds bypassing agent policy; disclose and test owner-only controls |
| UI mistakenly implies authority | Explicit `PREVIEW_ONLY_NOT_DEPLOYED` JSON; no signing, no account transaction, no createVault call |
| Review evidence becomes stale | Export block ID/timestamp and display time; live execution must independently revalidate |
| Sensitive data disclosure | No production proposal storage; never expose existing localhost server or saved keys |
| Web/RPC outages | Fail closed and show unavailable state, not eligible |

## Required gates before real deployment

1. Verify actual QIE Mainnet QUSDC address and token behavior; enforce expected token/network in a reviewed deployment process.
2. Run `forge fmt --check`, `forge build`, `FOUNDRY_PROFILE=ci forge test -vvv` and all Node/Python tests.
3. Add tests for ownership transfer, executor rotation, payment signature validation (EOA + ERC1271), nonce invalidation, pause and recovery across separate users.
4. Perform independent security review of factory + vault + guard, and compare compiled deployed bytecode to audited source.
5. Design an authenticated executor service with rate limits, durable state, explicit human consent, antifraud monitoring and revocation.
6. First deploy to a test environment using nonvaluable assets; then conduct a narrowly scoped real-world pilot only with informed user consent.
7. Separately verify production infrastructure and wallet security. No contract deployment is authorized by this document.

## Release assertions

- `main` remains the submitted hackathon project.
- `feat/v2-owner-approval` introduces experimental code only.
- No mainnet factory or independent customer vault has been deployed.
- Browser form exports a **configuration preview**; it does not grant a signer role or claim the connected account owns the existing demonstration vault.
