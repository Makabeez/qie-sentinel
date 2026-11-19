# QIE Sentinel architecture and trust boundaries

## What is running

- **Local private application:** `sentinel-agent/server.py` on `127.0.0.1:8765`, optional OpenAI advisory endpoint, live read-only chain state, local proposal/audit ledger.
- **Independent owner CLI:** `python3 sentinel-agent/agent.py approve <id>`; invokes encrypted `sentinel-owner` Foundry keystore only in the CLI session.
- **Independent executor CLI:** `python3 sentinel-agent/agent.py execute <id>`; explicit confirmation, uses a distinct `sentinel-executor` keystore.
- **On-chain vault:** `0xb752F05a55059C89a43a289d5d055F303B6DD96E` on QIE chain 1990.
- **On-chain PolicyGuard:** `0x532Ee81939386E23b8c58076e643D9FCe489F15C`.
- **Public Vercel showcase:** self-contained static files in `site/`. No private API, transaction submission, key storage, or RPC connection.

## Trust-boundary diagram

```mermaid
flowchart TD
  A[User business task] --> B[Local deterministic interpreter]
  B --> C[Read-only policy preflight]
  C -->|rejected| D[(SQLite rejection audit)]
  C -->|eligible| E[(SQLite proposal queue)]
  C -.->|optional consent only| L[LLM risk advisory]
  L -.->|untrusted explanation only| B
  E --> F[Owner CLI - separate keystore]
  F -->|EIP-712 signature| G[Executor CLI - separate keystore]
  G -->|signed intent| H[SentinelVault - QIE Mainnet]
  H --> I[PolicyGuard: recipient, budget, cap]
  I -->|approved| J[QUSDC token transfer]
  H --> K[On-chain nonce bitmap + event logs]
  D -.-> M[Static public showcase: curated evidence]
  K -.-> M
```

## Payment authorization

Domain: `QIE Sentinel Vault` / version `1` / chain ID `1990` / verifying contract vault address.

`Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor)`

The owner signs the exact digest returned by `paymentDigest(payment)` with Foundry `cast wallet sign --no-hash`. The executor submits `execute(payment, signature)`. Contract checks executor address, deadline, QUSDC token, nonce uniqueness, owner signature (EOA or ERC1271), then consumes PolicyGuard budget and transfers QUSDC. A transaction reverts atomically if any on-chain check fails.

## Operational boundaries

- Keep browser/backend bound to loopback. Do not reverse-proxy the private server to the public internet.
- Keep the owner private key offline except in the interactive CLI signing session.
- Keep demo transactions small; the contracts have not received an independent audit.
- The public site contains a **deterministic browser simulation**; it is not a connected agent or on-chain policy oracle.
- Source verification on explorers and audit of deployed bytecode are separate tasks; deployment transaction evidence does not equal verification of source or security audit.
