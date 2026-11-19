// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { SentinelVault } from "../../src/SentinelVault.sol";
import { MockQUSDC } from "../mocks/MockQUSDC.sol";

/// @notice Stateful handler intentionally exercises both successful and rejected transfers.
contract SentinelHandler is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;
    uint256 internal constant ATTACKER_KEY = 0xB0B;
    uint256 internal constant UNIT = 1e6;

    SentinelVault public immutable vault;
    MockQUSDC public immutable stable;
    address public immutable owner;
    address public immutable executor;
    address public immutable recipient;
    address public immutable attacker;
    uint256 public ghostPaid;
    uint256 public ghostRecovered;
    uint256 public ghostDeposited;
    uint256 public ghostSuccessfulPayments;
    uint256 public ghostRejected;
    mapping(uint256 => uint256) public ghostSpentByDay;

    uint256 private attackNonce = 1 << 128;
    SentinelVault.Payment private lastPayment;
    bytes private lastSignature;
    bool private hasPayment;

    constructor(
        SentinelVault vault_,
        MockQUSDC stable_,
        address owner_,
        address executor_,
        address recipient_
    ) {
        vault = vault_;
        stable = stable_;
        owner = owner_;
        executor = executor_;
        recipient = recipient_;
        attacker = vm.addr(ATTACKER_KEY);
        ghostDeposited = stable_.balanceOf(address(vault_));
    }

    function _payment(uint256 amount, uint256 nonce) private view returns (SentinelVault.Payment memory) {
        return
            SentinelVault.Payment(
                address(stable), recipient, amount, nonce, block.timestamp + 1 hours, executor
            );
    }

    function _sign(SentinelVault.Payment memory p, uint256 key) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r, s, v);
    }

    function _nextNonce() private returns (uint256 nonce) {
        nonce = attackNonce++;
    }

    /// @dev Any unexpected success or side-effect immediately fails the invariant run.
    function _mustReject(SentinelVault.Payment memory p, bytes memory signature, address caller) private {
        uint256 beforeVault = stable.balanceOf(address(vault));
        uint256 beforeRecipient = stable.balanceOf(recipient);
        uint256 beforeAttacker = stable.balanceOf(attacker);
        uint256 day = block.timestamp / 1 days;
        uint256 beforeSpent = vault.guard().spentByDay(day);
        bool beforeNonce = vault.isNonceUsed(p.nonce);

        vm.prank(caller);
        (bool success,) = address(vault).call(abi.encodeCall(SentinelVault.execute, (p, signature)));
        assertFalse(success, "unsafe payment accepted");
        assertEq(stable.balanceOf(address(vault)), beforeVault, "vault balance changed on reject");
        assertEq(stable.balanceOf(recipient), beforeRecipient, "recipient balance changed on reject");
        assertEq(stable.balanceOf(attacker), beforeAttacker, "attacker balance changed on reject");
        assertEq(vault.guard().spentByDay(day), beforeSpent, "budget changed on reject");
        assertEq(vault.isNonceUsed(p.nonce), beforeNonce, "nonce changed on reject");
        ghostRejected++;
    }

    function pay(uint96 randomAmount, uint64 nonceSeed) external {
        uint256 amount = bound(uint256(randomAmount), 1, 2 * UNIT);
        uint256 day = block.timestamp / 1 days;
        if (vault.paused() || stable.balanceOf(address(vault)) < amount) return;
        if (ghostSpentByDay[day] + amount > vault.guard().dailyLimit()) return;
        uint256 nonce = uint256(nonceSeed);
        if (vault.isNonceUsed(nonce)) return;
        SentinelVault.Payment memory p = _payment(amount, nonce);
        bytes memory signature = _sign(p, OWNER_KEY);
        vm.prank(executor);
        vault.execute(p, signature);
        ghostPaid += amount;
        ghostSpentByDay[day] += amount;
        ghostSuccessfulPayments++;
        lastPayment = p;
        lastSignature = signature;
        hasPayment = true;
    }

    function rejectUnauthorized(uint96 rawAmount) external {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), _nextNonce());
        _mustReject(p, _sign(p, OWNER_KEY), attacker);
    }

    function rejectBadSignature(uint96 rawAmount) external {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), _nextNonce());
        _mustReject(p, _sign(p, ATTACKER_KEY), executor);
    }

    function rejectBlockedRecipient(uint96 rawAmount) external {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), _nextNonce());
        p.recipient = attacker;
        _mustReject(p, _sign(p, OWNER_KEY), executor);
    }

    function rejectOverLimit(uint96 rawExcess) external {
        uint256 amount = vault.guard().maxPerTransfer() + 1 + bound(uint256(rawExcess), 0, 10 * UNIT);
        SentinelVault.Payment memory p = _payment(amount, _nextNonce());
        _mustReject(p, _sign(p, OWNER_KEY), executor);
    }

    function rejectExpired(uint96 rawAmount) external {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), _nextNonce());
        p.deadline = block.timestamp - 1;
        _mustReject(p, _sign(p, OWNER_KEY), executor);
    }

    function rejectPaused(uint96 rawAmount) external {
        SentinelVault.Payment memory p = _payment(bound(uint256(rawAmount), 1, 2 * UNIT), _nextNonce());
        bytes memory signature = _sign(p, OWNER_KEY);
        vm.prank(owner);
        vault.pause();
        _mustReject(p, signature, executor);
        vm.prank(owner);
        vault.unpause();
    }

    function rejectReplay() external {
        if (!hasPayment) return;
        _mustReject(lastPayment, lastSignature, executor);
    }

    function rotateDay(uint8 daysForward) external {
        uint256 delta = bound(uint256(daysForward), 1, 7);
        vm.warp(block.timestamp + delta * 1 days);
    }

    function emergencyRecover(uint96 rawAmount) external {
        uint256 available = stable.balanceOf(address(vault));
        if (available == 0) return;
        uint256 amount = bound(uint256(rawAmount), 1, available);
        vm.startPrank(owner);
        vault.pause();
        vault.emergencyRecover(owner, amount);
        vault.unpause();
        vm.stopPrank();
        ghostRecovered += amount;
    }

    function deposit(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 1, 5 * UNIT);
        stable.mint(address(vault), amount);
        ghostDeposited += amount;
    }
}
