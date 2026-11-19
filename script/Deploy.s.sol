// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SentinelVault } from "../src/SentinelVault.sol";

/// @notice Deploy only on QIE mainnet; deployment sender is selected by --account or --private-key.
contract Deploy is Script {
    uint256 internal constant QIE_CHAIN_ID = 1990;
    address internal constant QUSDC = 0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5;

    function run() external returns (SentinelVault vault) {
        require(block.chainid == QIE_CHAIN_ID, "QIE mainnet only");
        address owner = vm.envAddress("SENTINEL_OWNER");
        address executor = vm.envAddress("SENTINEL_EXECUTOR");
        uint256 perTx = vm.envUint("MAX_PER_TX");
        uint256 daily = vm.envUint("DAILY_LIMIT");
        require(owner != executor, "owner and executor must differ");
        require(QUSDC.code.length > 0, "QUSDC missing on chain");
        vm.startBroadcast();
        vault = new SentinelVault(QUSDC, owner, executor, perTx, daily);
        vm.stopBroadcast();
        console2.log("SentinelVault", address(vault));
        console2.log("PolicyGuard", address(vault.guard()));
        console2.log("QUSDC", QUSDC);
        console2.log("Owner", owner);
        console2.log("Executor", executor);
        console2.log("Chain", block.chainid);
    }
}
