// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {MockRevocable1271Owner} from "./mocks/MockRevocable1271Owner.sol";

/// @notice QIE Sentinel v2.5: purely local, disposable-signature security lab.
///         No production private keys, no QIE Mainnet broadcasts.
contract SentinelSignatureLabTest is Test {
    uint256 private constant SIGNER_KEY = 0xA11CE;
    uint256 private constant WRONG_KEY = 0xB0B;
    address private controller = address(this);
    address private signer;
    address private executor = address(0xE01);
    address private beneficiary = address(0xBEEF);
    address private outsider = address(0xBAD);
    MockQUSDC private token;
    MockRevocable1271Owner private wallet;
    SentinelVault private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        signer = vm.addr(SIGNER_KEY);
        token = new MockQUSDC();
        wallet = new MockRevocable1271Owner(controller, signer);
        vault = new SentinelVault(address(token), address(wallet), executor, 1e6, 5e6);
        token.mint(address(vault), 2e6);
        wallet.setRecipient(vault, beneficiary, true);
    }

    function _payment(uint256 nonce) private view returns (SentinelVault.Payment memory) {
        return SentinelVault.Payment({
            token: address(token),
            recipient: beneficiary,
            amount: 100_000,
            nonce: nonce,
            deadline: block.timestamp + 3600,
            executor: executor
        });
    }

    function _sign(SentinelVault.Payment memory p, uint256 key) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r, s, v);
    }

    function _assertNoPaymentSideEffects(uint256 nonce) private view {
        assertEq(token.balanceOf(address(vault)), 2e6);
        assertEq(token.balanceOf(beneficiary), 0);
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testValidERC1271ContractOwnerSignature() public {
        SentinelVault.Payment memory p = _payment(20);
        bytes memory sig = _sign(p, SIGNER_KEY);
        assertEq(wallet.isValidSignature(vault.paymentDigest(p), sig), IERC1271.isValidSignature.selector);
        assertTrue(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), sig));
        // Local simulated execution confirms integration with the actual vault:
        vm.prank(executor);
        vault.execute(p, sig);
        assertEq(token.balanceOf(beneficiary), 100_000);
        assertEq(token.balanceOf(address(vault)), 1_900_000);
        assertTrue(vault.isNonceUsed(20));
    }

    function testWrongSignerAndWrongPaymentNeverSpend() public {
        SentinelVault.Payment memory p = _payment(21);
        bytes memory wrong = _sign(p, WRONG_KEY);
        assertFalse(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), wrong));
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, wrong);
        _assertNoPaymentSideEffects(21);

        bytes memory correct = _sign(p, SIGNER_KEY);
        p.amount += 1;
        assertFalse(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), correct));
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, correct);
        _assertNoPaymentSideEffects(21);
    }

    function testRevokedDigestCannotSpendOrBurnNonce() public {
        SentinelVault.Payment memory p = _payment(22);
        bytes memory sig = _sign(p, SIGNER_KEY);
        wallet.revokeDigest(vault.paymentDigest(p));
        assertEq(wallet.isValidSignature(vault.paymentDigest(p), sig), bytes4(0xffffffff));
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, sig);
        _assertNoPaymentSideEffects(22);
    }

    function testSignerRotationInvalidatesOldSignature() public {
        SentinelVault.Payment memory p = _payment(23);
        bytes memory sig = _sign(p, SIGNER_KEY);
        wallet.changeSigner(vm.addr(WRONG_KEY));
        assertFalse(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), sig));
        vm.expectRevert(SentinelVault.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p, sig);
        _assertNoPaymentSideEffects(23);
        // New signer can authorize a new intent under this test-only wallet.
        bytes memory newSig = _sign(p, WRONG_KEY);
        assertTrue(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), newSig));
    }

    function testOnlyControllerMayRotateSignerRevokeOrChangePolicy() public {
        bytes32 digest = vault.paymentDigest(_payment(24));
        vm.startPrank(outsider);
        vm.expectRevert(MockRevocable1271Owner.UnauthorizedController.selector);
        wallet.changeSigner(outsider);
        vm.expectRevert(MockRevocable1271Owner.UnauthorizedController.selector);
        wallet.revokeDigest(digest);
        vm.expectRevert(MockRevocable1271Owner.UnauthorizedController.selector);
        wallet.setRecipient(vault, outsider, true);
        vm.stopPrank();
        assertEq(wallet.authorizedSigner(), signer);
        assertFalse(wallet.revoked(digest));
        assertFalse(vault.guard().allowedRecipients(outsider));
    }

    function testWrongChainAndVaultAndExpiredIntent() public {
        SentinelVault.Payment memory p = _payment(25);
        bytes memory original = _sign(p, SIGNER_KEY);
        vm.chainId(1);
        assertFalse(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), original));
        vm.chainId(1990);
        SentinelVault other = new SentinelVault(address(token), address(wallet), executor, 1e6, 5e6);
        assertFalse(SignatureChecker.isValidSignatureNow(address(wallet), other.paymentDigest(p), original));

        vm.warp(p.deadline + 1);
        vm.expectRevert(SentinelVault.ExpiredIntent.selector);
        vm.prank(executor);
        vault.execute(p, original);
        _assertNoPaymentSideEffects(25);
    }

    function testReplayIsRejectedForERC1271Owner() public {
        SentinelVault.Payment memory p = _payment(26);
        bytes memory sig = _sign(p, SIGNER_KEY);
        vm.prank(executor);
        vault.execute(p, sig);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, uint256(26)));
        vm.prank(executor);
        vault.execute(p, sig);
        assertEq(token.balanceOf(beneficiary), 100_000);
        assertTrue(vault.isNonceUsed(26));
    }

    function testOwnerNonceInvalidationRejectsPreviouslyValidSignature() public {
        SentinelVault.Payment memory p = _payment(27);
        bytes memory sig = _sign(p, SIGNER_KEY);
        assertTrue(SignatureChecker.isValidSignatureNow(address(wallet), vault.paymentDigest(p), sig));
        wallet.invalidateNonce(vault, 0, uint256(1) << 27);
        vm.expectRevert(abi.encodeWithSelector(SentinelVault.NonceAlreadyUsed.selector, uint256(27)));
        vm.prank(executor);
        vault.execute(p, sig);
        assertEq(token.balanceOf(beneficiary), 0);
        assertEq(token.balanceOf(address(vault)), 2e6);
    }
}
