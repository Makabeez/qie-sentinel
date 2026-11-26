// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV29} from "../../src/SentinelVaultV29.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";

/// @notice Stateful adversarial handler for separate epoch-protected user vaults.
/// @dev All signatures use throwaway keys inside an ephemeral Foundry VM.
contract SentinelV31Handler is Test {
    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant BOB_KEY = 0xB0B;
    uint256 private constant FUNDING = 1_000_000;
    address private constant EXEC_A = address(0xE01);
    address private constant EXEC_B = address(0xE02);
    address private constant EXEC_ALT = address(0xE03);
    address private constant RECIP_A = address(0xCAFE);
    address private constant RECIP_B = address(0xBEEF);
    address private constant ATTACKER = address(0xBAD);

    SentinelVaultV29 public immutable a;
    SentinelVaultV29 public immutable b;
    MockQUSDC public immutable token;
    address public immutable alice;
    address public immutable bob;

    uint256 public paidA;
    uint256 public paidB;
    uint256 public nonceA;
    uint256 public nonceB;
    uint256 public rejects;
    uint256 public lastExecutorEpochA;
    uint256 public lastExecutorEpochB;
    uint256 public lastOwnerEpochA;
    uint256 public lastOwnerEpochB;

    constructor(SentinelVaultV29 a_, SentinelVaultV29 b_, MockQUSDC token_) {
        a = a_;
        b = b_;
        token = token_;
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        lastExecutorEpochA = a.executorEpoch();
        lastExecutorEpochB = b.executorEpoch();
        lastOwnerEpochA = a.ownerEpoch();
        lastOwnerEpochB = b.ownerEpoch();
    }

    function _payment(SentinelVaultV29 vault, address recipient, uint256 nonce, uint256 amount)
        private view returns (SentinelVaultV29.Payment memory)
    {
        return SentinelVaultV29.Payment({
            token: address(token), recipient: recipient, amount: amount, nonce: nonce,
            deadline: block.timestamp + 1 hours, executor: vault.executor(),
            ownerEpoch: vault.ownerEpoch(), executorEpoch: vault.executorEpoch()
        });
    }

    function _sign(SentinelVaultV29 vault, SentinelVaultV29.Payment memory payment, uint256 key)
        private returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(payment));
        return abi.encodePacked(r,s,v);
    }

    function _pay(SentinelVaultV29 vault, address recipient, uint256 key, bool isA, uint96 seed) private {
        uint256 remaining = vault.guard().remainingToday();
        uint256 balance = token.balanceOf(address(vault));
        uint256 ceiling = vault.guard().maxPerTransfer();
        if (remaining < ceiling) ceiling = remaining;
        if (balance < ceiling) ceiling = balance;
        if (ceiling == 0) return;
        uint256 amount = bound(uint256(seed),1,ceiling);
        uint256 nonce = isA ? nonceA++ : nonceB++;
        SentinelVaultV29.Payment memory payment = _payment(vault,recipient,nonce,amount);
        bytes memory signature = _sign(vault,payment,key);
        vm.prank(vault.executor());
        vault.execute(payment,signature);
        if (isA) paidA += amount;
        else paidB += amount;
        assertTrue(vault.isNonceUsed(nonce));
    }

    function payA(uint96 seed) external {
        _pay(a,RECIP_A,ALICE_KEY,true,seed);
    }

    function payB(uint96 seed) external {
        _pay(b,RECIP_B,BOB_KEY,false,seed);
    }

    function rotateA(uint8 choice) external {
        uint256 prior = a.executorEpoch();
        vm.prank(alice);
        a.setExecutor(choice % 2 == 0 ? EXEC_A : EXEC_ALT);
        assertEq(a.executorEpoch(), prior+1);
        lastExecutorEpochA = a.executorEpoch();
    }

    function rotateB(uint8 choice) external {
        uint256 prior = b.executorEpoch();
        vm.prank(bob);
        b.setExecutor(choice % 2 == 0 ? EXEC_B : EXEC_ALT);
        assertEq(b.executorEpoch(), prior+1);
        lastExecutorEpochB = b.executorEpoch();
    }

    // Each round trip to a temporary owner must advance the owner epoch twice.
    // The old owner's unspent signature stays invalid after restoration.
    function transferOwnerA(uint8 seed) external {
        address temporary = seed % 2 == 0 ? ATTACKER : bob;
        uint256 beforeEpoch = a.ownerEpoch();
        uint256 nonce = 1024 + uint256(seed);
        SentinelVaultV29.Payment memory p = _payment(a,RECIP_A,nonce,1);
        bytes memory stale = _sign(a,p,ALICE_KEY);
        vm.prank(alice);
        a.transferOwnership(temporary);
        vm.prank(temporary);
        a.acceptOwnership();
        vm.prank(temporary);
        a.transferOwnership(alice);
        vm.prank(alice);
        a.acceptOwnership();
        assertEq(a.ownerEpoch(),beforeEpoch+2);
        uint256 beforeBalance=token.balanceOf(address(a));
        vm.prank(a.executor());
        (bool ok,)=address(a).call(abi.encodeCall(SentinelVaultV29.execute,(p,stale)));
        assertFalse(ok);
        assertEq(token.balanceOf(address(a)),beforeBalance);
        assertFalse(a.isNonceUsed(nonce));
        lastOwnerEpochA=a.ownerEpoch();
        rejects++;
    }

    function transferOwnerB(uint8 seed) external {
        address temporary = seed % 2 == 0 ? ATTACKER : alice;
        uint256 beforeEpoch = b.ownerEpoch();
        uint256 nonce = 1024 + uint256(seed);
        SentinelVaultV29.Payment memory p = _payment(b,RECIP_B,nonce,1);
        bytes memory stale = _sign(b,p,BOB_KEY);
        vm.prank(bob);
        b.transferOwnership(temporary);
        vm.prank(temporary);
        b.acceptOwnership();
        vm.prank(temporary);
        b.transferOwnership(bob);
        vm.prank(bob);
        b.acceptOwnership();
        assertEq(b.ownerEpoch(),beforeEpoch+2);
        uint256 beforeBalance=token.balanceOf(address(b));
        vm.prank(b.executor());
        (bool ok,)=address(b).call(abi.encodeCall(SentinelVaultV29.execute,(p,stale)));
        assertFalse(ok);
        assertEq(token.balanceOf(address(b)),beforeBalance);
        assertFalse(b.isNonceUsed(nonce));
        lastOwnerEpochB=b.ownerEpoch();
        rejects++;
    }

    // Reserve high nonces for cancellation, separate from sequential payment nonces.
    function cancelA(uint8 seed) external {
        uint256 nonce = 128 + uint256(seed) % 128;
        vm.prank(alice);
        a.invalidateNonces(0,uint256(1)<<nonce);
        assertTrue(a.isNonceUsed(nonce));
    }

    function cancelB(uint8 seed) external {
        uint256 nonce = 128 + uint256(seed) % 128;
        vm.prank(bob);
        b.invalidateNonces(0,uint256(1)<<nonce);
        assertTrue(b.isNonceUsed(nonce));
    }

    function rejectCrossOwnerA(uint96 seed) external {
        uint256 nonce = 512 + uint256(seed);
        SentinelVaultV29.Payment memory p = _payment(a,RECIP_A,nonce,1);
        bytes memory bad = _sign(a,p,BOB_KEY);
        uint256 beforeBalance = token.balanceOf(address(a));
        uint256 beforeSpent = a.guard().spentByDay(block.timestamp / 1 days);
        vm.prank(a.executor());
        (bool success,) = address(a).call(abi.encodeCall(SentinelVaultV29.execute,(p,bad)));
        assertFalse(success);
        assertFalse(a.isNonceUsed(nonce));
        assertEq(token.balanceOf(address(a)),beforeBalance);
        assertEq(a.guard().spentByDay(block.timestamp / 1 days),beforeSpent);
        rejects++;
    }

    function rejectUnauthorizedB(uint96 seed) external {
        uint256 nonce = 512 + uint256(seed);
        SentinelVaultV29.Payment memory p = _payment(b,RECIP_B,nonce,1);
        bytes memory valid = _sign(b,p,BOB_KEY);
        uint256 beforeBalance = token.balanceOf(address(b));
        vm.prank(ATTACKER);
        (bool success,) = address(b).call(abi.encodeCall(SentinelVaultV29.execute,(p,valid)));
        assertFalse(success);
        assertFalse(b.isNonceUsed(nonce));
        assertEq(token.balanceOf(address(b)),beforeBalance);
        rejects++;
    }

    function checkConservation() external view {
        assertEq(token.balanceOf(address(a)) + paidA,FUNDING);
        assertEq(token.balanceOf(address(b)) + paidB,FUNDING);
        assertEq(token.balanceOf(RECIP_A),paidA);
        assertEq(token.balanceOf(RECIP_B),paidB);
        assertEq(token.balanceOf(ATTACKER),0);
        assertEq(a.guard().spentByDay(block.timestamp/1 days),paidA);
        assertEq(b.guard().spentByDay(block.timestamp/1 days),paidB);
        assertLe(paidA,a.guard().dailyLimit());
        assertLe(paidB,b.guard().dailyLimit());
        assertEq(a.owner(),alice);
        assertEq(b.owner(),bob);
        assertEq(lastExecutorEpochA,a.executorEpoch());
        assertEq(lastExecutorEpochB,b.executorEpoch());
        assertEq(lastOwnerEpochA,a.ownerEpoch());
        assertEq(lastOwnerEpochB,b.ownerEpoch());
    }
}
