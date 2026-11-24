// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SentinelVault} from "./SentinelVault.sol";

/// @title SentinelVaultFactory
/// @notice Creates independent vaults with each caller as its own owner.
/// @dev Experimental v2 contract, NOT DEPLOYED and NOT independently audited.
///      No privileged factory admin, no pooled custody, and no inherited owner key.
///      Users must explicitly fund/configure their own vault after deployment.
contract SentinelVaultFactory {
    error InvalidToken();
    error InvalidExecutor();
    error ExecutorMustDifferFromOwner();

    address public immutable token;
    mapping(address => address[]) private _vaultsByOwner;

    event VaultCreated(
        address indexed owner,
        address indexed vault,
        address indexed guard,
        address executor,
        uint256 maxPerTransfer,
        uint256 dailyLimit
    );

    constructor(address token_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        token = token_;
    }

    /// @notice Permissionless creation; msg.sender always owns their new vault.
    /// @dev This call deploys a vault but NEVER funds it, signs a payment or sets recipients.
    ///      PolicyGuard validates nonzero and maxPerTransfer <= dailyLimit.
    function createVault(address executor_, uint256 maxPerTransfer_, uint256 dailyLimit_)
        external
        returns (address vaultAddress)
    {
        if (executor_ == address(0)) revert InvalidExecutor();
        if (executor_ == msg.sender) revert ExecutorMustDifferFromOwner();

        SentinelVault vault = new SentinelVault(
            token, msg.sender, executor_, maxPerTransfer_, dailyLimit_
        );
        vaultAddress = address(vault);
        _vaultsByOwner[msg.sender].push(vaultAddress);

        emit VaultCreated(
            msg.sender,
            vaultAddress,
            address(vault.guard()),
            executor_,
            maxPerTransfer_,
            dailyLimit_
        );
    }

    /// @notice Deployment history, NOT a statement of present ownership:
    ///         ownership may later be transferred through Ownable2Step.
    function getDeployedVaults(address creator) external view returns (address[] memory) {
        return _vaultsByOwner[creator];
    }

    function deployedCount(address creator) external view returns (uint256) {
        return _vaultsByOwner[creator].length;
    }
}
