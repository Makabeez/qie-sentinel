// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SentinelVaultFactory} from "../src/SentinelVaultFactory.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {PolicyGuard} from "../src/PolicyGuard.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";

/// @notice Sentinel 2.7: self-contained authorization lifecycle using throwaway keys.
/// @dev All deployments, minting, signatures and transfers live ONLY inside a Foundry test EVM.
///      There is no RPC URL, production key, remote deployment or external asset.
contract SentinelV27LifecycleTest is Test {
    uint256 internal constant ALICE_KEY = 0xA11CE;
    uint256 internal constant BOB_KEY = 0xB0B;
    address internal alice;
    address internal bob;
    address internal executorAlice = address(0xE01);
    address internal executorBob = address(0xE02);
    address internal outsider = address(0xBAD);
    address internal recipient = address(0xCAFE);
    MockQUSDC internal token;
    SentinelVaultFactory internal factory;
    SentinelVault internal aliceVault;
    SentinelVault internal bobVault;

    function setUp() public {
        vm.chainId(1990); // local test VM identifies as QIE; no real QIE RPC.
        vm.warp(1_800_000_000);
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        token = new MockQUSDC();
        factory = new SentinelVaultFactory(address(token));

        vm.prank(alice);
        aliceVault = SentinelVault(factory.createVault(executorAlice, 250_000, 400_000));
        vm.prank(bob);
        bobVault = SentinelVault(factory.createVault(executorBob, 250_000, 400_000));

        vm.prank(alice);
        aliceVault.setRecipient(recipient, true);
        vm.prank(bob);
        bobVault.setRecipient(recipient, true);
        token.mint(address(aliceVault), 1_000_000);
        token.mint(address(bobVault), 1_000_000);
    }

    function _payment(SentinelVault vault, address executor, uint256 amount, uint256 nonce)
        internal view returns (SentinelVault.Payment memory)
    {
        return SentinelVault.Payment({
            token: address(token),
            recipient: recipient,
            amount: amount,
            nonce: nonce,
            deadline: block.timestamp + 3600,
            executor: executor
        });
    }

    function _sign(SentinelVault vault, SentinelVault.Payment memory p, uint256 key)
        internal returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r, s, v);
    }

    function _assertAliceUntouched(uint256 nonce) internal view {
        assertEq(token.balanceOf(address(aliceVault)), 1_000_000);
        assertEq(token.balanceOf(recipient), 0);
        assertFalse(aliceVault.isNonceUsed(nonce));
        assertEq(aliceVault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testV27IndependentUsersReceiveDistinctOwnershipAndGuards() public {
        assertEq(aliceVault.owner(), alice);
        assertEq(bobVault.owner(), bob);
        assertTrue(address(aliceVault) != address(bobVault));
        assertTrue(address(aliceVault.guard()) != address(bobVault.guard()));
        assertEq(aliceVault.guard().vault(), address(aliceVault));
        assertEq(bobVault.guard().vault(), address(bobVault));
        assertEq(aliceVault.guard().maxPerTransfer(), 250_000);
        assertEq(bobVault.guard().dailyLimit(), 400_000);
        assertEq(factory.deployedCount(alice), 1);
        assertEq(factory.deployedCount(bob), 1);
    }

    function testV27IndependentOwnerConsentAndExecutorPerformOnlyScopedTransfer() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 3);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        assertEq(token.balanceOf(address(aliceVault)), 900_000);
        assertEq(token.balanceOf(recipient), 100_000);
        assertEq(token.balanceOf(address(bobVault)), 1_000_000);
        assertTrue(aliceVault.isNonceUsed(3));
        assertFalse(bobVault.isNonceUsed(3));
    }

    function testV27AIAgentOrUnauthorizedCallerCannotSubmitSignedPayment() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 4);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, outsider));
        vm.prank(outsider);
        aliceVault.execute(p, sig);
        _assertAliceUntouched(4);
    }

    function testV27WrongOwnerSignatureRejectedWithNoStateChange() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 5);
        bytes memory sig = _sign(aliceVault, p, BOB_KEY);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        _assertAliceUntouched(5);
    }

    function testV27SignatureForAliceVaultCannotAuthorizeBobVault() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorBob, 100_000, 6);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executorBob);
        bobVault.execute(p, sig);
        assertEq(token.balanceOf(address(bobVault)), 1_000_000);
        assertFalse(bobVault.isNonceUsed(6));
    }

    function testV27OwnerRevocationPreventsExecutionOfPreviouslyValidSignature() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 7);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.prank(alice);
        aliceVault.invalidateNonces(0, uint256(1) << 7);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, uint256(7)));
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        assertEq(token.balanceOf(address(aliceVault)), 1_000_000);
        assertEq(token.balanceOf(recipient), 0);
    }

    function testV27OwnerPausesToBlockEvenCorrectlySignedIntent() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 8);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.prank(alice);
        aliceVault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        _assertAliceUntouched(8);
    }

    function testV27BudgetLimitBlocksAdditionalPaymentWithoutConsumingNonce() public {
        SentinelVault.Payment memory first = _payment(aliceVault, executorAlice, 250_000, 9);
        bytes memory firstSig = _sign(aliceVault, first, ALICE_KEY);
        vm.prank(executorAlice);
        aliceVault.execute(first, firstSig);

        SentinelVault.Payment memory second = _payment(aliceVault, executorAlice, 200_000, 10);
        bytes memory sig = _sign(aliceVault, second, ALICE_KEY);
        vm.expectRevert(
            abi.encodeWithSelector(PolicyGuard.DailyLimitExceeded.selector, uint256(200_000), uint256(150_000))
        );
        vm.prank(executorAlice);
        aliceVault.execute(second, sig);
        assertFalse(aliceVault.isNonceUsed(10));
        assertEq(token.balanceOf(address(aliceVault)), 750_000);
        assertEq(token.balanceOf(recipient), 250_000);
    }

    function testV27ExpiredIntentFailsWithNoNonceConsumption() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 11);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.warp(p.deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SentinelVault.ExpiredIntent.selector, p.deadline, p.deadline + 1)
        );
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        _assertAliceUntouched(11);
    }

    function testV27RotatingExecutorInvalidatesOldExecutorPermission() public {
        SentinelVault.Payment memory p = _payment(aliceVault, executorAlice, 100_000, 12);
        bytes memory sig = _sign(aliceVault, p, ALICE_KEY);
        vm.prank(alice);
        aliceVault.setExecutor(executorBob);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.UnauthorizedExecutor.selector, executorAlice));
        vm.prank(executorAlice);
        aliceVault.execute(p, sig);
        _assertAliceUntouched(12);
    }

    function testV27OutsiderCannotManageAnotherOwnerVault() public {
        vm.startPrank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        aliceVault.setLimits(1, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        aliceVault.invalidateNonces(0, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        aliceVault.setRecipient(outsider, true);
        vm.stopPrank();
        assertFalse(aliceVault.guard().allowedRecipients(outsider));
    }
}
