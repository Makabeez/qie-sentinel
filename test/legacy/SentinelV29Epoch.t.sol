// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV29} from "../../src/legacy/SentinelVaultV29.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";

/// @notice Offline non-production V2.9 signature epoch regression suite.
/// @dev Deploys only to ephemeral Foundry EVM using throwaway keys.
contract SentinelV29EpochTest is Test {
    uint256 internal constant ALICE_KEY = 0xA11CE;
    uint256 internal constant BOB_KEY = 0xB0B;
    address internal alice;
    address internal bob;
    address internal executor = address(0xE01);
    address internal alternateExecutor = address(0xE02);
    address internal recipient = address(0xCAFE);
    MockQUSDC internal token;
    SentinelVaultV29 internal vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        token = new MockQUSDC();
        vault = new SentinelVaultV29(address(token), alice, executor, 250_000, 400_000);
        token.mint(address(vault), 1_000_000);
        vm.prank(alice);
        vault.setRecipient(recipient, true);
    }

    function _payment(uint256 nonce) internal view returns (SentinelVaultV29.Payment memory) {
        return SentinelVaultV29.Payment({
            token: address(token), recipient: recipient, amount: 100_000,
            nonce: nonce, deadline: block.timestamp + 1 hours,
            executor: executor, ownerEpoch: vault.ownerEpoch(), executorEpoch: vault.executorEpoch()
        });
    }

    function _sign(SentinelVaultV29.Payment memory p, uint256 key) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r, s, v);
    }

    function _assertUnspent(uint256 nonce) internal view {
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(vault)), 1_000_000);
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testV29FreshOwnerSignatureExecutesWithinCurrentEpoch() public {
        SentinelVaultV29.Payment memory p = _payment(1);
        bytes memory sig = _sign(p, ALICE_KEY);
        vm.prank(executor);
        vault.execute(p, sig);
        assertTrue(vault.isNonceUsed(1));
        assertEq(token.balanceOf(recipient), 100_000);
    }

    function testV29OwnershipReturnPermanentlyInvalidatesOldIntent() public {
        SentinelVaultV29.Payment memory p = _payment(2);
        bytes memory stale = _sign(p, ALICE_KEY);
        uint256 original = vault.ownerEpoch();

        vm.prank(alice);
        vault.transferOwnership(bob);
        vm.prank(bob);
        vault.acceptOwnership();
        vm.prank(bob);
        vault.transferOwnership(alice);
        vm.prank(alice);
        vault.acceptOwnership();

        assertEq(vault.owner(), alice);
        assertEq(vault.ownerEpoch(), original + 2);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.StaleOwnerEpoch.selector, original, original + 2));
        vm.prank(executor);
        vault.execute(p, stale);
        _assertUnspent(2);

        SentinelVaultV29.Payment memory fresh = _payment(3);
        bytes memory sig = _sign(fresh, ALICE_KEY);
        vm.prank(executor);
        vault.execute(fresh, sig);
        assertEq(token.balanceOf(recipient), 100_000);
    }

    function testV29ExecutorReturnPermanentlyInvalidatesOldIntent() public {
        SentinelVaultV29.Payment memory p = _payment(4);
        bytes memory stale = _sign(p, ALICE_KEY);
        uint256 original = vault.executorEpoch();
        vm.prank(alice);
        vault.setExecutor(alternateExecutor);
        vm.prank(alice);
        vault.setExecutor(executor);
        assertEq(vault.executor(), executor);
        assertEq(vault.executorEpoch(), original + 2);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.StaleExecutorEpoch.selector, original, original + 2));
        vm.prank(executor);
        vault.execute(p, stale);
        _assertUnspent(4);
    }

    function testV29ExplicitSameExecutorResetRevokesUnconsumedIntents() public {
        SentinelVaultV29.Payment memory p = _payment(5);
        bytes memory stale = _sign(p, ALICE_KEY);
        uint256 oldEpoch = p.executorEpoch;
        vm.prank(alice);
        vault.setExecutor(executor);
        assertEq(vault.executorEpoch(), oldEpoch + 1);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.StaleExecutorEpoch.selector, oldEpoch, oldEpoch + 1));
        vm.prank(executor);
        vault.execute(p, stale);
        _assertUnspent(5);
    }

    function testV29ChangingIntentEpochBreaksOldSignatureEvenIfValuesNowValid() public {
        SentinelVaultV29.Payment memory p = _payment(6);
        bytes memory sig = _sign(p, ALICE_KEY);
        vm.prank(alice);
        vault.setExecutor(executor);
        // Attacker cannot salvage an old signature just by patching the epoch.
        p.executorEpoch = vault.executorEpoch();
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, sig);
        _assertUnspent(6);
    }

    function testV29FailedOwnershipAcceptanceDoesNotChangeEpoch() public {
        uint256 oldEpoch = vault.ownerEpoch();
        vm.prank(alice);
        vault.transferOwnership(bob);
        assertEq(vault.ownerEpoch(), oldEpoch);
        vm.expectRevert();
        vm.prank(recipient);
        vault.acceptOwnership();
        assertEq(vault.ownerEpoch(), oldEpoch);
    }

    function testV29WrongChainAndDifferentVaultRejectSignature() public {
        SentinelVaultV29.Payment memory p = _payment(7);
        bytes memory sig = _sign(p, ALICE_KEY);
        vm.chainId(1);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, sig);
        vm.chainId(1990);

        SentinelVaultV29 separate = new SentinelVaultV29(address(token), alice, executor, 250_000, 400_000);
        token.mint(address(separate), 1_000_000);
        vm.prank(alice);
        separate.setRecipient(recipient, true);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        separate.execute(p, sig);
        _assertUnspent(7);
    }

    function testV29NonceCancellationStillWorks() public {
        SentinelVaultV29.Payment memory p = _payment(8);
        bytes memory sig = _sign(p, ALICE_KEY);
        vm.prank(alice);
        vault.invalidateNonces(0, uint256(1) << 8);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.NonceAlreadyUsed.selector, uint256(8)));
        vm.prank(executor);
        vault.execute(p, sig);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testV29EpochDigestDomainSeparatedFromLegacyVault() public {
        SentinelVaultV29.Payment memory p = _payment(9);
        assertEq(
            vault.PAYMENT_TYPEHASH(),
            keccak256("Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor,uint256 ownerEpoch,uint256 executorEpoch)")
        );
        assertTrue(vault.paymentDigest(p) != bytes32(0));
        assertGt(vault.ownerEpoch(), 0);
        assertGt(vault.executorEpoch(), 0);
    }
}
