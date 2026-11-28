// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SentinelVaultV33} from "../../src/legacy/SentinelVaultV33.sol";

/// @notice TEST-ONLY wallet supporting monotonic signer epoch for V3.3.
/// @dev Not a secure production wallet. Uses an explicit controller to simulate
///      signer rotations, cancellations, and owner-admin calls in a local EVM.
contract MockV33EpochWallet is IERC1271 {
    error UnauthorizedController();
    error InvalidSigner();

    address public immutable controller;
    address public authorizedSigner;
    uint256 public signerEpoch = 1;
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
        if (!SignatureChecker.isValidSignatureNow(authorizedSigner, digest, signature)) {
            return bytes4(0xffffffff);
        }
        return IERC1271.isValidSignature.selector;
    }

    function changeSigner(address nextSigner) external onlyController {
        if (nextSigner == address(0)) revert InvalidSigner();
        authorizedSigner = nextSigner;
        ++signerEpoch; // Monotonic even when an earlier signer is restored.
    }

    function revokeDigest(bytes32 digest) external onlyController {
        revoked[digest] = true;
    }

    function setRecipient(SentinelVaultV33 vault, address recipient, bool allowed)
        external onlyController
    {
        vault.setRecipient(recipient, allowed);
    }

    function setExecutor(SentinelVaultV33 vault, address nextExecutor)
        external onlyController
    {
        vault.setExecutor(nextExecutor);
    }

    function invalidateNonces(SentinelVaultV33 vault, uint256 word, uint256 mask)
        external onlyController
    {
        vault.invalidateNonces(word, mask);
    }

    function pauseVault(SentinelVaultV33 vault) external onlyController {
        vault.pause();
    }

    function unpauseVault(SentinelVaultV33 vault) external onlyController {
        vault.unpause();
    }
}
