// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultFactory} from "../src/SentinelVaultFactory.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {PolicyGuard} from "../src/PolicyGuard.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SentinelVaultFactoryTest is Test {
    MockQUSDC internal token;
    SentinelVaultFactory internal factory;
    uint256 internal constant ALICE_KEY = 0xA11CE;
    uint256 internal constant BOB_KEY = 0xB0B;
    address internal alice;
    address internal bob;
    address internal executorAlice = address(0xE01);
    address internal executorBob = address(0xE02);
    address internal beneficiary = address(0xABCD);

    function setUp() public {
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        token = new MockQUSDC();
        factory = new SentinelVaultFactory(address(token));
    }

    function testUsersOwnSeparateVaultsAndGuards() public {
        vm.prank(alice);
        address first = factory.createVault(executorAlice, 1e6, 5e6);
        vm.prank(bob);
        address second = factory.createVault(executorBob, 2e6, 8e6);

        assertTrue(first != second);
        SentinelVault a = SentinelVault(first);
        SentinelVault b = SentinelVault(second);
        assertEq(a.owner(), alice);
        assertEq(b.owner(), bob);
        assertEq(a.executor(), executorAlice);
        assertEq(b.executor(), executorBob);
        assertEq(address(a.token()), address(token));
        assertEq(address(b.token()), address(token));
        assertEq(a.guard().vault(), first);
        assertEq(b.guard().vault(), second);
        assertTrue(address(a.guard()) != address(b.guard()));
        assertEq(a.guard().maxPerTransfer(), 1e6);
        assertEq(b.guard().maxPerTransfer(), 2e6);
        assertEq(factory.deployedCount(alice), 1);
        assertEq(factory.deployedCount(bob), 1);
        assertEq(factory.getDeployedVaults(alice)[0], first);
        assertEq(factory.getDeployedVaults(bob)[0], second);
        assertEq(a.balance(), 0);
        assertEq(b.balance(), 0);
    }

    function testUnrelatedUserCannotChangeOtherUsersPolicies() public {
        vm.prank(alice);
        SentinelVault vault = SentinelVault(factory.createVault(executorAlice, 1e6, 5e6));
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vault.setRecipient(beneficiary, true);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vault.setLimits(1, 1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vault.setExecutor(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        vault.pause();
        vm.stopPrank();
        assertFalse(vault.guard().allowedRecipients(beneficiary));
        assertEq(vault.owner(), alice);
    }

    function testFactoryCannotConfigureOrRecoverUsersFunds() public {
        vm.prank(alice);
        SentinelVault vault = SentinelVault(factory.createVault(executorAlice, 1e6, 5e6));
        vm.expectRevert(abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, address(factory)
        ));
        vm.prank(address(factory));
        vault.setRecipient(beneficiary, true);

        token.mint(address(vault), 300000);
        vm.expectRevert(abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, address(factory)
        ));
        vm.prank(address(factory));
        vault.pause();
        assertEq(vault.balance(), 300000);
    }

    function testCrossUserCannotSignForAnotherOwnersVault() public {
        vm.prank(alice);
        SentinelVault a = SentinelVault(factory.createVault(executorAlice, 1e6, 5e6));
        vm.prank(bob);
        SentinelVault b = SentinelVault(factory.createVault(executorBob, 1e6, 5e6));

        vm.prank(alice);
        a.setRecipient(beneficiary, true);
        vm.prank(bob);
        b.setRecipient(beneficiary, true);
        token.mint(address(a), 2e6);
        token.mint(address(b), 2e6);

        SentinelVault.Payment memory payment = SentinelVault.Payment({
            token: address(token),
            recipient: beneficiary,
            amount: 300000,
            nonce: 12,
            deadline: block.timestamp + 1 hours,
            executor: executorAlice
        });

        // Bob's valid EOA signature must not be accepted in Alice's vault.
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(BOB_KEY, a.paymentDigest(payment));
        bytes memory wrongOwnerSig = abi.encodePacked(r, ss, v);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executorAlice);
        a.execute(payment, wrongOwnerSig);
        assertFalse(a.isNonceUsed(12));
        assertEq(a.balance(), 2e6);

        // Alice signs the same precise intent for Alice's vault.
        (v, r, ss) = vm.sign(ALICE_KEY, a.paymentDigest(payment));
        bytes memory ownerSig = abi.encodePacked(r, ss, v);
        vm.prank(executorAlice);
        a.execute(payment, ownerSig);
        assertEq(a.balance(), 1700000);
        assertTrue(a.isNonceUsed(12));
        assertEq(b.balance(), 2e6);
        assertFalse(b.isNonceUsed(12));

        // Alice's valid signature for her own vault cannot be replayed in Bob's
        // vault, even if the executor field is changed and the request is
        // submitted by Bob's correctly configured executor.
        payment.executor = executorBob;
        (v, r, ss) = vm.sign(ALICE_KEY, a.paymentDigest(payment));
        bytes memory wrongVaultSig = abi.encodePacked(r, ss, v);
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executorBob);
        b.execute(payment, wrongVaultSig);
        assertEq(b.balance(), 2e6);
        assertFalse(b.isNonceUsed(12));
    }

    function testNoAllowlistByDefault() public {
        vm.prank(alice);
        SentinelVault vault = SentinelVault(factory.createVault(executorAlice, 1e6, 5e6));
        PolicyGuard guard = vault.guard();
        assertFalse(guard.allowedRecipients(beneficiary));
        vm.expectRevert(abi.encodeWithSelector(PolicyGuard.RecipientNotAllowed.selector, beneficiary));
        guard.validate(beneficiary, 100000);
    }

    function testInvalidInputFailsWithoutDeploying() public {
        vm.expectRevert(SentinelVaultFactory.InvalidToken.selector);
        new SentinelVaultFactory(address(0));
        vm.expectRevert(SentinelVaultFactory.InvalidToken.selector);
        new SentinelVaultFactory(address(0xC0DE));

        vm.startPrank(alice);
        vm.expectRevert(SentinelVaultFactory.InvalidExecutor.selector);
        factory.createVault(address(0), 1e6, 5e6);
        vm.expectRevert(SentinelVaultFactory.ExecutorMustDifferFromOwner.selector);
        factory.createVault(alice, 1e6, 5e6);
        vm.expectRevert(PolicyGuard.InvalidLimit.selector);
        factory.createVault(executorAlice, 2e6, 1e6);
        assertEq(factory.deployedCount(alice), 0);
        vm.stopPrank();
    }

    function testFuzzUserOwnsCreatedVault(address user, address executor) public {
        vm.assume(user != address(0) && executor != address(0) && user != executor);
        vm.prank(user);
        address deployed = factory.createVault(executor, 1, 2);
        assertEq(SentinelVault(deployed).owner(), user);
        assertEq(SentinelVault(deployed).executor(), executor);
    }

    function testOwnerCanRotateAndTransferOwnershipWithoutFactory() public {
        vm.prank(alice);
        SentinelVault vault = SentinelVault(factory.createVault(executorAlice, 1e6, 5e6));
        vm.prank(alice);
        vault.transferOwnership(bob);
        assertEq(vault.owner(), alice);
        vm.prank(bob);
        vault.acceptOwnership();
        assertEq(vault.owner(), bob);
        // Factory history records creator, not current owner.
        assertEq(factory.deployedCount(alice), 1);
        assertEq(factory.deployedCount(bob), 0);
    }
}
