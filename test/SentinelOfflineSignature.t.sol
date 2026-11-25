// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelVault} from "../src/SentinelVault.sol";
import {MockQUSDC} from "./mocks/MockQUSDC.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @notice Offline EIP-712 signature verification with throwaway test keys.
/// @dev No real QIE keys, no mainnet broadcast, no user authorization.
contract SentinelOfflineSignatureTest is Test {
    uint256 internal constant TEST_OWNER_KEY = 0xA11CE;
    uint256 internal constant TEST_OTHER_KEY = 0xB0B;
    address internal owner;
    address internal executor = address(0xE01);
    address internal recipient = address(0xBEEF);
    MockQUSDC internal token;
    SentinelVault internal vault;

    function setUp() public {
        vm.chainId(1990);
        vm.warp(1_800_000_000);
        owner = vm.addr(TEST_OWNER_KEY);
        token = new MockQUSDC();
        vault = new SentinelVault(address(token), owner, executor, 1e6, 5e6);
    }

    function payment() internal view returns (SentinelVault.Payment memory) {
        return SentinelVault.Payment({
            token: address(token), recipient: recipient, amount: 50_000,
            nonce: 3, deadline: block.timestamp + 7 days, executor: executor
        });
    }

    function independentDigest(SentinelVault.Payment memory p) internal view returns (bytes32) {
        bytes32 typehash = keccak256(
            "Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor)"
        );
        bytes32 structHash = keccak256(abi.encode(
            typehash,p.token,p.recipient,p.amount,p.nonce,p.deadline,p.executor
        ));
        bytes32 domainHash = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("QIE Sentinel Vault")),
            keccak256(bytes("1")),
            block.chainid,
            address(vault)
        ));
        return keccak256(abi.encodePacked(hex"1901",domainHash,structHash));
    }

    function signTestKey(bytes32 digest,uint256 key) internal returns (bytes memory) {
        (uint8 v,bytes32 r,bytes32 s) = vm.sign(key,digest);
        return abi.encodePacked(r,s,v);
    }

    function testIndependentDigestMatchesVaultAndLocalSignature() public {
        SentinelVault.Payment memory p = payment();
        bytes32 digest = independentDigest(p);
        assertEq(vault.paymentDigest(p),digest);
        bytes memory signature = signTestKey(digest,TEST_OWNER_KEY);
        assertTrue(SignatureChecker.isValidSignatureNow(owner,digest,signature));
        assertFalse(SignatureChecker.isValidSignatureNow(vm.addr(TEST_OTHER_KEY),digest,signature));
    }

    function testEveryPaymentFieldIsBoundToSignature() public {
        SentinelVault.Payment memory p = payment();
        bytes32 digest = independentDigest(p);
        bytes memory sig = signTestKey(digest,TEST_OWNER_KEY);

        p.recipient = address(0xBAD);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
        p = payment();p.amount += 1;
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
        p = payment();p.nonce += 1;
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
        p = payment();p.deadline += 1;
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
        p = payment();p.executor = address(0xBAD);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
        p = payment();p.token = address(0xBAD);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),sig));
    }

    function testWrongChainAndVaultInvalidateSignatures() public {
        SentinelVault.Payment memory p = payment();
        bytes32 chain1990 = independentDigest(p);
        bytes memory signature = signTestKey(chain1990,TEST_OWNER_KEY);
        vm.chainId(1);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,independentDigest(p),signature));
        assertTrue(SignatureChecker.isValidSignatureNow(owner,chain1990,signature));
        vm.chainId(1990);
        SentinelVault other = new SentinelVault(address(token),owner,executor,1e6,5e6);
        assertTrue(other.paymentDigest(p) != chain1990);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,other.paymentDigest(p),signature));
    }

    function testWrongOwnerDoesNotVerify() public {
        SentinelVault.Payment memory p = payment();
        bytes32 digest = vault.paymentDigest(p);
        bytes memory wrong = signTestKey(digest,TEST_OTHER_KEY);
        assertFalse(SignatureChecker.isValidSignatureNow(owner,digest,wrong));
    }
}
