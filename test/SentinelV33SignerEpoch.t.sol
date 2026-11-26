// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV33} from "../src/SentinelVaultV33.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {MockV33EpochWallet} from "./mocks/MockV33EpochWallet.sol";
import {MockV32ContractOwner} from "./mocks/MockV32ContractOwner.sol";

/// @notice Disposable local EVM proof for compatible contract-wallet signer epochs.
contract SentinelV33SignerEpochTest is Test {
    uint256 private constant KEY_A = 0xA11CE;
    uint256 private constant KEY_B = 0xB0B;
    address private executor = address(0xE01);
    address private recipient = address(0xCAFE);
    MockQUSDC private stable;
    MockV33EpochWallet private wallet;
    SentinelVaultV33 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        stable = new MockQUSDC();
        wallet = new MockV33EpochWallet(address(this),vm.addr(KEY_A));
        vault = new SentinelVaultV33(address(stable),address(wallet),executor,250_000,400_000);
        wallet.setRecipient(vault,recipient,true);
        stable.mint(address(vault),1_000_000);
    }

    function _intent(uint256 nonce) private view returns (SentinelVaultV33.Payment memory) {
        return SentinelVaultV33.Payment({
            token:address(stable),recipient:recipient,amount:100_000,nonce:nonce,
            deadline:block.timestamp+3600,executor:executor,
            ownerEpoch:vault.ownerEpoch(),executorEpoch:vault.executorEpoch(),
            signerEpoch:vault.signerEpoch()
        });
    }
    function _sign(SentinelVaultV33.Payment memory p,uint256 key) private returns(bytes memory) {
        (uint8 v,bytes32 r,bytes32 s)=vm.sign(key,vault.paymentDigest(p));
        return abi.encodePacked(r,s,v);
    }
    function _unchanged(uint256 nonce) private view {
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(stable.balanceOf(address(vault)),1_000_000);
        assertEq(stable.balanceOf(recipient),0);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV33ValidCurrentWalletEpochExecutes() public {
        SentinelVaultV33.Payment memory p=_intent(1);
        bytes memory sig=_sign(p,KEY_A);
        vm.prank(executor);
        vault.execute(p,sig);
        assertEq(stable.balanceOf(recipient),100_000);
        assertTrue(vault.isNonceUsed(1));
    }

    function testV33SignerReturnNeverRevivesOldUnspentSignature() public {
        SentinelVaultV33.Payment memory p=_intent(2);
        bytes memory sig=_sign(p,KEY_A);
        uint256 old=p.signerEpoch;
        wallet.changeSigner(vm.addr(KEY_B));
        wallet.changeSigner(vm.addr(KEY_A));
        assertEq(wallet.signerEpoch(),old+2);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV33.StaleSignerEpoch.selector,old,old+2));
        vm.prank(executor);
        vault.execute(p,sig);
        _unchanged(2);
        SentinelVaultV33.Payment memory current=_intent(3);
        bytes memory freshSig=_sign(current,KEY_A);
        vm.prank(executor);
        vault.execute(current,freshSig);
        assertEq(stable.balanceOf(recipient),100_000);
    }

    function testV33PatchingSignerEpochWithoutResigningIsInvalid() public {
        SentinelVaultV33.Payment memory p=_intent(4);
        bytes memory sig=_sign(p,KEY_A);
        wallet.changeSigner(vm.addr(KEY_B));
        wallet.changeSigner(vm.addr(KEY_A));
        p.signerEpoch=vault.signerEpoch();
        vm.expectRevert(SentinelVaultV33.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        _unchanged(4);
    }

    function testV33WrongSignerRejectedWithoutBurningNonce() public {
        SentinelVaultV33.Payment memory p=_intent(5);
        bytes memory badSig=_sign(p,KEY_B);
        vm.expectRevert(SentinelVaultV33.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,badSig);
        _unchanged(5);
    }

    function testV33UnsupportedERC1271OwnerFailsClosed() public {
        MockV32ContractOwner oldWallet=new MockV32ContractOwner(address(this),vm.addr(KEY_A));
        SentinelVaultV33 unsupported=new SentinelVaultV33(address(stable),address(oldWallet),executor,250_000,400_000);
        SentinelVaultV33.Payment memory p=_intent(6);
        p.ownerEpoch=unsupported.ownerEpoch();
        p.executorEpoch=unsupported.executorEpoch();
        p.signerEpoch=0;
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV33.UnsupportedContractOwner.selector,address(oldWallet)));
        vm.prank(executor);
        unsupported.execute(p,hex"");
    }

    function testV33EoaOwnerUsesZeroSignerEpoch() public {
        address alice=vm.addr(KEY_A);
        SentinelVaultV33 eoa=new SentinelVaultV33(address(stable),alice,executor,250_000,400_000);
        assertEq(eoa.signerEpoch(),0);
        assertEq(vault.signerEpoch(),1);
    }

    function testV33ExecutorResetAlsoRejectsOldWalletIntent() public {
        SentinelVaultV33.Payment memory p=_intent(7);
        bytes memory sig=_sign(p,KEY_A);
        wallet.setExecutor(vault,executor);
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV33.StaleExecutorEpoch.selector,p.executorEpoch,p.executorEpoch+1
        ));
        vm.prank(executor);
        vault.execute(p,sig);
        _unchanged(7);
    }

    function testV33CancelledNonceRemainsCancelledAfterSignerRestoration() public {
        SentinelVaultV33.Payment memory p=_intent(8);
        wallet.invalidateNonces(vault,0,uint256(1)<<8);
        wallet.changeSigner(vm.addr(KEY_B));
        wallet.changeSigner(vm.addr(KEY_A));
        SentinelVaultV33.Payment memory nowCurrent=_intent(8);
        bytes memory newSig=_sign(nowCurrent,KEY_A);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV33.NonceAlreadyUsed.selector,uint256(8)));
        vm.prank(executor);
        vault.execute(nowCurrent,newSig);
        assertTrue(vault.isNonceUsed(8));
        assertEq(stable.balanceOf(recipient),0);
    }
}
