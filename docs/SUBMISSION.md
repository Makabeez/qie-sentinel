# QIE Sentinel — final submission checklist

## Project identities and links
- **Name:** QIE Sentinel
- **Tagline:** Autonomous proposals. Human-controlled funds.
- **Tracks to consider:** AI + Autonomous Agents; financial infrastructure as a secondary application. Confirm the exact category wording in the organizer's portal.
- **Website:** https://qie-sentinel-peach.vercel.app/
- **Source and tests:** https://github.com/Makabeez/qie-sentinel
- **CI:** https://github.com/Makabeez/qie-sentinel/actions
- **QIE Mainnet:** chain ID 1990
- **Source verified:** [SentinelVault](https://mainnet.qie.digital/address/0xb752F05a55059C89a43a289d5d055F303B6DD96E?tab=contract) and [PolicyGuard](https://mainnet.qie.digital/address/0x532Ee81939386E23b8c58076e643D9FCe489F15C?tab=contract).

## Project description — ready to adapt
QIE Sentinel is a QUSDC payment firewall for AI-assisted agents on QIE Mainnet. The agent can interpret a payment request and propose a transaction, but cannot sign or spend on its own. Deterministic policy checks guard recipient allowlists, transfer caps, daily spending, nonces and deadlines. A human owner signs the exact EIP-712 payment intent, and an independent executor submits it to verified Solidity contracts. The public read-only lab demonstrates real on-chain policy checks without connecting a wallet or broadcasting transactions. The project includes documented historical payments, a local proposal/audit workflow and automated Foundry/Python tests.

## Proof and transparency
- [ ] Confirm the [production Vercel page](https://qie-sentinel-peach.vercel.app/) shows both verified contracts, three linked receipts and updated read-only lab.
- [ ] Confirm all five lab scenarios in a fresh browser. Unknown recipient and oversize are *contract eth_call reverts*; nonce and deadline are *read-only on-chain-state checks*. No mined failed transactions are claimed.
- [ ] Confirm source tabs show verification on both contracts.
- [ ] Confirm GitHub Python and Foundry workflows pass at final commit.
- [ ] Confirm owner pause/unpause receipts and three payment receipt links work.
- [ ] Record/submit the updated video following [VIDEO_HANDOFF.md](VIDEO_HANDOFF.md), replacing the outdated static-simulation narration.
- [ ] Include **authentic** local agent proposal/audit evidence if available, redacted of signatures and identifiers as needed. Do not fabricate a “live agent” on the public site.
- [ ] Avoid implying traction: all three real payments (0.45 QUSDC total) were to the same authorized test wallet.
- [ ] Disclose: source verified, **not independently audited**; privileged owner recovery is possible but not demonstrated on mainnet.
- [ ] Check current organizer deadline, portal form, eligibility, team composition and any video-length requirements on the official site.
- [ ] Submit through the official portal and retain confirmation. Publication of GitHub/Vercel alone is **not** a hackathon submission.

## Safety and operations
- No private key or keystore files in Git, Vercel, footage or local evidence exports.
- Keep private agent server bound to 127.0.0.1; no public tunnel or reverse proxy.
- No signing or QUSDC payments solely to create apparent traction.
- Do not publish SQLite, hidden .env, private invoices or API credentials.
- Before any next local git update: `git fetch origin && git status -sb`; inspect differences and avoid `git add -A` because the local directory has unrelated untracked projects.
- Check pinned compiler/dependencies and any outstanding security findings.
- Video is handled separately; no video file is included in this GitHub release.

## Submission contact fields
Enter these yourself on the official portal: team name, account/wallet, email, contributor roles, original development contributions, video URL and any required chain deployments. No submission has been performed by this document.
