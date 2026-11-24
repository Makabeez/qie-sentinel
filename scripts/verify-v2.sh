#!/usr/bin/env bash
# QIE Sentinel v2.1 — local validation only. NEVER deploys, signs or broadcasts.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
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
forge build
echo "[6/6] Independent-owner factory isolation tests"
forge test --match-contract SentinelVaultFactoryTest -vv
echo "[PASS] v2.1 local checks passed. No mainnet transaction, signature or deployment."
