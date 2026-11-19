# QIE Sentinel · Autonomous proposals. Human-controlled funds.

**QIE Digital Hackathon 2026 · QIE Mainnet (chain ID 1990)**

A QUSDC-only vault and AI-agent security workflow. Agents interpret payment tasks and create proposals; deterministic policy preflight rejects unsafe requests; an independent owner signs exactly scoped EIP-712 intents; a separate executor submits them to a Solidity vault that verifies signatures, nonces, budgets and recipients before transfer.

> **Hackathon MVP; not independently audited.** Keep funds minimal. Do not expose the local Python application publicly.

## What has been demonstrated

- Vault deployment and PolicyGuard deployment on QIE Mainnet.
- Owner-only pause and unpause transactions.
- Real executor-submitted, owner-signed 0.10 QUSDC payment using nonce 1.
- Real proposal queue -> owner signature -> executor -> confirmed 0.10 QUSDC payment using nonce 2.
- Deterministic agent demo with one unsigned candidate and four off-chain rejections (unauthorized address, over-limit amount, used nonce, expired deadline).
- Local live dashboard, persistent SQLite audit ledger, evidence exporter and standalone showcase.
- Optional consent-only AI risk adviser, advisory text only; authorization always deterministic.

## Live deployed contracts

| Contract | Address |
|---|---|
| SentinelVault | [`0xb752F05a55059C89a43a289d5d055F303B6DD96E`](https://mainnet.qie.digital/address/0xb752F05a55059C89a43a289d5d055F303B6DD96E) |
| PolicyGuard | [`0x532Ee81939386E23b8c58076e643D9FCe489F15C`](https://mainnet.qie.digital/address/0x532Ee81939386E23b8c58076e643D9FCe489F15C) |
| QUSDC | `0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5` |

### Independently inspectable transactions

- [Vault deployment](https://mainnet.qie.digital/tx/0x8edf56430a508d1595e7cdbee0b0187dbcc4bc9a2c07b2683da4f9aef30a8d94)
- [Owner pauses vault](https://mainnet.qie.digital/tx/0x6b039508ea4eb6a9c40b97a65ef1eb211b1c7f143e58a5bb144fecad54dcda1d)
- [Owner unpauses vault](https://mainnet.qie.digital/tx/0xdac70752ed0c6dd36593059109c2feb4c7c1519cbe226842016ce6eefcb26e35)
- [EIP-712 payment, nonce 1](https://mainnet.qie.digital/tx/0x196dce5ce2ad7ad2f327eb5ff9d41c171dd0535bbcdb001742832b1862a5d59a)
- [Approval queue payment, nonce 2](https://mainnet.qie.digital/tx/0x95f122e6b4679727751dd8e111ed4a5892fd9d85d07aa0554fcb1a52127c1b48)

## Architecture

```text
Business task -> deterministic interpreter -> policy preflight -> SQLite proposal
                               | rejected? -> audit event (NO transfer)
                               v
                  separate owner keystore approval (EIP-712)
                               v
                  separate executor keystore + mainnet tx
                               v
             SentinelVault -> PolicyGuard -> QUSDC token transfer
```

The optional external LLM only explains risks after consent; it cannot set policy or sign. The Vercel public website (`site/`) is static and runs an explicitly labeled simulation. The local Python server should stay bound to `127.0.0.1`.

See [architecture](docs/ARCHITECTURE.md), [security limitations](docs/SECURITY.md), and [3-minute demo script](docs/DEMO.md).

## Local development

Requires Linux/WSL, Python 3.12+, Git and Foundry (`forge` / `cast`).

```bash
bash scripts/install-deps.sh
forge build
FOUNDRY_PROFILE=ci forge test -vv
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' -v
python3 scripts/check-public-site.py
python3 sentinel-agent/server.py
# Dashboard at http://127.0.0.1:8765/
```

Create no private keys for read-only tests. Real payment approval/execution uses encrypted, separately held Foundry owner/executor keystores. Never place a private key in `.env`, Git, Vercel, or browser JavaScript.

## Generate local evidence

```bash
python3 sentinel-agent/demo.py run   # unsigned proposal + rejected scenarios only
python3 sentinel-agent/evidence.py --output sentinel-evidence.json
python3 sentinel-agent/showcase.py --input sentinel-evidence.json --output sentinel-showcase.html
```

Evidence files include public payment addresses and proposal history; keep them untracked and review before sharing. Off-chain rejections must not be described as failed on-chain transactions.

## Deploy public showcase on Vercel

**Vercel project Root Directory = `site`**. Framework preset = `Other`. No backend and no environment variables needed. The static site does not call the local API or the QIE RPC.

Using the CLI (from repository root):

```bash
cd site
npx vercel login
npx vercel
npx vercel --prod
```

Or connect this GitHub repository in the Vercel dashboard and set Root Directory to `site`. Vercel deploys commits after the Git integration is configured. Do **not** set the root to `sentinel-agent/` or expose port 8765.

## Source and security notes

Solidity `0.8.24`, OpenZeppelin `v5.0.2`, forge-std `v1.9.7`, `evm_version="paris"`. The project has automated unit, fuzz, invariant, fork and Python tests. Local verification is not a third-party audit or verification of deployed source on a block explorer. CI only counts as passing once GitHub Actions executes successfully.
