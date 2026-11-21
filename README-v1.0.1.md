# QIE Sentinel v1.0.1 — verification diagnostics fix

Fixes Foundry `cast call` uint256 pretty-printing / formatting issue: use raw ABI `eth_call` selector and `cast to-dec`, then show the actual numeric limits. Does not redeploy or sign transactions.

Dry run: `bash scripts/verify-qie-mainnet.sh`

Only after successful local dry run **and verifying original deployment constructor arguments and bytecode metadata**: `VERIFY_SUBMIT=1 bash scripts/verify-qie-mainnet.sh`. Explorer matching may still fail if deployment compiler metadata or constructor inputs differ.
