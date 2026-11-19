// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { SentinelVault } from "../../src/SentinelVault.sol";
import { PolicyGuard } from "../../src/PolicyGuard.sol";
import { MockQUSDC } from "../mocks/MockQUSDC.sol";
import { SentinelHandler } from "./SentinelHandler.sol";

contract SentinelInvariantTest is StdInvariant, Test {
    uint256 internal constant UNIT = 1e6;
    SentinelVault internal vault;
    MockQUSDC internal stable;
    SentinelHandler internal handler;
    address internal owner;
    address internal executor = address(0xE);
    address internal recipient = address(0xBEEF);

    function setUp() public {
        vm.warp(1_800_000_000);
        owner = vm.addr(0xA11CE);
        stable = new MockQUSDC();
        vault = new SentinelVault(address(stable), owner, executor, 2 * UNIT, 5 * UNIT);
        stable.mint(address(vault), 20 * UNIT);
        vm.prank(owner);
        vault.setRecipient(recipient, true);
        handler = new SentinelHandler(vault, stable, owner, executor, recipient);
        targetContract(address(handler));
    }

    function invariant_ConservationOfFunds() public view {
        assertEq(
            stable.balanceOf(address(vault)) + handler.ghostPaid() + handler.ghostRecovered(),
            handler.ghostDeposited()
        );
        assertEq(stable.balanceOf(recipient), handler.ghostPaid());
    }

    function invariant_NeverSpendsOverDailyBudget() public view {
        uint256 day = block.timestamp / 1 days;
        assertLe(vault.guard().spentByDay(day), vault.guard().dailyLimit());
        assertEq(vault.guard().spentByDay(day), handler.ghostSpentByDay(day));
    }

    function invariant_RejectedAttemptsNeverChangeState() public view {
        assertEq(stable.balanceOf(handler.attacker()), 0);
    }

    function invariant_OnlyApprovedTokenAndRecipientReceiveAgentFunds() public view {
        assertEq(address(vault.token()), address(stable));
        assertEq(vault.guard().allowedRecipients(recipient), true);
        assertEq(stable.balanceOf(executor), 0);
    }
}
