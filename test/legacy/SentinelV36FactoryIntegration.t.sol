// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelEpochFactoryV36} from "../../src/legacy/SentinelEpochFactoryV36.sol";
import {SentinelVaultV35} from "../../src/SentinelVaultV35.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";

/// @notice Audit-candidate factory integration; disposable EOA keys, mock tokens, local VM.
contract SentinelV36FactoryIntegrationTest is Test {
    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant BOB_KEY = 0xB0B;
    address private alice;
    address private bob;
    address private executorA = address(0xE01);
    address private executorB = address(0xE02);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;
    SentinelEpochFactoryV36 private factory;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        token = new MockQUSDC();
        factory = new SentinelEpochFactoryV36(address(token));
    }

    function _create(address creator,address exec) private returns (SentinelVaultV35 result) {
        vm.prank(creator);
        result = SentinelVaultV35(factory.createVault(exec,250_000,400_000));
    }

    function _payment(SentinelVaultV35 vault_,address exec,uint256 nonce)
        private view returns (SentinelVaultV35.Payment memory)
    {
        return SentinelVaultV35.Payment({
            token:address(token),recipient:recipient,amount:100_000,nonce:nonce,
            deadline:block.timestamp+3600,executor:exec,ownerEpoch:vault_.ownerEpoch(),
            executorEpoch:vault_.executorEpoch(),signerEpoch:vault_.signerEpoch()
        });
    }

    function _sign(SentinelVaultV35 vault_,SentinelVaultV35.Payment memory p,uint256 key)
        private returns (bytes memory)
    {
        (uint8 v,bytes32 r,bytes32 s)=vm.sign(key,vault_.paymentDigest(p));
        return abi.encodePacked(r,s,v);
    }

    function testV36TwoIndependentOwnersReceiveV35AndSeparateGuards() public {
        SentinelVaultV35 a=_create(alice,executorA);
        SentinelVaultV35 b=_create(bob,executorB);
        assertTrue(address(a)!=address(b));
        assertTrue(address(a.guard())!=address(b.guard()));
        assertEq(a.owner(),alice);
        assertEq(b.owner(),bob);
        assertEq(a.executor(),executorA);
        assertEq(b.executor(),executorB);
        assertEq(a.guard().vault(),address(a));
        assertEq(b.guard().vault(),address(b));
        assertFalse(a.guard().allowedRecipients(recipient));
        assertFalse(b.guard().allowedRecipients(recipient));
        assertEq(factory.deployedCount(alice),1);
        assertEq(factory.deployedCount(bob),1);
        assertEq(factory.getDeployedVaults(alice)[0],address(a));
    }

    function testV36IndependentOwnerPaymentAndCrossVaultReplay() public {
        SentinelVaultV35 a=_create(alice,executorA);
        SentinelVaultV35 b=_create(bob,executorA);
        vm.prank(alice);
        a.setRecipient(recipient,true);
        vm.prank(bob);
        b.setRecipient(recipient,true);
        token.mint(address(a),1_000_000);
        token.mint(address(b),1_000_000);
        SentinelVaultV35.Payment memory p=_payment(a,executorA,1);
        bytes memory sig=_sign(a,p,ALICE_KEY);
        vm.expectRevert(SentinelVaultV35.InvalidSignature.selector);
        vm.prank(executorA);
        b.execute(p,sig);
        vm.prank(executorA);
        a.execute(p,sig);
        assertEq(token.balanceOf(recipient),100_000);
        assertEq(token.balanceOf(address(a)),900_000);
        assertEq(token.balanceOf(address(b)),1_000_000);
        assertTrue(a.isNonceUsed(1));
        assertFalse(b.isNonceUsed(1));
    }

    function testV36PortfolioRehearsal() public {
        SentinelVaultV35 vault = _create(alice, executorA);
        assertEq(vault.owner(), alice);
        assertEq(vault.executor(), executorA);

        token.mint(address(vault), 1_000_000);
        vm.prank(alice);
        vault.setRecipient(recipient, true);

        SentinelVaultV35.Payment memory payment = _payment(vault, executorA, 7);
        bytes memory signature = _sign(vault, payment, ALICE_KEY);
        vm.prank(executorA);
        vault.execute(payment, signature);
        assertEq(token.balanceOf(recipient), 100_000);
        assertEq(vault.balance(), 900_000);
        assertTrue(vault.isNonceUsed(7));

        payment.nonce = 8;
        signature = _sign(vault, payment, ALICE_KEY);
        vm.prank(alice);
        vault.invalidateNonces(0, 1 << 8);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.NonceAlreadyUsed.selector, 8));
        vm.prank(executorA);
        vault.execute(payment, signature);
        assertEq(token.balanceOf(recipient), 100_000);
        assertEq(vault.balance(), 900_000);

        vm.startPrank(alice);
        vault.pause();
        vault.emergencyRecover(alice, 900_000);
        vm.stopPrank();
        assertTrue(vault.paused());
        assertEq(vault.balance(), 0);
        assertEq(token.balanceOf(alice), 900_000);
    }

    function testV36CannotCreateWithZeroSameExecutorOrInvalidLimits() public {
        vm.startPrank(alice);
        vm.expectRevert(SentinelEpochFactoryV36.InvalidExecutor.selector);
        factory.createVault(address(0),1,2);
        vm.expectRevert(SentinelEpochFactoryV36.ExecutorMustDifferFromOwner.selector);
        factory.createVault(alice,1,2);
        vm.expectRevert();
        factory.createVault(executorA,300,200);
        assertEq(factory.deployedCount(alice),0);
        vm.stopPrank();
    }

    function testV36FactoryCannotControlOrRecoverOwnersVault() public {
        SentinelVaultV35 a=_create(alice,executorA);
        vm.expectRevert();
        vm.prank(address(factory));
        a.setRecipient(recipient,true);
        vm.expectRevert();
        vm.prank(address(factory));
        a.pause();
        assertEq(a.owner(),alice);
    }

    function testV36HistoricalCreatorRegistryNotOwnerPortfolio() public {
        SentinelVaultV35 a=_create(alice,executorA);
        vm.prank(alice);
        a.transferOwnership(bob);
        vm.prank(bob);
        a.acceptOwnership();
        assertEq(a.owner(),bob);
        assertEq(factory.deployedCount(alice),1);
        assertEq(factory.deployedCount(bob),0);
    }

    function testV36OwnerExecutorSeparationSurvivesFactoryCreation() public {
        SentinelVaultV35 a=_create(alice,executorA);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.OwnerExecutorConflict.selector,alice));
        vm.prank(alice);
        a.setExecutor(alice);
        vm.prank(alice);
        a.transferOwnership(executorA);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.OwnerExecutorConflict.selector,executorA));
        vm.prank(executorA);
        a.acceptOwnership();
        assertEq(a.owner(),alice);
    }
}
