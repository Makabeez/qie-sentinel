#!/usr/bin/env bash
# One command: every Solidity, Python and JS test + public-site guard. No keys, no RPC writes.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
[ -f lib/forge-std/src/Test.sol ] || bash scripts/install-deps.sh
rc=0
echo "[1/4] Foundry ($(forge --version | head -1))"
FOUNDRY_PROFILE=ci forge test 2>&1 | grep -E "Ran [0-9]+ test suites|FAIL" || rc=1
echo "[2/4] Python ($(python3 --version))"
python3 -m unittest discover -s sentinel-agent -p 'test_*.py' 2>&1 | grep -E "^Ran|^OK|FAILED" || rc=1
echo "[3/4] JS ($(node --version 2>/dev/null || echo 'node MISSING'))"
node --test v2/test-*.mjs 2>&1 | grep -E "^# (pass|fail)|^ℹ (pass|fail)" || { echo "  no summary line; raw tail:"; node --test v2/test-*.mjs 2>&1 | tail -8; rc=1; }
echo "[4/4] Site"
python3 scripts/check-public-site.py || rc=1
exit $rc
