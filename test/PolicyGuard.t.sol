// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { PolicyGuard } from "../src/PolicyGuard.sol";

contract PolicyGuardTest is Test {
    PolicyGuard internal guard;
    address internal recipient = address(0x123);

    function setUp() public {
        vm.warp(1_800_000_000);
        guard = new PolicyGuard(address(this), 2e6, 5e6);
        guard.setRecipient(recipient, true);
    }

    function test_OnlyVaultMutations() public {
        vm.prank(address(0x456));
        vm.expectRevert(PolicyGuard.OnlyVault.selector);
        guard.consume(recipient, 1);
        vm.prank(address(0x456));
        vm.expectRevert(PolicyGuard.OnlyVault.selector);
        guard.setLimits(1, 2);
    }

    function test_RejectsBadLimits() public {
        vm.expectRevert(PolicyGuard.InvalidLimit.selector);
        guard.setLimits(0, 2);
        vm.expectRevert(PolicyGuard.InvalidLimit.selector);
        guard.setLimits(3, 2);
        vm.expectRevert(PolicyGuard.InvalidLimit.selector);
        guard.setLimits(1, 0);
    }

    function test_Revocation() public {
        guard.setRecipient(recipient, false);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.RecipientNotAllowed.selector, recipient));
        guard.consume(recipient, 1);
    }

    function test_ReducingLimitDoesNotUnderflow() public {
        guard.consume(recipient, 2e6);
        guard.setLimits(1, 1);
        assertEq(guard.remainingToday(), 0);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.DailyLimitExceeded.selector, 1, 0));
        guard.consume(recipient, 1);
    }

    function testFuzz_SpendRemainsWithinLimit(uint96 a, uint96 b) public {
        uint256 first = bound(uint256(a), 1, 2e6);
        uint256 second = bound(uint256(b), 1, 2e6);
        guard.consume(recipient, first);
        guard.consume(recipient, second);
        assertLe(guard.spentByDay(block.timestamp / 1 days), 5e6);
    }

    function testFuzz_DayIsolation(uint32 offset) public {
        uint256 elapsed = bound(uint256(offset), 1, 365);
        uint256 firstDay = block.timestamp / 1 days;
        guard.consume(recipient, 2e6);
        vm.warp((firstDay + elapsed) * 1 days);
        assertEq(guard.remainingToday(), 5e6);
        assertEq(guard.spentByDay(firstDay), 2e6);
    }
}
