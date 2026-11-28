// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV37} from "../src/SentinelVaultV37.sol";
import {PolicyGuard} from "../src/PolicyGuard.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";

contract SentinelV37AutonomyTest is Test {
    uint256 private constant OWNER_KEY = 0xA11CE;
    address private owner;
    address private executor = address(0xE01);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;
    SentinelVaultV37 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        owner = vm.addr(OWNER_KEY);
        token = new MockQUSDC();
        vault = new SentinelVaultV37(address(token), owner, executor, 1_000_000, 5_000_000);
        token.mint(address(vault), 100_000_000);
        vm.startPrank(owner);
        vault.setRecipient(recipient, true);
        vault.setAutoLimit(250_000); // agent may pay up to 0.25 QUSDC alone
        vm.stopPrank();
    }

    function testAgentPaysSmallAllowlistedWithoutOwnerSignature() public {
        vm.prank(executor);
        vault.executeAuto(recipient, 250_000, 1);
        assertEq(token.balanceOf(recipient), 250_000);
        assertTrue(vault.isNonceUsed(1));
    }

    function testAboveAutoLimitEscalatesToOwner() public {
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV37.AutoLimitExceeded.selector, 250_001, 250_000));
        vm.prank(executor);
        vault.executeAuto(recipient, 250_001, 1);
    }

    function testUnknownRecipientRejected() public {
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.RecipientNotAllowed.selector, address(0xBAD)));
        vm.prank(executor);
        vault.executeAuto(address(0xBAD), 1, 1);
    }

    function testOnlyExecutor() public {
        vm.expectRevert();
        vm.prank(address(0xBAD));
        vault.executeAuto(recipient, 1, 1);
    }

    function testPausedBlocksAgent() public {
        vm.prank(owner);
        vault.pause();
        vm.expectRevert();
        vm.prank(executor);
        vault.executeAuto(recipient, 1, 1);
    }

    function testOwnerCancelsQueuedAutoNonce() public {
        vm.prank(owner);
        vault.invalidateNonces(0, 1 << 5);
        vm.expectRevert();
        vm.prank(executor);
        vault.executeAuto(recipient, 1, 5);
    }

    function testAutoLimitCannotExceedPerTxCap() public {
        vm.expectRevert();
        vm.prank(owner);
        vault.setAutoLimit(1_000_001);
    }

    /// Stolen hot key: max loss is the daily budget, to allowlisted addresses only.
    function testFuzzStolenExecutorKeyLossBoundedByDailyLimit(uint8 attempts) public {
        uint256 n = uint256(attempts) % 60 + 1;
        for (uint256 i; i < n; ++i) {
            vm.prank(executor);
            try vault.executeAuto(recipient, 250_000, 100 + i) {} catch {}
        }
        assertLe(token.balanceOf(recipient), 5_000_000);
    }
}
