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
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal executorAlice = address(0xE01);
    address internal executorBob = address(0xE02);
    address internal beneficiary = address(0xABCD);

    function setUp() public {
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
        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, address(factory)
        ));
        vault.setRecipient(beneficiary, true);

        token.mint(address(vault), 300000);
        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, address(factory)
        ));
        vault.pause();
        assertEq(vault.balance(), 300000);
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
