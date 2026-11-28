// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SentinelEpochFactoryV30} from "../../src/legacy/SentinelEpochFactoryV30.sol";
import {SentinelVaultV29} from "../../src/legacy/SentinelVaultV29.sol";
import {PolicyGuard} from "../../src/PolicyGuard.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";

/// @notice Sentinel 3.0 factory isolation and authorization tests.
/// @dev Entirely ephemeral local EVM; no deployments, RPC or real assets.
contract SentinelV30FactoryTest is Test {
    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant BOB_KEY = 0xB0B;
    address private alice;
    address private bob;
    address private executorAlice = address(0xE01);
    address private executorBob = address(0xE02);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;
    SentinelEpochFactoryV30 private factory;

    function setUp() public {
        vm.chainId(1990); // only local Foundry EVM
        vm.warp(1_800_000_000);
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        token = new MockQUSDC();
        factory = new SentinelEpochFactoryV30(address(token));
    }

    function _create(address creator, address executor) private returns (SentinelVaultV29 result) {
        vm.prank(creator);
        result = SentinelVaultV29(factory.createVault(executor, 250_000, 400_000));
    }

    function _payment(SentinelVaultV29 vault, address executor, uint256 nonce)
        private view returns (SentinelVaultV29.Payment memory)
    {
        return SentinelVaultV29.Payment({
            token: address(token), recipient: recipient, amount: 100_000,
            nonce: nonce, deadline: block.timestamp + 3600, executor: executor,
            ownerEpoch: vault.ownerEpoch(), executorEpoch: vault.executorEpoch()
        });
    }

    function _sign(SentinelVaultV29 vault, SentinelVaultV29.Payment memory payment, uint256 key)
        private returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(payment));
        return abi.encodePacked(r,s,v);
    }

    function testV30TwoOwnersHaveIndependentVaultsGuardsAndEmptyAllowlist() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        SentinelVaultV29 b = _create(bob, executorBob);
        assertTrue(address(a) != address(b));
        assertTrue(address(a.guard()) != address(b.guard()));
        assertEq(a.owner(), alice);
        assertEq(b.owner(), bob);
        assertEq(a.executor(), executorAlice);
        assertEq(b.executor(), executorBob);
        assertEq(a.guard().vault(), address(a));
        assertEq(b.guard().vault(), address(b));
        assertEq(address(a.token()), address(token));
        assertEq(address(b.token()), address(token));
        assertFalse(a.guard().allowedRecipients(recipient));
        assertFalse(b.guard().allowedRecipients(recipient));
        assertEq(a.balance(), 0);
        assertEq(b.balance(), 0);
        assertEq(factory.deployedCount(alice), 1);
        assertEq(factory.deployedCount(bob), 1);
    }

    function testV30FactoryCannotControlOrRecoverOwnerVault() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(factory)));
        vm.prank(address(factory));
        a.setRecipient(recipient, true);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(factory)));
        vm.prank(address(factory));
        a.pause();

        token.mint(address(a), 500_000);
        vm.prank(alice);
        a.pause();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(factory)));
        vm.prank(address(factory));
        a.emergencyRecover(address(factory), 500_000);
        assertEq(token.balanceOf(address(a)), 500_000);
    }

    function testV30OnlySignedScopedPaymentMovesMockFunds() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        SentinelVaultV29 b = _create(bob, executorBob);
        vm.prank(alice);
        a.setRecipient(recipient, true);
        vm.prank(bob);
        b.setRecipient(recipient, true);
        token.mint(address(a), 1_000_000);
        token.mint(address(b), 1_000_000);
        SentinelVaultV29.Payment memory p = _payment(a, executorAlice, 10);
        bytes memory sig = _sign(a, p, ALICE_KEY);
        vm.prank(executorAlice);
        a.execute(p, sig);
        assertEq(token.balanceOf(recipient), 100_000);
        assertEq(token.balanceOf(address(a)), 900_000);
        assertEq(token.balanceOf(address(b)), 1_000_000);
        assertTrue(a.isNonceUsed(10));
        assertFalse(b.isNonceUsed(10));
    }

    function testV30WrongSignerAndCrossVaultReplayRejected() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        SentinelVaultV29 b = _create(bob, executorBob);
        vm.prank(alice);
        a.setRecipient(recipient, true);
        vm.prank(bob);
        b.setRecipient(recipient, true);
        token.mint(address(a), 1_000_000);
        token.mint(address(b), 1_000_000);
        SentinelVaultV29.Payment memory p = _payment(a, executorAlice, 11);
        bytes memory wrong = _sign(a, p, BOB_KEY);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executorAlice);
        a.execute(p, wrong);
        // Same executor for a different vault, with Alice's valid signature:
        // even with matching payment fields, domain binds the address.
        vm.prank(bob);
        b.setExecutor(executorAlice);
        p.executorEpoch = b.executorEpoch();
        bytes memory aliceSig = _sign(a, p, ALICE_KEY);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executorAlice);
        b.execute(p, aliceSig);
        assertEq(token.balanceOf(address(a)), 1_000_000);
        assertEq(token.balanceOf(address(b)), 1_000_000);
        assertEq(token.balanceOf(recipient), 0);
        assertFalse(a.isNonceUsed(11));
        assertFalse(b.isNonceUsed(11));
    }

    function testV30RestoringOwnerDoesNotReviveOldSignature() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        vm.prank(alice);
        a.setRecipient(recipient, true);
        token.mint(address(a), 1_000_000);
        SentinelVaultV29.Payment memory p = _payment(a, executorAlice, 12);
        bytes memory sig = _sign(a, p, ALICE_KEY);
        vm.prank(alice);
        a.transferOwnership(bob);
        vm.prank(bob);
        a.acceptOwnership();
        vm.prank(bob);
        a.transferOwnership(alice);
        vm.prank(alice);
        a.acceptOwnership();
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.StaleOwnerEpoch.selector, p.ownerEpoch, a.ownerEpoch()));
        vm.prank(executorAlice);
        a.execute(p, sig);
        assertEq(token.balanceOf(address(a)), 1_000_000);
        assertFalse(a.isNonceUsed(12));
    }

    function testV30RestoringExecutorDoesNotReviveOldSignature() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        vm.prank(alice);
        a.setRecipient(recipient, true);
        token.mint(address(a), 1_000_000);
        SentinelVaultV29.Payment memory p = _payment(a, executorAlice, 13);
        bytes memory sig = _sign(a, p, ALICE_KEY);
        vm.prank(alice);
        a.setExecutor(executorBob);
        vm.prank(alice);
        a.setExecutor(executorAlice);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.StaleExecutorEpoch.selector, p.executorEpoch, a.executorEpoch()));
        vm.prank(executorAlice);
        a.execute(p, sig);
        assertEq(token.balanceOf(address(a)), 1_000_000);
        assertFalse(a.isNonceUsed(13));
    }

    function testV30InvalidSetupRevertsWithoutRegistryEntry() public {
        vm.expectRevert(SentinelEpochFactoryV30.InvalidToken.selector);
        new SentinelEpochFactoryV30(address(0));
        vm.expectRevert(SentinelEpochFactoryV30.InvalidToken.selector);
        new SentinelEpochFactoryV30(address(0xBEEF));

        vm.startPrank(alice);
        vm.expectRevert(SentinelEpochFactoryV30.InvalidExecutor.selector);
        factory.createVault(address(0), 100, 200);
        vm.expectRevert(SentinelEpochFactoryV30.ExecutorMustDifferFromOwner.selector);
        factory.createVault(alice, 100, 200);
        vm.expectRevert(PolicyGuard.InvalidLimit.selector);
        factory.createVault(executorAlice, 300, 200);
        assertEq(factory.deployedCount(alice), 0);
        vm.stopPrank();
    }

    function testV30CreatorHistoryDoesNotRepresentCurrentOwner() public {
        SentinelVaultV29 a = _create(alice, executorAlice);
        vm.prank(alice);
        a.transferOwnership(bob);
        vm.prank(bob);
        a.acceptOwnership();
        assertEq(a.owner(), bob);
        assertEq(factory.deployedCount(alice), 1);
        assertEq(factory.deployedCount(bob), 0);
        assertEq(factory.getDeployedVaults(alice)[0], address(a));
    }
}
