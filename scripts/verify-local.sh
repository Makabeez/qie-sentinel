#!/usr/bin/env bash
set -euo pipefail
bash scripts/install-deps.sh
forge fmt
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
