// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SentinelVaultV33} from "../../src/SentinelVaultV33.sol";

/// @notice Deliberately unsafe ERC-1271 fixture, NEVER for real assets.
/// @dev Simulates frozen epoch, unavailable epoch/signature and internal signer changes.
contract MockV34AdversarialWallet is IERC1271 {
    error UnauthorizedController();
    error BrokenEpoch();
    error BrokenSignature();

    address public immutable controller;
    address public authorizedSigner;
    uint256 private _epoch = 1;
    bool public freezeEpoch;
    bool public revertEpoch;
    bool public revertSignature;
    bool public forceInvalidSignature;

    constructor(address controller_, address signer_) {
        controller = controller_;
        authorizedSigner = signer_;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedController();
        _;
    }

    function signerEpoch() external view returns (uint256) {
        if (revertEpoch) revert BrokenEpoch();
        return _epoch;
    }

    function changeSigner(address next) external onlyController {
        authorizedSigner = next;
        if (!freezeEpoch) ++_epoch;
    }

    function setFreezeEpoch(bool enabled) external onlyController {
        freezeEpoch = enabled;
    }

    function setRevertEpoch(bool enabled) external onlyController {
        revertEpoch = enabled;
    }

    function setRevertSignature(bool enabled) external onlyController {
        revertSignature = enabled;
    }

    function setForceInvalidSignature(bool enabled) external onlyController {
        forceInvalidSignature = enabled;
    }

    function isValidSignature(bytes32 digest, bytes memory signature) external view returns (bytes4) {
        if (revertSignature) revert BrokenSignature();
        if (forceInvalidSignature) return bytes4(0xffffffff);
        if (SignatureChecker.isValidSignatureNow(authorizedSigner,digest,signature)) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0xffffffff);
    }

    function configureRecipient(SentinelVaultV33 vault, address recipient, bool allowed) external onlyController {
        vault.setRecipient(recipient,allowed);
    }

    function pauseVault(SentinelVaultV33 vault) external onlyController {
        vault.pause();
    }

    function recover(SentinelVaultV33 vault,address recipient,uint256 amount) external onlyController {
        vault.emergencyRecover(recipient,amount);
    }

    function invalidate(SentinelVaultV33 vault,uint256 word,uint256 mask) external onlyController {
        vault.invalidateNonces(word,mask);
    }
}
