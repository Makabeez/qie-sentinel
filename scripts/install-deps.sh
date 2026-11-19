#!/usr/bin/env bash
set -euo pipefail
mkdir -p lib
if [ ! -f lib/forge-std/src/Test.sol ]; then
  forge install foundry-rs/forge-std@v1.9.7 --no-git
fi
if [ ! -f lib/openzeppelin-contracts/contracts/access/Ownable.sol ]; then
  # OZ 5.4 requires Cancun MCOPY; QIE deployment uses evm_version=paris.
  forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-git
fi
