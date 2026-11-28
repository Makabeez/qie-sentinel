// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SentinelFactoryV37 } from "../src/SentinelFactoryV37.sol";
import { SentinelVaultV37 } from "../src/SentinelVaultV37.sol";

/// @notice QIE mainnet only. Run with the OWNER account: it deploys the public factory,
///         then creates the demo vault (owner = sender), allowlists one recipient and sets the auto-pay limit.
/// Env: SENTINEL_EXECUTOR, SENTINEL_RECIPIENT, MAX_PER_TX, DAILY_LIMIT, AUTO_LIMIT
///      optional SENTINEL_FACTORY (reuse an already deployed factory)
contract DeployV37 is Script {
    uint256 internal constant QIE_CHAIN_ID = 1990;
    address internal constant QUSDC = 0x3F43DA82eC9A4f5285F10FaF1F26EcA7319E5DA5;

    function run() external returns (SentinelFactoryV37 factory, SentinelVaultV37 vault) {
        require(block.chainid == QIE_CHAIN_ID, "QIE mainnet only");
        require(QUSDC.code.length > 0, "QUSDC missing on chain");
        address executor = vm.envAddress("SENTINEL_EXECUTOR");
        address recipient = vm.envAddress("SENTINEL_RECIPIENT");
        uint256 perTx = vm.envUint("MAX_PER_TX");
        uint256 daily = vm.envUint("DAILY_LIMIT");
        uint256 autoLimit = vm.envUint("AUTO_LIMIT");
        address existing = vm.envOr("SENTINEL_FACTORY", address(0));
        require(autoLimit <= perTx, "AUTO_LIMIT > MAX_PER_TX");

        vm.startBroadcast();
        require(msg.sender != executor, "run as OWNER, not executor");
        factory = existing == address(0) ? new SentinelFactoryV37(QUSDC) : SentinelFactoryV37(existing);
        vault = SentinelVaultV37(factory.createVault(executor, perTx, daily));
        vault.setRecipient(recipient, true);
        vault.setAutoLimit(autoLimit);
        vm.stopBroadcast();

        console2.log("FactoryV37", address(factory));
        console2.log("VaultV37", address(vault));
        console2.log("PolicyGuard", address(vault.guard()));
        console2.log("Owner", vault.owner());
        console2.log("Executor", vault.executor());
        console2.log("AutoLimit", vault.autoLimitPerTx());
    }
}
