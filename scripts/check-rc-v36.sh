#!/usr/bin/env bash
# QIE Sentinel 3.6 — reproducible local audit-candidate gate.
# NO keys, deployments, external RPC requests or signing transactions.
set -euo pipefail
cd "$(dirname "$0")/.."

FORGE="${FOUNDRY_FORGE:-$HOME/.foundry/bin/forge}"
if [[ ! -x "$FORGE" ]]; then
  echo "[STOP] Foundry forge missing: $FORGE" >&2
  exit 2
fi
if ! "$FORGE" --version | grep -q '^forge Version:'; then
  echo "[STOP] Wrong forge executable" >&2
  exit 2
fi
if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
  branch="$(git branch --show-current)"
  if [[ "$branch" != "feat/v2-owner-approval" ]]; then
    echo "[STOP] Audit-candidate verification is for the experimental worktree only" >&2
    exit 2
  fi
fi

echo "QIE Sentinel v3.6: AUDIT CANDIDATE ONLY (NO DEPLOYMENT)"
echo "Commit: $(git rev-parse HEAD)"
echo "[1/4] Validate frozen architecture / deployment boundaries"

for file in \
  src/SentinelVaultV35.sol \
  src/PolicyGuard.sol \
  src/interfaces/ISentinelOwnerSignerEpoch.sol \
  src/SentinelEpochFactoryV30.sol \
  audit/V36_RELEASE_CANDIDATE.md \
  audit/V35_HARDENING_REVIEW.md \
  audit/V34_WALLET_COMPATIBILITY.md \
  test/SentinelV35Hardening.t.sol \
  test/SentinelV34WalletCompatibility.t.sol
do
  if [[ ! -f "$file" ]]; then echo "[STOP] Missing audit scope file: $file" >&2; exit 3; fi
done

grep -Fq 'contract SentinelVaultV35 is' src/SentinelVaultV35.sol
grep -Fq 'EIP712("QIE Sentinel Vault V4", "4")' src/SentinelVaultV35.sol
grep -Fq 'ISentinelOwnerSignerEpoch' src/SentinelVaultV35.sol
grep -Fq 'SentinelVaultV29' src/SentinelEpochFactoryV30.sol
if grep -Eq 'SentinelVaultV35|SentinelVaultV33' src/SentinelEpochFactoryV30.sol; then
  echo "[STOP] Experimental V30 factory changed its deployed version; review needed" >&2
  exit 3
fi
grep -Fq 'NO-GO FOR MAINNET' audit/V36_RELEASE_CANDIDATE.md

echo "[2/4] Validate Solidity compiler, scope and formatting"
FOUNDRY_PROFILE=ci "$FORGE" build
if [[ "${RC_CHECK_FMT:-1}" == "1" ]]; then
  "$FORGE" fmt --check --root . src/SentinelVaultV35.sol src/interfaces/ISentinelOwnerSignerEpoch.sol \
    test/SentinelV35Hardening.t.sol test/mocks/MockV35FeeToken.sol || {
      echo "[STOP] Formatting failed for candidate source and tests" >&2
      exit 4
    }
fi

echo "[3/4] Re-run all local Solidity unit, fuzz, invariant and adversarial tests"
FOUNDRY_PROFILE=ci "$FORGE" test --offline -q

echo "[4/4] Confirm publication check and preserve no-go status"
bash scripts/check-publish.sh
echo "[PASS] AUDIT CANDIDATE reproducibility gate passed — not an audit, not a release."
echo "[PASS] No signer, deployment transaction or real-fund interaction performed."
