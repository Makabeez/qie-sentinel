// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SentinelVault } from "../src/SentinelVault.sol";

/// @notice Requires a separately paused vault and the owner's signature.
contract Recover is Script {
    function run() external {
        require(block.chainid == 1990, "QIE mainnet only");
        SentinelVault vault = SentinelVault(vm.envAddress("SENTINEL_VAULT"));
        address destination = vm.envAddress("RECOVERY_RECIPIENT");
        uint256 amount = vm.envUint("RECOVERY_AMOUNT");
        require(address(vault).code.length > 0, "Vault not deployed");
        require(vault.paused(), "Pause vault before recovery");
        vm.startBroadcast();
        vault.emergencyRecover(destination, amount);
        vm.stopBroadcast();
        console2.log("Recovered", amount);
        console2.log("Destination", destination);
    }
}
