// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { SentinelFactoryV37 } from "../src/SentinelFactoryV37.sol";
import { SentinelVaultV37 } from "../src/SentinelVaultV37.sol";
import { MockQUSDC } from "./mocks/MockQUSDC.sol";

contract SentinelFactoryV37Test is Test {
    MockQUSDC private token;
    SentinelFactoryV37 private factory;
    address private alice = address(0xA11);
    address private bob = address(0xB0B);
    address private relayer = address(0xE01);
    address private shop = address(0x5409);

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        token = new MockQUSDC();
        factory = new SentinelFactoryV37(address(token));
    }

    function testCallerOwnsVaultAndCounterGrows() public {
        vm.prank(alice);
        address v = factory.createVault(relayer, 1_000_000, 5_000_000);
        vm.prank(bob);
        factory.createVault(relayer, 500_000, 1_000_000);
        assertEq(SentinelVaultV37(v).owner(), alice);
        assertEq(SentinelVaultV37(v).executor(), relayer);
        assertEq(factory.totalVaults(), 2);
        assertEq(factory.vaultAt(0), v);
        assertEq(factory.getDeployedVaults(alice).length, 1);
    }

    function testRejectsAbovePreviewCaps() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(SentinelFactoryV37.AbovePreviewCap.selector, 1_000_001, 5_000_000));
        factory.createVault(relayer, 1_000_001, 5_000_000);
        vm.expectRevert(abi.encodeWithSelector(SentinelFactoryV37.AbovePreviewCap.selector, 1_000_000, 5_000_001));
        factory.createVault(relayer, 1_000_000, 5_000_001);
        vm.stopPrank();
    }

    function testRejectsSelfExecutorAndZero() public {
        vm.startPrank(alice);
        vm.expectRevert(SentinelFactoryV37.ExecutorMustDifferFromOwner.selector);
        factory.createVault(alice, 1, 1);
        vm.expectRevert(SentinelFactoryV37.InvalidExecutor.selector);
        factory.createVault(address(0), 1, 1);
        vm.stopPrank();
    }

    function testEndToEndSharedRelayerIsolatedTenants() public {
        vm.prank(alice);
        SentinelVaultV37 va = SentinelVaultV37(factory.createVault(relayer, 1_000_000, 5_000_000));
        vm.prank(bob);
        SentinelVaultV37 vb = SentinelVaultV37(factory.createVault(relayer, 1_000_000, 5_000_000));
        token.mint(address(va), 2_000_000);
        token.mint(address(vb), 2_000_000);
        vm.startPrank(alice);
        va.setRecipient(shop, true);
        va.setAutoLimit(250_000);
        vm.stopPrank();
        // Same relayer key serves both, but Bob never allowlisted the shop and set no auto limit.
        vm.prank(relayer);
        va.executeAuto(shop, 100_000, 1);
        vm.expectRevert();
        vm.prank(relayer);
        vb.executeAuto(shop, 100_000, 1);
        assertEq(token.balanceOf(shop), 100_000);
        assertEq(token.balanceOf(address(vb)), 2_000_000);
    }

    function testRenounceStillLockedThroughFactory() public {
        vm.prank(alice);
        SentinelVaultV37 v = SentinelVaultV37(factory.createVault(relayer, 1, 1));
        vm.expectRevert();
        vm.prank(alice);
        v.renounceOwnership();
        assertEq(v.owner(), alice);
    }
}
