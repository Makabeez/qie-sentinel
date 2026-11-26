// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Optional contract-owner capability REQUIRED by SentinelVaultV33.
/// @dev The owner wallet MUST increase this counter on EVERY authorization
///      policy/signer change, including restoring an earlier signer or module.
///      A malicious or incorrectly implemented wallet can lie about the value.
interface ISentinelOwnerSignerEpoch {
    function signerEpoch() external view returns (uint256);
}
