# QIE Sentinel 3.7 portfolio demo

QIE Sentinel lets an owner authorize a specific treasury payment while delegating
submission to a separate executor. The vault checks the signed intent, policy
limits and nonce before moving tokens.

## Walk through the authorization

From the repo root, run `python3 -m http.server 8766 --bind 127.0.0.1` and open
[the portfolio walkthrough](http://127.0.0.1:8766/v2/portfolio.html).

1. Expand the domain and payment fields. The verifying contract scopes the authorization to one vault.
2. Change the amount from 0.25 to 0.26. The original digest stays fixed and the proposed digest changes.
3. Restore the amount and set the executor epoch to 2. The digest changes again. This counter binds a payment to the current executor authorization even when an old executor address is restored.
4. Follow the on-chain evidence link to see the submitted v1.1 receipts.

## Run the mock-token settlement rehearsal

With Foundry installed, from the repo root:

```sh
bash scripts/install-deps.sh
forge test --match-test testV36PortfolioRehearsal -vvvv
node --test v2/test-*.mjs
```

The trace follows a V35 vault created through the V36 factory. A disposable
owner allowlists a recipient and signs an intent. A separate executor settles
0.10 mock tokens, leaving 0.90 in the vault. The owner cancels a second signed
intent, verifies it cannot settle, pauses the vault and recovers the balance.
All transaction state lives in the Foundry test VM.

## Release notes

- Added an offline browser walkthrough for the V35 EIP-712 domain and payment fields.
- Added a reproducible zero-value V36 factory and V35 vault rehearsal.
- The browser walkthrough uses fixed sample data. The Foundry rehearsal runs the actual contracts with independently deployed mock assets and disposable keys.
- The [v3.6 audit candidate](../audit/V36_RELEASE_CANDIDATE.md) remains subject to independent review before use with live funds.
