// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SentinelEpochFactoryV30} from "../../src/SentinelEpochFactoryV30.sol";
import {SentinelVaultV29} from "../../src/SentinelVaultV29.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";
import {SentinelV31Handler} from "./SentinelV31Handler.sol";

/// @notice Stateful random interleavings of two users and their own vaults.
/// @dev Only local Foundry VM, mock QUSDC, synthetic test accounts and signatures.
contract SentinelV31InvariantTest is StdInvariant, Test {
    SentinelEpochFactoryV30 internal factory;
    SentinelVaultV29 internal a;
    SentinelVaultV29 internal b;
    MockQUSDC internal token;
    SentinelV31Handler internal handler;

    function setUp() public {
        vm.chainId(1990); // no QIE RPC connection
        vm.warp(1_800_000_000);
        token = new MockQUSDC();
        factory = new SentinelEpochFactoryV30(address(token));

        address alice = vm.addr(0xA11CE);
        address bob = vm.addr(0xB0B);
        vm.prank(alice);
        a = SentinelVaultV29(factory.createVault(address(0xE01),250_000,400_000));
        vm.prank(bob);
        b = SentinelVaultV29(factory.createVault(address(0xE02),250_000,400_000));
        vm.prank(alice);
        a.setRecipient(address(0xCAFE),true);
        vm.prank(bob);
        b.setRecipient(address(0xBEEF),true);
        token.mint(address(a),1_000_000);
        token.mint(address(b),1_000_000);
        handler = new SentinelV31Handler(a,b,token);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.payA.selector;
        selectors[1] = handler.payB.selector;
        selectors[2] = handler.rotateA.selector;
        selectors[3] = handler.rotateB.selector;
        selectors[4] = handler.cancelA.selector;
        selectors[5] = handler.cancelB.selector;
        selectors[6] = handler.rejectCrossOwnerA.selector;
        selectors[7] = handler.rejectUnauthorizedB.selector;
        selectors[8] = handler.transferOwnerA.selector;
        selectors[9] = handler.transferOwnerB.selector;
        targetSelector(FuzzSelector({addr:address(handler),selectors:selectors}));
        targetContract(address(handler));
    }

    function invariant_VaultBalancesMatchSuccessfulTransfers() public view {
        handler.checkConservation();
    }

    function invariant_SignersAndPoliciesRemainTenantIsolated() public view {
        assertTrue(address(a) != address(b));
        assertTrue(address(a.guard()) != address(b.guard()));
        assertEq(a.guard().vault(),address(a));
        assertEq(b.guard().vault(),address(b));
        assertEq(a.owner(),handler.alice());
        assertEq(b.owner(),handler.bob());
        assertFalse(a.guard().allowedRecipients(address(0xBEEF)));
        assertFalse(b.guard().allowedRecipients(address(0xCAFE)));
        assertEq(factory.deployedCount(handler.alice()),1);
        assertEq(factory.deployedCount(handler.bob()),1);
    }

    function invariant_NoncesAndEpochsRemainScoped() public view {
        assertEq(a.executorEpoch(),handler.lastExecutorEpochA());
        assertEq(b.executorEpoch(),handler.lastExecutorEpochB());
        assertEq(a.ownerEpoch(),handler.lastOwnerEpochA());
        assertEq(b.ownerEpoch(),handler.lastOwnerEpochB());
        assertLe(a.guard().spentByDay(block.timestamp/1 days),a.guard().dailyLimit());
        assertLe(b.guard().spentByDay(block.timestamp/1 days),b.guard().dailyLimit());
    }
}
