// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SentinelVaultV29} from "../src/SentinelVaultV29.sol";
import {SentinelEpochFactoryV30} from "../src/SentinelEpochFactoryV30.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {MockV32ContractOwner} from "./mocks/MockV32ContractOwner.sol";

/// @notice v3.2 local pre-audit ERC-1271 and epoch compatibility regression.
contract SentinelV32ContractOwnerTest is Test {
    uint256 private constant FIRST_KEY = 0xA11CE;
    uint256 private constant SECOND_KEY = 0xB0B;
    address private signer;
    address private secondSigner;
    address private executor = address(0xE01);
    address private beneficiary = address(0xCAFE);
    address private outsider = address(0xBAD);
    MockQUSDC private token;
    SentinelEpochFactoryV30 private factory;
    MockV32ContractOwner private wallet;
    SentinelVaultV29 private vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        signer = vm.addr(FIRST_KEY);
        secondSigner = vm.addr(SECOND_KEY);
        token = new MockQUSDC();
        factory = new SentinelEpochFactoryV30(address(token));
        wallet = new MockV32ContractOwner(address(this), signer);
        // A contract wallet can itself call the factory; we simulate it with vm.prank.
        vm.prank(address(wallet));
        vault = SentinelVaultV29(factory.createVault(executor, 250_000, 400_000));
        wallet.setRecipient(vault, beneficiary, true);
        token.mint(address(vault), 1_000_000);
    }

    function _payment(uint256 nonce) private view returns (SentinelVaultV29.Payment memory) {
        return SentinelVaultV29.Payment({
            token: address(token),
            recipient: beneficiary,
            amount: 100_000,
            nonce: nonce,
            deadline: block.timestamp + 3600,
            executor: vault.executor(),
            ownerEpoch: vault.ownerEpoch(),
            executorEpoch: vault.executorEpoch()
        });
    }

    function _sign(SentinelVaultV29.Payment memory p, uint256 key) private returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, vault.paymentDigest(p));
        return abi.encodePacked(r,s,v);
    }

    function _assertUnspent(uint256 nonce) private view {
        assertFalse(vault.isNonceUsed(nonce));
        assertEq(token.balanceOf(address(vault)), 1_000_000);
        assertEq(token.balanceOf(beneficiary), 0);
        assertEq(vault.guard().spentByDay(block.timestamp / 1 days), 0);
    }

    function testV32ContractWalletOwnsIndependentFactoryVault() public {
        assertEq(vault.owner(), address(wallet));
        assertEq(factory.deployedCount(address(wallet)), 1);
        assertEq(vault.executorEpoch(), 1);
        assertTrue(vault.ownerEpoch() > 0);
        assertEq(vault.guard().vault(), address(vault));
    }

    function testV32ValidERC1271SignatureExecutesOwnerApprovedPayment() public {
        SentinelVaultV29.Payment memory p = _payment(20);
        bytes memory sig = _sign(p, FIRST_KEY);
        assertEq(wallet.isValidSignature(vault.paymentDigest(p),sig),IERC1271.isValidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        assertTrue(vault.isNonceUsed(20));
        assertEq(token.balanceOf(beneficiary),100_000);
    }

    function testV32WrongContractWalletSignerCannotSpendOrBurnNonce() public {
        SentinelVaultV29.Payment memory p = _payment(21);
        bytes memory sig = _sign(p, SECOND_KEY);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        _assertUnspent(21);
    }

    function testV32ContractWalletRevokesDigest() public {
        SentinelVaultV29.Payment memory p = _payment(22);
        bytes memory sig = _sign(p, FIRST_KEY);
        wallet.revokeDigest(vault.paymentDigest(p));
        assertEq(wallet.isValidSignature(vault.paymentDigest(p),sig),bytes4(0xffffffff));
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,sig);
        _assertUnspent(22);
    }

    function testV32ContractWalletSignerRotationInvalidatesOldSignature() public {
        SentinelVaultV29.Payment memory p = _payment(23);
        bytes memory oldSig = _sign(p,FIRST_KEY);
        wallet.changeSigner(secondSigner);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        vault.execute(p,oldSig);
        _assertUnspent(23);
        bytes memory newSig = _sign(p,SECOND_KEY);
        vm.prank(executor);
        vault.execute(p,newSig);
        assertEq(token.balanceOf(beneficiary),100_000);
    }

    function testV32ContractWalletExecutorRotationInvalidatesPriorEpoch() public {
        SentinelVaultV29.Payment memory p = _payment(24);
        bytes memory sig = _sign(p,FIRST_KEY);
        uint256 previous = p.executorEpoch;
        wallet.setExecutor(vault,executor);
        assertEq(vault.executorEpoch(),previous+1);
        vm.expectRevert(abi.encodeWithSelector(
            SentinelVaultV29.StaleExecutorEpoch.selector,previous,previous+1
        ));
        vm.prank(executor);
        vault.execute(p,sig);
        _assertUnspent(24);
    }

    function testV32ContractWalletNonceCancellationPreventsReplay() public {
        SentinelVaultV29.Payment memory p = _payment(25);
        bytes memory sig = _sign(p,FIRST_KEY);
        wallet.invalidateNonces(vault,0,uint256(1)<<25);
        vm.expectRevert(abi.encodeWithSelector(SentinelVaultV29.NonceAlreadyUsed.selector,uint256(25)));
        vm.prank(executor);
        vault.execute(p,sig);
        _assertUnspent(25);
    }

    function testV32OutsiderCannotInvokeContractWalletAdministration() public {
        vm.startPrank(outsider);
        vm.expectRevert(MockV32ContractOwner.UnauthorizedController.selector);
        wallet.changeSigner(outsider);
        vm.expectRevert(MockV32ContractOwner.UnauthorizedController.selector);
        wallet.revokeDigest(bytes32(uint256(1)));
        vm.expectRevert(MockV32ContractOwner.UnauthorizedController.selector);
        wallet.setRecipient(vault, outsider, true);
        vm.expectRevert(MockV32ContractOwner.UnauthorizedController.selector);
        wallet.pauseVault(vault);
        vm.stopPrank();
        assertEq(wallet.authorizedSigner(),signer);
        assertFalse(vault.guard().allowedRecipients(outsider));
        assertFalse(vault.paused());
    }

    function testV32CrossVault1271SignatureDomainSeparation() public {
        SentinelVaultV29.Payment memory p = _payment(26);
        bytes memory sig = _sign(p,FIRST_KEY);
        vm.prank(address(wallet));
        SentinelVaultV29 other = SentinelVaultV29(factory.createVault(executor,250_000,400_000));
        wallet.setRecipient(other,beneficiary,true);
        token.mint(address(other),1_000_000);
        vm.expectRevert(SentinelVaultV29.InvalidSignature.selector);
        vm.prank(executor);
        other.execute(p,sig);
        assertEq(token.balanceOf(address(other)),1_000_000);
        assertFalse(other.isNonceUsed(26));
    }
}
