# Three-minute QIE Sentinel demo script

## 0:00–0:25 — Problem

“AI agents can propose payments faster than humans can review them. A natural-language model should not have unilateral access to treasury funds. QIE Sentinel separates autonomy from authorization.” Show the Vercel public hero.

## 0:25–0:55 — Architecture

Show the trust boundary diagram: task -> interpreter -> policy preflight -> owner-signed intent -> executor -> on-chain vault/PolicyGuard. Point out that the optional AI advisor does not control permission.

## 0:55–1:35 — Attack scenarios

On the **public Vercel page**, click the invalid recipient, oversize amount, used nonce, and expired intent scenarios. Say explicitly: “These buttons are an offline simulation of the actual policy rules.”

## 1:35–2:05 — Real agent audit

On the **private local PM2 dashboard**, show `/api/agent/events` and the four actual recorded off-chain rejections produced by `python3 sentinel-agent/demo.py run`. Explain these were preflight rejections, not failed on-chain transfers.

## 2:05–2:35 — Owner approval and real payment

Show the previously confirmed EIP-712 approval queue entry (`nonce 2`, `0.10 QUSDC`) and explorer tx `0x95f122e6b4679727751dd8e111ed4a5892fd9d85d07aa0554fcb1a52127c1b48`. No need to spend funds again. If demoing live CLI, **do not sign or broadcast** unless intentionally authorizing another small payment.

## 2:35–3:00 — Controls and close

Show successful pause/unpause receipts, QUSDC spending cap, on-chain contract addresses. Close with: “The agent proposes. The owner authorizes. The blockchain enforces.” Mention hackathon MVP, not independently audited.

## Rehearsal checklist

- `pm2 status` shows `qie-sentinel` online.
- `curl -fsS http://127.0.0.1:8765/api/state` returns chainId 1990.
- GitHub Actions shows green Python and Foundry checks (only claim this after it runs).
- Public Vercel page is accessible from another device without a VPN.
- No secrets in screen recording, shell history, export files, or browser tabs.
- Explorer links for deployment, pause, unpause, and both payments work.
