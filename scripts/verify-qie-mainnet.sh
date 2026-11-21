#!/usr/bin/env bash
# QIE Sentinel — safe, keyless mainnet source verification.
# Run from the existing project's root. Set VERIFY_SUBMIT=1 to submit.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"
RPC="https://rpc1mainnet.qie.digital"
EXPLORER="https://mainnet.qie.digital/api/"
VAULT="0xb752F05a55059C89a43a289d5d055F303B6DD96E"
GUARD="0x532Ee81939386E23b8c58076e643D9FCe489F15C"
TOKEN="0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5"
OWNER="0x395215ab5Dde403801868fa850b89e305F01725E"
EXECUTOR="0xD0612b00030AC351EAb6A7800E4b7679e3f7D95A"
for tool in forge cast; do command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }; done
[[ -f foundry.toml && -f src/SentinelVault.sol && -f src/PolicyGuard.sol ]] || { echo 'Run from qie-sentinel project with source files.'; exit 1; }
[[ "$(cast chain-id --rpc-url "$RPC")" == 1990 ]] || { echo 'Wrong chain ID!'; exit 1; }
[[ "$(cast call "$VAULT" 'guard()(address)' --rpc-url "$RPC" | tr '[:upper:]' '[:lower:]')" == "${GUARD,,}" ]] || { echo 'On-chain guard address differs.'; exit 1; }
[[ "$(cast call "$VAULT" 'owner()(address)' --rpc-url "$RPC" | tr '[:upper:]' '[:lower:]')" == "${OWNER,,}" ]] || { echo 'On-chain owner differs.'; exit 1; }
[[ "$(cast call "$VAULT" 'executor()(address)' --rpc-url "$RPC" | tr '[:upper:]' '[:lower:]')" == "${EXECUTOR,,}" ]] || { echo 'On-chain executor differs.'; exit 1; }
[[ "$(cast call "$VAULT" 'token()(address)' --rpc-url "$RPC" | tr '[:upper:]' '[:lower:]')" == "${TOKEN,,}" ]] || { echo 'On-chain token differs.'; exit 1; }
# Get raw ABI result, then decode its uint256 directly. Typed cast output may include
# a display annotation such as "1000000 [1e6]" on recent Foundry versions.
read_uint256() {
  local target="$1" signature="$2" raw value
  raw="$(cast call "$target" "$(cast sig "$signature")" --rpc-url "$RPC")"
  [[ "$raw" =~ ^0x[0-9a-fA-F]{64}$ ]] || {
    echo "ERROR: Unexpected uint256 RPC result for $signature: $raw" >&2
    return 1
  }
  value="$(cast to-dec "$raw")"
  [[ "$value" =~ ^[0-9]+$ ]] || {
    echo "ERROR: Non-numeric decoded value for $signature: $value" >&2
    return 1
  }
  printf '%s\n' "$value"
}
MAX_PER_TRANSFER="$(read_uint256 "$GUARD" 'maxPerTransfer()')"
DAILY_LIMIT="$(read_uint256 "$GUARD" 'dailyLimit()')"
printf '[CHAIN] Guard maxPerTransfer = %s raw units (expected 1000000)\n' "$MAX_PER_TRANSFER"
printf '[CHAIN] Guard dailyLimit    = %s raw units (expected 5000000)\n' "$DAILY_LIMIT"
[[ "$MAX_PER_TRANSFER" == 1000000 ]] || { echo 'On-chain per-transfer limit truly differs; STOP, do not submit.' >&2; exit 1; }
[[ "$DAILY_LIMIT" == 5000000 ]] || { echo 'On-chain daily limit truly differs; STOP, do not submit.' >&2; exit 1; }
[[ "$(cast code "$VAULT" --rpc-url "$RPC")" != 0x ]] || { echo 'Vault code missing.'; exit 1; }
[[ "$(cast code "$GUARD" --rpc-url "$RPC")" != 0x ]] || { echo 'Guard code missing.'; exit 1; }
echo '[OK] Live mainnet chain, code and current configuration match the expected settings.'
echo '[NOTE] Matching current configuration does NOT prove the constructor values or compiled bytecode match the deployed creation bytecode.'
echo '[INFO] Installing missing Foundry dependencies, if necessary.'
bash scripts/install-deps.sh
forge build
VAULT_ARGS="$(cast abi-encode 'constructor(address,address,address,uint256,uint256)' "$TOKEN" "$OWNER" "$EXECUTOR" 1000000 5000000)"
GUARD_ARGS="$(cast abi-encode 'constructor(address,uint256,uint256)' "$VAULT" 1000000 5000000)"
echo '[OK] Build succeeded. Source verification is a separate operation.'
if [[ "${VERIFY_SUBMIT:-0}" != 1 ]]; then
  echo 'DRY RUN ONLY. To submit the verification jobs, run:'
  echo '  VERIFY_SUBMIT=1 bash scripts/verify-qie-mainnet.sh'
  exit 0
fi
echo '[VERIFY] SentinelVault (no transaction or private key required)'
forge verify-contract "$VAULT" src/SentinelVault.sol:SentinelVault \
  --chain-id 1990 --verifier blockscout --verifier-url "$EXPLORER" \
  --constructor-args "$VAULT_ARGS" --watch

echo '[VERIFY] PolicyGuard'
forge verify-contract "$GUARD" src/PolicyGuard.sol:PolicyGuard \
  --chain-id 1990 --verifier blockscout --verifier-url "$EXPLORER" \
  --constructor-args "$GUARD_ARGS" --watch

echo '[SUCCESS] Verification jobs reported completion. Confirm source in Contract tabs:'
echo "https://mainnet.qie.digital/address/$VAULT"
echo "https://mainnet.qie.digital/address/$GUARD"
