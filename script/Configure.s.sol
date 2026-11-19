// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SentinelVault } from "../src/SentinelVault.sol";

/// @notice Owner-only recipient configuration. Run with the owner's secure signer.
contract Configure is Script {
    function run() external {
        require(block.chainid == 1990, "QIE mainnet only");
        SentinelVault vault = SentinelVault(vm.envAddress("SENTINEL_VAULT"));
        address recipient = vm.envAddress("SENTINEL_RECIPIENT");
        bool approved = vm.envBool("SENTINEL_APPROVED");
        require(address(vault).code.length > 0, "Vault not deployed");
        require(address(vault.token()) == 0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5, "Unexpected token");
        vm.startBroadcast();
        vault.setRecipient(recipient, approved);
        vm.stopBroadcast();
        console2.log("Vault", address(vault));
        console2.log("Recipient", recipient);
        console2.log("Approved", approved);
    }
}
