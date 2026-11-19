// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { SentinelVault } from "../src/SentinelVault.sol";
import { MockQUSDC } from "./mocks/MockQUSDC.sol";

/// @notice Independent security regression tests with explicit unchanged-state assertions.
contract SentinelAdversarialTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;
    uint256 internal constant WRONG_KEY = 0xB0B;
    uint256 internal constant UNIT = 1e6;
    MockQUSDC internal token;
    SentinelVault internal vault;
    address internal owner;
    address internal executor = address(0xE);
    address internal recipient = address(0xBEEF);
    address internal attacker = address(0xBAD);

    function setUp() public {
        vm.warp(1_800_000_000);
        owner = vm.addr(OWNER_KEY);
        token = new MockQUSDC();
        vault = new SentinelVault(address(token), owner, executor, 2 * UNIT, 5 * UNIT);
        token.mint(address(vault), 20 * UNIT);
        vm.prank(owner);
        vault.setRecipient(recipient, true);
    }

    function _payment(uint256 amount, uint256 nonce) internal view returns (SentinelVault.Payment memory) {
        return
            SentinelVault.Payment(
                address(token), recipient, amount, nonce, block.timestamp + 1 hours, executor
            );
    }

    function _sign(SentinelVault.Payment memory p, uint256 key) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r, s, v);
    }

    function _rejectWithoutSideEffects(SentinelVault.Payment memory p, bytes memory sig, address caller)
        internal
    {
        uint256 vaultBefore = token.balanceOf(address(vault));
        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 attackerBefore = token.balanceOf(attacker);
        uint256 day = block.timestamp / 1 days;
        uint256 spentBefore = vault.guard().spentByDay(day);
        bool usedBefore = vault.isNonceUsed(p.nonce);
        vm.prank(caller);
        (bool ok,) = address(vault).call(abi.encodeCall(SentinelVault.execute, (p, sig)));
        assertFalse(ok, "unexpected authorization");
        assertEq(token.balanceOf(address(vault)), vaultBefore);
        assertEq(token.balanceOf(recipient), recipientBefore);
        assertEq(token.balanceOf(attacker), attackerBefore);
        assertEq(vault.guard().spentByDay(day), spentBefore);
        assertEq(vault.isNonceUsed(p.nonce), usedBefore);
    }

    function testFuzz_RejectUnauthorizedCaller(uint96 rawAmount) public {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), 101);
        _rejectWithoutSideEffects(p, _sign(p, OWNER_KEY), attacker);
    }

    function testFuzz_RejectNonOwnerSignature(uint96 rawAmount) public {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), 102);
        _rejectWithoutSideEffects(p, _sign(p, WRONG_KEY), executor);
    }

    function testFuzz_RejectBlockedRecipient(uint96 rawAmount) public {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), 103);
        p.recipient = attacker;
        _rejectWithoutSideEffects(p, _sign(p, OWNER_KEY), executor);
    }

    function testFuzz_RejectOverspend(uint96 rawExcess) public {
        uint256 amount = 2 * UNIT + 1 + bound(uint256(rawExcess), 0, 100 * UNIT);
        SentinelVault.Payment memory p = _payment(amount, 104);
        _rejectWithoutSideEffects(p, _sign(p, OWNER_KEY), executor);
    }

    function testFuzz_RejectExpired(uint96 rawAmount) public {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), 105);
        p.deadline = block.timestamp - 1;
        _rejectWithoutSideEffects(p, _sign(p, OWNER_KEY), executor);
    }

    function test_RejectPaused() public {
        SentinelVault.Payment memory p = _payment(UNIT, 106);
        bytes memory sig = _sign(p, OWNER_KEY);
        vm.prank(owner);
        vault.pause();
        _rejectWithoutSideEffects(p, sig, executor);
    }

    function test_ReplayCannotDoubleSpend() public {
        SentinelVault.Payment memory p = _payment(UNIT, 107);
        bytes memory sig = _sign(p, OWNER_KEY);
        vm.prank(executor);
        vault.execute(p, sig);
        _rejectWithoutSideEffects(p, sig, executor);
    }

    function test_InsufficientFundsCannotBurnNonceOrBudget() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(owner);
        vault.emergencyRecover(owner, 20 * UNIT);
        vm.prank(owner);
        vault.unpause();
        SentinelVault.Payment memory p = _payment(UNIT, 108);
        _rejectWithoutSideEffects(p, _sign(p, OWNER_KEY), executor);
    }

    function test_OwnerCannotRecoverUntilPaused() public {
        vm.prank(owner);
        (bool ok,) = address(vault).call(abi.encodeCall(SentinelVault.emergencyRecover, (owner, UNIT)));
        assertFalse(ok);
        assertEq(token.balanceOf(address(vault)), 20 * UNIT);
    }
}
