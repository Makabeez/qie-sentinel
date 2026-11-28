// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SentinelVault} from "../../src/SentinelVault.sol";

/// @notice Offline test fixture, not a production wallet. No real funds or keys.
contract MockRevocable1271Owner is IERC1271 {
    error UnauthorizedController();
    error InvalidSigner();

    address public immutable controller;
    address public authorizedSigner;
    mapping(bytes32 => bool) public revoked;

    constructor(address controller_, address signer_) {
        if (controller_ == address(0) || signer_ == address(0)) revert InvalidSigner();
        controller = controller_;
        authorizedSigner = signer_;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedController();
        _;
    }

    function isValidSignature(bytes32 digest, bytes memory signature) external view returns (bytes4) {
        if (revoked[digest]) return bytes4(0xffffffff);
        if (!SignatureChecker.isValidSignatureNow(authorizedSigner, digest, signature))
            return bytes4(0xffffffff);
        return IERC1271.isValidSignature.selector;
    }

    function changeSigner(address nextSigner) external onlyController {
        if (nextSigner == address(0)) revert InvalidSigner();
        authorizedSigner = nextSigner;
    }

    function revokeDigest(bytes32 digest) external onlyController {
        revoked[digest] = true;
    }

    function setRecipient(SentinelVault vault, address recipient, bool allowed) external onlyController {
        vault.setRecipient(recipient, allowed);
    }

    function pauseVault(SentinelVault vault) external onlyController {
        vault.pause();
    }

    function invalidateNonce(SentinelVault vault, uint256 word, uint256 mask)
        external onlyController
    {
        vault.invalidateNonces(word, mask);
    }
}
