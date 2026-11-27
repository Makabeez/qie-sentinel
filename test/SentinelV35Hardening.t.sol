// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV35} from "../src/SentinelVaultV35.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {MockV35FeeToken} from "./mocks/MockV35FeeToken.sol";

/// @notice Experimental security hardening; all transactions local to Foundry.
contract SentinelV35HardeningTest is Test {
    uint256 private constant OWNER_KEY = 0xA11CE;
    address private owner;
    address private executor = address(0xE01);
    address private recipient = address(0xCAFE);
    MockQUSDC private token;
    SentinelVaultV35 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        owner = vm.addr(OWNER_KEY);
        token = new MockQUSDC();
        vault = new SentinelVaultV35(address(token),owner,executor,250_000,400_000);
        vm.prank(owner);
        vault.setRecipient(recipient,true);
        token.mint(address(vault),1_000_000);
    }

    function _intent(SentinelVaultV35 target,address tokenAddress,address destination,uint256 nonce)
        private view returns (SentinelVaultV35.Payment memory)
    {
        return SentinelVaultV35.Payment({
            token:tokenAddress,recipient:destination,amount:100_000,nonce:nonce,
            deadline:block.timestamp+3600,executor:target.executor(),
            ownerEpoch:target.ownerEpoch(),executorEpoch:target.executorEpoch(),
            signerEpoch:target.signerEpoch()
        });
    }

    function _sign(SentinelVaultV35 target,SentinelVaultV35.Payment memory payment)
        private returns (bytes memory)
    {
        (uint8 v,bytes32 r,bytes32 s)=vm.sign(OWNER_KEY,target.paymentDigest(payment));
        return abi.encodePacked(r,s,v);
    }

    function testV35OrdinaryTokenDeliversExactSignedAmount() public {
        SentinelVaultV35.Payment memory p=_intent(vault,address(token),recipient,1);
        bytes memory sig=_sign(vault,p);
        vm.prank(executor);
        vault.execute(p,sig);
        assertEq(token.balanceOf(address(vault)),900_000);
        assertEq(token.balanceOf(recipient),100_000);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),100_000);
        assertTrue(vault.isNonceUsed(1));
    }

    function testV35ConstructorRefusesOwnerExecutorEquality() public {
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.OwnerExecutorConflict.selector,owner));
        new SentinelVaultV35(address(token),owner,owner,250_000,400_000);
    }

    function testV35OwnerCannotBeSetAsExecutorAfterCreation() public {
        uint256 epoch=vault.executorEpoch();
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.OwnerExecutorConflict.selector,owner));
        vm.prank(owner);
        vault.setExecutor(owner);
        assertEq(vault.executor(),executor);
        assertEq(vault.executorEpoch(),epoch);
    }

    function testV35OwnershipCannotTransferToCurrentExecutor() public {
        uint256 epoch=vault.ownerEpoch();
        vm.prank(owner);
        vault.transferOwnership(executor);
        assertEq(vault.pendingOwner(),executor);
        // Ownable2Step permits nomination; acceptance must remain blocked.
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.OwnerExecutorConflict.selector,executor));
        vm.prank(executor);
        vault.acceptOwnership();
        assertEq(vault.owner(),owner);
        assertEq(vault.ownerEpoch(),epoch);
    }

    function testV35OwnershipTransferToIndependentThirdPartyWorks() public {
        address newOwner=address(0xB0B);
        vm.prank(owner);
        vault.transferOwnership(newOwner);
        vm.prank(newOwner);
        vault.acceptOwnership();
        assertEq(vault.owner(),newOwner);
        assertEq(vault.executor(),executor);
    }

    function testV35StandardNonzeroRecipientRequired() public {
        vm.prank(owner);
        vault.setRecipient(address(vault),true);
        SentinelVaultV35.Payment memory p=_intent(vault,address(token),address(vault),2);
        bytes memory sig=_sign(vault,p);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV35.InvalidRecipient.selector,address(vault)));
        vm.prank(executor);
        vault.execute(p,sig);
        assertFalse(vault.isNonceUsed(2));
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV35FeeTokenAtomicRollbackLeavesNonceAndBudgetUntouched() public {
        MockV35FeeToken feeToken=new MockV35FeeToken();
        SentinelVaultV35 feeVault=new SentinelVaultV35(address(feeToken),owner,executor,250_000,400_000);
        vm.prank(owner);
        feeVault.setRecipient(recipient,true);
        feeToken.mint(address(feeVault),1_000_000);
        SentinelVaultV35.Payment memory p=_intent(feeVault,address(feeToken),recipient,8);
        bytes memory sig=_sign(feeVault,p);
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV35.UnexpectedTransferAmount.selector,uint256(100_000),uint256(100_000),uint256(90_000)
        ));
        vm.prank(executor);
        feeVault.execute(p,sig);
        assertEq(feeToken.balanceOf(address(feeVault)),1_000_000);
        assertEq(feeToken.balanceOf(recipient),0);
        assertFalse(feeVault.isNonceUsed(8));
        assertEq(feeVault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV35OwnerRecoveryRemainsPrivilegedAndRequiresPause() public {
        vm.expectRevert();
        vm.prank(owner);
        vault.emergencyRecover(owner,100_000);
        vm.prank(owner);
        vault.pause();
        vm.prank(owner);
        vault.emergencyRecover(owner,100_000);
        assertEq(token.balanceOf(owner),100_000);
        assertEq(token.balanceOf(address(vault)),900_000);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV35UnauthorisedRecoveryCannotTransferFunds() public {
        vm.prank(owner);
        vault.pause();
        vm.expectRevert();
        vm.prank(address(0xBAD));
        vault.emergencyRecover(address(0xBAD),100_000);
        assertEq(token.balanceOf(address(vault)),1_000_000);
    }
}
