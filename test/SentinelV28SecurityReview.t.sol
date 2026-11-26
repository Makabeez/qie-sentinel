// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {PolicyGuard} from "../src/PolicyGuard.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";

/// @notice v2.8 pre-audit edge cases, entirely local with disposable keys.
/// @dev Exercises existing contract unchanged. Never uses production wallets.
contract SentinelV28SecurityReviewTest is Test {
    uint256 internal constant OLD_KEY = 0xA11CE;
    uint256 internal constant NEW_KEY = 0xB0B;
    address internal oldOwner;
    address internal newOwner;
    address internal executor = address(0xE01);
    address internal recipient = address(0xCAFE);
    address internal outsider = address(0xBAD);
    MockQUSDC internal token;
    SentinelVault internal vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        oldOwner = vm.addr(OLD_KEY);
        newOwner = vm.addr(NEW_KEY);
        token = new MockQUSDC();
        vault = new SentinelVault(address(token), oldOwner, executor, 250_000, 400_000);
        token.mint(address(vault), 1_000_000);
        vm.prank(oldOwner);
        vault.setRecipient(recipient, true);
    }

    function _payment(uint256 nonce, uint256 amount) internal view returns (SentinelVault.Payment memory) {
        return SentinelVault.Payment({
            token: address(token), recipient: recipient, amount: amount,
            nonce: nonce, deadline: block.timestamp + 1 hours, executor: executor
        });
    }

    function _sign(SentinelVault.Payment memory p, uint256 key) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r,s,v);
    }

    function _assertUnspent(uint256 nonce) internal view {
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(vault)), 1_000_000);
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testV28TransferRequiresAcceptanceByNewOwner() public {
        vm.prank(oldOwner);
        vault.transferOwnership(newOwner);
        assertEq(vault.owner(), oldOwner);
        assertEq(vault.pendingOwner(), newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        vm.prank(outsider);
        vault.acceptOwnership();
        assertEq(vault.owner(), oldOwner);
        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(), newOwner);
        assertEq(vault.pendingOwner(), address(0));
    }

    function testV28OldOwnerSignedIntentInvalidAfterOwnershipTransfer() public {
        SentinelVault.Payment memory p = _payment(40, 100_000);
        bytes memory oldSig = _sign(p, OLD_KEY);
        vm.prank(oldOwner);
        vault.transferOwnership(newOwner);
        vm.prank(newOwner);
        vault.acceptOwnership();

        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, oldSig);
        _assertUnspent(40);

        bytes memory newSig = _sign(p, NEW_KEY);
        vm.prank(executor);
        vault.execute(p, newSig);
        assertTrue(vault.isNonceUsed(40));
        assertEq(token.balanceOf(recipient), 100_000);
    }

    function testV28RevokedRecipientBlocksPreviouslySignedIntentWithoutNonceBurn() public {
        SentinelVault.Payment memory p = _payment(41, 100_000);
        bytes memory sig = _sign(p, OLD_KEY);
        vm.prank(oldOwner);
        vault.setRecipient(recipient, false);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.RecipientNotAllowed.selector, recipient));
        vm.prank(executor);
        vault.execute(p, sig);
        _assertUnspent(41);
    }

    function testV28LoweredLimitsBlockPreviouslySignedIntentWithoutNonceBurn() public {
        SentinelVault.Payment memory p = _payment(42, 100_000);
        bytes memory sig = _sign(p, OLD_KEY);
        vm.prank(oldOwner);
        vault.setLimits(50_000, 100_000);
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.TransferLimitExceeded.selector, uint256(100_000), uint256(50_000)));
        vm.prank(executor);
        vault.execute(p, sig);
        _assertUnspent(42);
    }

    function testV28RecoveryRequiresPauseAndOwnerAndCanBypassPolicyByDesign() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(oldOwner);
        vault.emergencyRecover(outsider, 100_000);
        vm.prank(oldOwner);
        vault.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        vm.prank(outsider);
        vault.emergencyRecover(outsider, 100_000);

        // This bypasses the recipient allowlist and daily limit by explicit design.
        // It is a privileged owner escape hatch and must be disclosed in any UX.
        vm.prank(oldOwner);
        vault.emergencyRecover(outsider, 600_000);
        assertEq(token.balanceOf(outsider), 600_000);
        assertEq(token.balanceOf(address(vault)), 400_000);
        assertFalse(vault.guard().allowedRecipients(outsider));
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testV28FailedTokenTransferRollsBackNonceAndBudget() public {
        SentinelVault.Payment memory p = _payment(43, 100_000);
        bytes memory sig = _sign(p, OLD_KEY);
        // Vault balance no longer covers payment. SafeERC20 reverts and both
        // earlier nonce consumption and PolicyGuard budget write roll back.
        vm.prank(oldOwner);
        vault.pause();
        vm.prank(oldOwner);
        vault.emergencyRecover(oldOwner, 950_000);
        vm.prank(oldOwner);
        vault.unpause();

        vm.expectRevert();
        vm.prank(executor);
        vault.execute(p, sig);
        assertFalse(vault.isNonceUsed(43));
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(vault)), 50_000);
    }

    /// @notice Documented design caveat: returning ownership to a past signer
    ///         makes their previously valid, unconsumed signed intent valid again.
    ///         A production v3 should include owner epochs or explicit nonce
    ///         invalidation on each owner change. DO NOT change submitted v1.1.
    function testV28PreviouslySignedIntentRevalidatesWhenOwnershipReturns() public {
        SentinelVault.Payment memory p = _payment(44, 100_000);
        bytes memory originalSig = _sign(p, OLD_KEY);

        vm.prank(oldOwner);
        vault.transferOwnership(newOwner);
        vm.prank(newOwner);
        vault.acceptOwnership();

        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, originalSig);
        assertFalse(vault.isNonceUsed(44));

        vm.prank(newOwner);
        vault.transferOwnership(oldOwner);
        vm.prank(oldOwner);
        vault.acceptOwnership();

        // This succeeds under the EXISTING signature schema.
        // It documents a revivability risk, not a production endorsement.
        vm.prank(executor);
        vault.execute(p, originalSig);
        assertTrue(vault.isNonceUsed(44));
        assertEq(token.balanceOf(recipient), 100_000);
    }

    /// @notice Executor rotation only changes present executor authorization.
    ///         A previously signed intent can execute after rotation back.
    function testV28PreviouslySignedIntentRevalidatesWhenExecutorReturns() public {
        SentinelVault.Payment memory p = _payment(45, 100_000);
        bytes memory originalSig = _sign(p, OLD_KEY);

        vm.prank(oldOwner);
        vault.setExecutor(outsider);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, executor));
        vm.prank(executor);
        vault.execute(p, originalSig);
        assertFalse(vault.isNonceUsed(45));

        vm.prank(oldOwner);
        vault.setExecutor(executor);
        vm.prank(executor);
        vault.execute(p, originalSig);
        assertTrue(vault.isNonceUsed(45));
        assertEq(token.balanceOf(recipient), 100_000);
    }
}
