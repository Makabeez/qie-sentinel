# Security and disclosure

**Hackathon prototype — no independent audit.** Not designed for unattended high-value production funds.

## Strong boundaries

- QIE chain ID 1990; token bound to QUSDC `0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5`.
- Owner-only administration, recipient allowlisting, per-payment cap, daily spending cap, EIP-712 signed intents, nonce bitmap, deadlines, emergency pause/recovery.
- Only owner-signed payment structs may be executed by the specifically authorized executor.
- No signature or private key is needed for public Vercel pages. The browser simulation cannot move tokens.

## Threats and residual risks

1. **Compromised owner key**: can authorize and recover funds; store encrypted and separate from agent runtime.
2. **Compromised executor key**: cannot create owner signatures but may submit still-valid signatures; keep signature distribution tightly scoped and invalidate compromised nonces.
3. **Incorrect signer intent**: an owner can sign malicious payment fields. Check token, address, amount, nonce, deadline and executor before signing.
4. **RPC outages/stale chain state**: preflight must fail closed; on-chain enforcement is the ultimate boundary.
5. **Untrusted natural language / prompt injection**: AI explanations cannot override deterministic policy rules; advisory data may leave local system only with consent.
6. **Public endpoint exposure**: the local Python server is not hardened for multi-user public internet access. Keep bound to `127.0.0.1`. Do not tunnel `/api/proposals` or `/api/agent/*` publicly.
7. **Event-history scope**: read-only chain snapshots may use a limited block lookback. Empty results are not proof of no earlier payments.
8. **Sensitive publication**: before `git push`, inspect tracked files and exported reports. Public site intentionally contains only disclosed mainnet addresses and known transaction references.
9. **Admin recovery**: `emergencyRecover` is owner-privileged while paused and bypasses normal agent policy by design; disclose this to users.
10. **No external audit**: passing Foundry and Python tests does not establish immunity to exploits.

## Disclosures in demos

Distinguish **real on-chain successful payments** (linkable explorer receipts), **recorded off-chain rejections**, **browser-simulated examples**, and **optional AI-generated explanations**. Never describe a simulated rejection as a reverted mainnet transaction.
