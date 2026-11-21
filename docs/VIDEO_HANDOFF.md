# QIE Sentinel — Claude video production handoff (2026-11-21)

**Project:** QIE Sentinel — *Autonomous proposals. Human-controlled funds.*  
**Public website:** https://qie-sentinel-peach.vercel.app/  
**GitHub:** https://github.com/Makabeez/qie-sentinel  
**Suggested duration:** 2:30–3:00, 16:9, English narration, burned-in readable captions, no private keys or sensitive terminal history.

## What to show and what each claim proves

### Scene 1 · 0:00–0:20 — Problem and premise
AI agents can propose actions, but should not independently spend treasury funds. Introduce the phrase: **“The agent proposes. The owner authorizes. The blockchain enforces.”**

Show the public website hero and **QIE Mainnet chain ID 1990**.

### Scene 2 · 0:20–0:45 — The architecture
Show diagram: request → **local deterministic interpreter** → **read-only policy preflight** → SQLite unsigned proposal/audit → human EIP-712 owner signing → separately controlled executor → verified SentinelVault → PolicyGuard → QUSDC transfer.

Clarify: OpenAI advice is **optional and consent-only** and cannot change policy or sign. No claim that the public website contains a live LLM or autonomous signing.

### Scene 3 · 0:45–1:35 — Five *genuine read-only* public cases
Record the actual public [lab](https://qie-sentinel-peach.vercel.app/#demo) working in a browser, rather than reusing the earlier static simulation capture.

1. **Approved wallet / 0.05 QUSDC:** `PolicyGuard.validate` passes; nonce 3 unused; deadline valid. This is **eligible for owner signature**, not a payment.
2. **Unknown recipient:** `PolicyGuard.validate` returns `RecipientNotAllowed` under `eth_call`.
3. **Oversize 1.000001 QUSDC:** `PolicyGuard.validate` returns `TransferLimitExceeded` under `eth_call`.
4. **Replay nonce 1:** `SentinelVault.isNonceUsed(1)` returns true under `eth_call`; frontend marks ineligible.
5. **Expired deadline:** frontend compares expiry with timestamp from latest chain block; marks ineligible.

**Do not narrate any of these as mined reverted transactions.** The public site does not send a transaction. Show the network block height and the no-wallet badge. A read-only test is not a simulation of the full owner-signature `execute()` function.

### Scene 4 · 1:35–2:05 — Human approval boundary
Use an authentic **redacted** recording of the private dashboard or existing audit evidence (only if the user provides or records it): structured payment proposal → deterministic decision → awaiting owner → owner signs EIP-712 exact intent → executor submission. **If no authentic recording is supplied, use an explicitly labeled diagram and historical explorer receipt rather than inventing UI, approval screens or agent activity.**

Signing uses a separate `sentinel-owner` encrypted keystore; executor has its own `sentinel-executor` keystore. Do **not** show command prompts that expose keys, signatures, connection tokens, private customer invoices, SQLite contents, or wallet secret material.

### Scene 5 · 2:05–2:40 — On-chain receipts + verified code
Show mainnet explorer **Contract Source Code Verified** tabs, compiler solc 0.8.24, Paris EVM, optimizer 200 runs:
- Vault: https://mainnet.qie.digital/address/0xb752F05a55059C89a43a289d5d055F303B6DD96E?tab=contract
- Guard: https://mainnet.qie.digital/address/0x532Ee81939386E23b8c58076e643D9FCe489F15C?tab=contract

Historical successful payment receipts (all to the **same** allowed wallet; not third-party traction):
- 0.25 QUSDC: https://mainnet.qie.digital/tx/0xf26e8863dad1f16399bcf3d5cfb8efad378897446da585c16afb2eeaef3d9442
- 0.10 QUSDC, nonce 1: https://mainnet.qie.digital/tx/0x196dce5ce2ad7ad2f327eb5ff9d41c171dd0535bbcdb001742832b1862a5d59a
- 0.10 QUSDC, nonce 2: https://mainnet.qie.digital/tx/0x95f122e6b4679727751dd8e111ed4a5892fd9d85d07aa0554fcb1a52127c1b48

Also show owner pause and unpause:
- https://mainnet.qie.digital/tx/0x6b039508ea4eb6a9c40b97a65ef1eb211b1c7f143e58a5bb144fecad54dcda1d
- https://mainnet.qie.digital/tx/0xdac70752ed0c6dd36593059109c2feb4c7c1519cbe226842016ce6eefcb26e35

**Do not claim emergency recovery was exercised on-chain.** It is implemented but no receipt proves use.

### Scene 6 · 2:40–3:00 — Close and link
Show public GitHub and Vercel URLs, the successful CI workflows if they are green at the time of recording, and the disclosure: **hackathon MVP; source-verified, not independently audited; self-directed test payments, not independent adoption**.

## Suggested outro line
“QIE Sentinel shows how an AI agent can propose payments without owning the signing authority. Every transfer requires a human-approved, scoped EIP-712 intent, a separate executor, and on-chain policy enforcement. The agent proposes. The owner authorizes. The blockchain enforces.”

## Assets, guardrails and checks

- Prefer actual browser capture of https://qie-sentinel-peach.vercel.app/#demo and explorer over generated screenshots.
- The prior 2:46 video described the security cases as simulated. **It is outdated for v0.9/v1.1**; do not submit it unchanged.
- Only public website, mainnet explorer and repository should be visible without redaction.
- No spending, signing, redeployment, recovery transaction, or authorization is necessary for the video.
- No artificial traction or claim of independent users.
- Verify every address and URL on screen; show readable text at 1080p where possible.
- Deliver MP4 H.264/AAC, a thumbnail, editable subtitle SRT, a narration script and scene timestamps.
