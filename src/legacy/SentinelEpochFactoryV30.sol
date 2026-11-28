// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SentinelVaultV29} from "./SentinelVaultV29.sol";

/// @title SentinelEpochFactoryV30
/// @notice Experimental factory for epoch-protected, independently owned vaults.
/// @dev NOT DEPLOYED; local Foundry tests only. No factory admin, shared funds,
///      signing authority, auto-funding, token transfers or delegate approvals.
///      Creation history does NOT prove current ownership after a transfer.
contract SentinelEpochFactoryV30 {
    error InvalidToken();
    error InvalidExecutor();
    error ExecutorMustDifferFromOwner();

    address public immutable token;
    mapping(address => address[]) private _vaultsByCreator;

    event EpochVaultCreated(
        address indexed creator,
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

    /// @notice Caller is always the initial owner, with a distinct executor.
    /// @dev No allowlisted recipients, funding or signature creation in factory.
    function createVault(address executor_, uint256 maxPerTransfer_, uint256 dailyLimit_)
        external
        returns (address vaultAddress)
    {
        if (executor_ == address(0)) revert InvalidExecutor();
        if (executor_ == msg.sender) revert ExecutorMustDifferFromOwner();

        SentinelVaultV29 vault = new SentinelVaultV29(
            token, msg.sender, executor_, maxPerTransfer_, dailyLimit_
        );
        vaultAddress = address(vault);
        _vaultsByCreator[msg.sender].push(vaultAddress);
        emit EpochVaultCreated(
            msg.sender,
            vaultAddress,
            address(vault.guard()),
            executor_,
            maxPerTransfer_,
            dailyLimit_
        );
    }

    /// @notice Historical creator lookup; owner() must be queried for current owner.
    function getDeployedVaults(address creator) external view returns (address[] memory) {
        return _vaultsByCreator[creator];
    }

    function deployedCount(address creator) external view returns (uint256) {
        return _vaultsByCreator[creator].length;
    }
}
