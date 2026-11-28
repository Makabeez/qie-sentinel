// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVaultV33} from "../../src/legacy/SentinelVaultV33.sol";
import {MockV34AdversarialWallet} from "../mocks/MockV34AdversarialWallet.sol";
import {MockQUSDC} from "../mocks/MockQUSDC.sol";

/// @notice Local-only red-team tests: V33 cannot guarantee monotonicity for dishonest wallets.
/// @dev Passing "reactivation" tests DOCUMENT a release blocker, NOT security of arbitrary wallets.
contract SentinelV34WalletCompatibilityTest is Test {
    uint256 private constant KEY_A = 0xA11CE;
    uint256 private constant KEY_B = 0xB0B;
    address private executor = address(0xE01);
    address private recipient = address(0xCAFE);
    address private outsider = address(0xBAD);
    MockQUSDC private stable;
    MockV34AdversarialWallet private wallet;
    SentinelVaultV33 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        stable = new MockQUSDC();
        wallet = new MockV34AdversarialWallet(address(this),vm.addr(KEY_A));
        vault = new SentinelVaultV33(address(stable),address(wallet),executor,250_000,400_000);
        wallet.configureRecipient(vault,recipient,true);
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

    function _assertNoTransfer(uint256 nonce) private view {
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(stable.balanceOf(address(vault)),1_000_000);
        assertEq(stable.balanceOf(recipient),0);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    /// @notice An actively dishonest wallet can freeze its reported epoch;
    /// old signer signatures DO reactivate and must be kept off allowlists.
    function testV34FrozenEpochRevivesPriorSignature_RiskConfirmed() public {
        SentinelVaultV33.Payment memory p=_intent(31);
        bytes memory oldSig=_sign(p,KEY_A);
        wallet.setFreezeEpoch(true);
        wallet.changeSigner(vm.addr(KEY_B));

        vm.expectRevert(SentinelVaultV33.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,oldSig);
        _assertNoTransfer(31);

        wallet.changeSigner(vm.addr(KEY_A));
        assertEq(vault.signerEpoch(),p.signerEpoch);
        // The exploitability condition is observable under an untrustworthy owner wallet.
        vm.prank(executor);
        vault.execute(p,oldSig);
        assertEq(stable.balanceOf(recipient),100_000);
        assertTrue(vault.isNonceUsed(31));
    }

    function testV34UnresponsiveEpochRejectsBeforeSignatureAndDoesNotBurnNonce() public {
        SentinelVaultV33.Payment memory p=_intent(32);
        bytes memory sig=_sign(p,KEY_A);
        wallet.setRevertEpoch(true);
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV33.UnsupportedContractOwner.selector,address(wallet)
        ));
        vm.prank(executor);
        vault.execute(p,sig);
        _assertNoTransfer(32);
    }

    function testV34RevertingERC1271FailsClosedWithoutStateChanges() public {
        SentinelVaultV33.Payment memory p=_intent(33);
        bytes memory sig=_sign(p,KEY_A);
        wallet.setRevertSignature(true);
        vm.expectRevert(SentinelVaultV33.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        _assertNoTransfer(33);
    }

    function testV34InvalidERC1271ReturnFailsClosed() public {
        SentinelVaultV33.Payment memory p=_intent(34);
        bytes memory sig=_sign(p,KEY_A);
        wallet.setForceInvalidSignature(true);
        vm.expectRevert(SentinelVaultV33.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        _assertNoTransfer(34);
    }

    function testV34ExplicitNonceCancellationBlocksDishonestWalletReplay() public {
        SentinelVaultV33.Payment memory p=_intent(35);
        bytes memory sig=_sign(p,KEY_A);
        wallet.invalidate(vault,0,uint256(1)<<35);
        wallet.setFreezeEpoch(true);
        wallet.changeSigner(vm.addr(KEY_B));
        wallet.changeSigner(vm.addr(KEY_A));
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV33.NonceAlreadyUsed.selector,uint256(35)
        ));
        vm.prank(executor);
        vault.execute(p,sig);
        assertTrue(vault.isNonceUsed(35));
        assertEq(stable.balanceOf(recipient),0);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV34PausedOwnerCanRecoverEvenIfERC1271EpochBroken() public {
        wallet.setRevertEpoch(true);
        wallet.pauseVault(vault);
        wallet.recover(vault,outsider,100_000);
        assertEq(stable.balanceOf(outsider),100_000);
        assertEq(stable.balanceOf(address(vault)),900_000);
        assertEq(vault.guard().spentByDay(block.timestamp/1 days),0);
    }

    function testV34ControllerRestrictionOnWalletMutators() public {
        vm.startPrank(outsider);
        vm.expectRevert(MockV34AdversarialWallet.UnauthorizedController.selector);
        wallet.setFreezeEpoch(true);
        vm.expectRevert(MockV34AdversarialWallet.UnauthorizedController.selector);
        wallet.changeSigner(outsider);
        vm.expectRevert(MockV34AdversarialWallet.UnauthorizedController.selector);
        wallet.pauseVault(vault);
        vm.stopPrank();
        assertEq(wallet.authorizedSigner(),vm.addr(KEY_A));
        assertFalse(wallet.freezeEpoch());
    }

    function testV34HonestEpochAdvancesAndPreventsReactivation() public {
        SentinelVaultV33.Payment memory p=_intent(36);
        bytes memory sig=_sign(p,KEY_A);
        wallet.changeSigner(vm.addr(KEY_B));
        wallet.changeSigner(vm.addr(KEY_A));
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV33.StaleSignerEpoch.selector,p.signerEpoch,p.signerEpoch+2
        ));
        vm.prank(executor);
        vault.execute(p,sig);
        _assertNoTransfer(36);
    }
}
