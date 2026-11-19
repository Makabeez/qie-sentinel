// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SentinelVault } from "../src/SentinelVault.sol";

contract Pause is Script {
    function run() external {
        require(block.chainid == 1990, "QIE mainnet only");
        SentinelVault vault = SentinelVault(vm.envAddress("SENTINEL_VAULT"));
        require(address(vault).code.length > 0, "Vault not deployed");
        vm.startBroadcast();
        vault.pause();
        vm.stopBroadcast();
        console2.log("Paused vault", address(vault));
    }
}
