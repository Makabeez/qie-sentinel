#!/usr/bin/env bash
# QIE Sentinel v3.4 — local validation only. NEVER deploys, signs or broadcasts.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
# Resolve Foundry explicitly: some hosts have a different 'forge' executable.
FOUNDRY_FORGE="$HOME/.foundry/bin/forge"
if [[ ! -x "$FOUNDRY_FORGE" ]]; then
  echo "[STOP] Foundry forge not found at $FOUNDRY_FORGE. Install Foundry first." >&2
  exit 2
fi
if ! "$FOUNDRY_FORGE" --version | grep -q '^forge Version:'; then
  echo "[STOP] Unexpected forge binary: $FOUNDRY_FORGE" >&2
  exit 2
fi
current="$(git branch --show-current)"
if [[ "$current" != "feat/v2-owner-approval" ]]; then
  echo "[STOP] Run from C:\\Github\\qie-sentinel-v2 on feat/v2-owner-approval, not from the submitted main branch." >&2
  exit 2
fi
echo "[1/6] JavaScript syntax"
node --check v2/app.mjs
node --check v2/policy.mjs
node --check v2/onboarding.mjs
echo "[2/6] JavaScript security and policy tests"
node --test v2/test-*.mjs
echo "[3/6] Public v1.1 site regression"
python3 scripts/check-public-site.py
echo "[4/6] No sensitive files tracked"
bash scripts/check-publish.sh
echo "[5/6] Install pinned Foundry dependencies and compile (no deployment)"
bash scripts/install-deps.sh
"$FOUNDRY_FORGE" build
echo "[6/6] Factory isolation and offline signature lab tests"
"$FOUNDRY_FORGE" test --match-contract SentinelVaultFactoryTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelSignatureLabTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelOfflineSignatureTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV27LifecycleTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV28SecurityReviewTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV29EpochTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV30FactoryTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV32ContractOwnerTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV33SignerEpochTest -vv
"$FOUNDRY_FORGE" test --match-contract SentinelV34WalletCompatibilityTest -vv
FOUNDRY_PROFILE=ci "$FOUNDRY_FORGE" test --match-contract SentinelV31InvariantTest -vv
echo "[PASS] v2 local checks passed. No mainnet transaction, signature or deployment."
