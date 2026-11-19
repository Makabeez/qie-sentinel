// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { SentinelVault } from "../src/SentinelVault.sol";
import { PolicyGuard } from "../src/PolicyGuard.sol";
import { MockQUSDC } from "./mocks/MockQUSDC.sol";
import { Mock1271Owner } from "./mocks/Mock1271Owner.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract SentinelVaultTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;
    uint256 internal constant OTHER_KEY = 0xB0B;
    uint256 internal constant UNIT = 1e6;
    address internal owner;
    address internal executor = address(0xE);
    address internal recipient = address(0xBEEF);
    address internal attacker;
    MockQUSDC internal stable;
    SentinelVault internal vault;
    PolicyGuard internal guard;

    function setUp() public {
        owner = vm.addr(OWNER_KEY);
        attacker = vm.addr(OTHER_KEY);
        vm.warp(1_800_000_000);
        stable = new MockQUSDC();
        vault = new SentinelVault(address(stable), owner, executor, 2 * UNIT, 5 * UNIT);
        guard = vault.guard();
        stable.mint(address(vault), 100 * UNIT);
        vm.prank(owner);
        vault.setRecipient(recipient, true);
    }

    function _payment(uint256 amount, uint256 nonce) internal view returns (SentinelVault.Payment memory) {
        return SentinelVault.Payment(
            address(stable), recipient, amount, nonce, block.timestamp + 1 hours, executor
        );
    }

    function _sign(SentinelVault.Payment memory p, uint256 key) internal returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor)"
                ),
                p.token,
                p.recipient,
                p.amount,
                p.nonce,
                p.deadline,
                p.executor
            )
        );
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("QIE Sentinel Vault")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _execute(SentinelVault.Payment memory p) internal {
        bytes memory sig = _sign(p, OWNER_KEY);
        vm.prank(executor);
        vault.execute(p, sig);
    }

    function test_ConstructionAndDomain() public view {
        assertEq(address(vault.token()), address(stable));
        assertEq(vault.executor(), executor);
        assertEq(vault.owner(), owner);
        assertEq(guard.vault(), address(vault));
        assertTrue(vault.domainSeparator() != bytes32(0));
    }

    function test_ValidPaymentTransfersAndAccountsForBudget() public {
        _execute(_payment(2 * UNIT, 7));
        assertEq(stable.balanceOf(recipient), 2 * UNIT);
        assertEq(vault.balance(), 98 * UNIT);
        assertEq(guard.spentByDay(block.timestamp / 1 days), 2 * UNIT);
        assertEq(guard.remainingToday(), 3 * UNIT);
        assertTrue(vault.isNonceUsed(7));
    }

    function test_ReplayRejected() public {
        SentinelVault.Payment memory p = _payment(UNIT, 27);
        bytes memory sig = _sign(p, OWNER_KEY);
        vm.prank(executor);
        vault.execute(p, sig);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, 27));
        vault.execute(p, sig);
    }

    function test_NonceBitmapBoundaryAndInvalidation() public {
        vm.prank(owner);
        vault.invalidateNonces(1, uint256(1) << 0);
        assertTrue(vault.isNonceUsed(256));
        assertFalse(vault.isNonceUsed(255));
        assertFalse(vault.isNonceUsed(257));
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, 256));
        SentinelVault.Payment memory p = _payment(UNIT, 256);
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_RevertIfWrongExecutor() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, attacker));
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_RevertIfIntentExecutorDoesNotMatch() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        p.executor = attacker;
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, executor));
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_RevertIfWrongSigner() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        vm.prank(executor);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vault.execute(p, _sign(p, OTHER_KEY));
    }

    function test_RevertIfWrongToken() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        p.token = attacker;
        vm.prank(executor);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_RevertIfExpired() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        vm.warp(p.deadline + 1);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(SentinelVault.ExpiredIntent.selector, p.deadline, block.timestamp)
        );
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_ExpiredAtDeadlineAllowed() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        bytes memory sig = _sign(p, OWNER_KEY);
        vm.warp(p.deadline);
        vm.prank(executor);
        vault.execute(p, sig);
        assertEq(stable.balanceOf(recipient), UNIT);
    }

    function test_NotAllowlistedRejectedWithoutNonceBurn() public {
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        p.recipient = attacker;
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.RecipientNotAllowed.selector, attacker));
        vault.execute(p, _sign(p, OWNER_KEY));
        assertFalse(vault.isNonceUsed(0));
    }

    function test_ZeroAndOverLimitRejected() public {
        SentinelVault.Payment memory p = _payment(0, 0);
        vm.prank(executor);
        vm.expectRevert(PolicyGuard.AmountZero.selector);
        vault.execute(p, _sign(p, OWNER_KEY));
        p = _payment(3 * UNIT, 1);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(PolicyGuard.TransferLimitExceeded.selector, 3 * UNIT, 2 * UNIT)
        );
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_DailyLimitAndReset() public {
        _execute(_payment(2 * UNIT, 0));
        _execute(_payment(2 * UNIT, 1));
        _execute(_payment(UNIT, 2));
        SentinelVault.Payment memory p = _payment(1, 3);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.DailyLimitExceeded.selector, 1, 0));
        vault.execute(p, _sign(p, OWNER_KEY));
        vm.warp((block.timestamp / 1 days + 1) * 1 days);
        _execute(_payment(UNIT, 4));
        assertEq(guard.remainingToday(), 4 * UNIT);
    }

    function test_BudgetRollbackWhenTokenInsufficient() public {
        vm.prank(owner);
        vault.pause();
        vm.prank(owner);
        vault.emergencyRecover(owner, 100 * UNIT);
        vm.prank(owner);
        vault.unpause();
        SentinelVault.Payment memory p = _payment(UNIT, 88);
        vm.prank(executor);
        vm.expectRevert();
        vault.execute(p, _sign(p, OWNER_KEY));
        assertFalse(vault.isNonceUsed(88));
        assertEq(guard.spentByDay(block.timestamp / 1 days), 0);
    }

    function test_PauseBlocksExecutionAndRecoveryRequiresPause() public {
        vm.prank(owner);
        vm.expectRevert(bytes4(keccak256("ExpectedPause()")));
        vault.emergencyRecover(owner, UNIT);
        vm.prank(owner);
        vault.pause();
        SentinelVault.Payment memory p = _payment(UNIT, 0);
        vm.prank(executor);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.execute(p, _sign(p, OWNER_KEY));
        vm.prank(owner);
        vault.emergencyRecover(owner, 10 * UNIT);
        assertEq(stable.balanceOf(owner), 10 * UNIT);
        vm.prank(owner);
        vault.unpause();
        _execute(p);
    }

    function test_OnlyOwnerCanConfigure() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setExecutor(attacker);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.setLimits(1, 2);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        vault.pause();
        vm.prank(attacker);
        vm.expectRevert(PolicyGuard.OnlyVault.selector);
        guard.setRecipient(attacker, true);
    }

    function test_ExecutorRotationInvalidatesOldIntents() public {
        SentinelVault.Payment memory p = _payment(UNIT, 1);
        bytes memory signature = _sign(p, OWNER_KEY);
        vm.prank(owner);
        vault.setExecutor(attacker);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, executor));
        vault.execute(p, signature);
        p.executor = attacker;
        vm.prank(attacker);
        vault.execute(p, _sign(p, OWNER_KEY));
    }

    function test_OwnerRotationInvalidatesOldSignatures() public {
        SentinelVault.Payment memory p = _payment(UNIT, 1);
        bytes memory oldSig = _sign(p, OWNER_KEY);
        vm.prank(owner);
        vault.transferOwnership(attacker);
        vm.prank(attacker);
        vault.acceptOwnership();
        vm.prank(executor);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vault.execute(p, oldSig);
        // The new owner can approve new payments with a new signature.
        vm.prank(executor);
        vault.execute(p, _sign(p, OTHER_KEY));
    }

    function test_ContractOwnerCanSignViaERC1271() public {
        Mock1271Owner contractOwner = new Mock1271Owner(owner);
        SentinelVault otherVault =
            new SentinelVault(address(stable), address(contractOwner), executor, UNIT, 3 * UNIT);
        stable.mint(address(otherVault), 3 * UNIT);
        contractOwner.configureRecipient(otherVault, recipient, true);
        SentinelVault.Payment memory p =
            SentinelVault.Payment(address(stable), recipient, UNIT, 0, block.timestamp + 1, executor);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_KEY, otherVault.paymentDigest(p));
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(executor);
        otherVault.execute(p, signature);
        assertEq(stable.balanceOf(recipient), UNIT);
    }

    function testFuzz_ValidAmountTransfers(uint96 rawAmount, uint64 rawNonce) public {
        uint256 amount = bound(uint256(rawAmount), 1, 2 * UNIT);
        uint256 nonce = uint256(rawNonce);
        _execute(_payment(amount, nonce));
        assertEq(stable.balanceOf(recipient), amount);
        assertEq(guard.remainingToday(), 5 * UNIT - amount);
    }

    function testFuzz_ReplayAlwaysFails(uint96 rawAmount, uint64 rawNonce) public {
        uint256 amount = bound(uint256(rawAmount), 1, 2 * UNIT);
        uint256 nonce = uint256(rawNonce);
        SentinelVault.Payment memory p = _payment(amount, nonce);
        bytes memory signature = _sign(p, OWNER_KEY);
        vm.prank(executor);
        vault.execute(p, signature);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, nonce));
        vault.execute(p, signature);
    }

    function testFuzz_OverPerTxAlwaysFails(uint96 excess) public {
        uint256 amount = 2 * UNIT + 1 + bound(uint256(excess), 0, 100 * UNIT);
        SentinelVault.Payment memory p = _payment(amount, 0);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.TransferLimitExceeded.selector, amount, 2 * UNIT));
        vault.execute(p, _sign(p, OWNER_KEY));
        assertFalse(vault.isNonceUsed(0));
    }

    function testFuzz_InvalidatedNonceCannotExecute(uint64 rawNonce) public {
        uint256 nonce = uint256(rawNonce);
        vm.prank(owner);
        vault.invalidateNonces(nonce >> 8, uint256(1) << (nonce & 255));
        SentinelVault.Payment memory p = _payment(UNIT, nonce);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, nonce));
        vault.execute(p, _sign(p, OWNER_KEY));
    }
}
