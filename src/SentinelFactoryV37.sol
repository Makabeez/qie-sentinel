// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SentinelVaultV37 } from "./SentinelVaultV37.sol";

/// @title SentinelFactoryV37
/// @notice Public, permissionless factory for independently owned V37 vaults on QIE Mainnet.
/// @dev UNAUDITED PREVIEW: hard caps are baked in so no user can create a vault whose agent
///      (or owner signature) can move more than PREVIEW_MAX_PER_TX per payment or
///      PREVIEW_DAILY_LIMIT per UTC day. No admin, no fees, no shared funds, no approvals.
contract SentinelFactoryV37 {
    error InvalidToken();
    error InvalidExecutor();
    error ExecutorMustDifferFromOwner();
    error AbovePreviewCap(uint256 maxPerTransfer, uint256 dailyLimit);

    uint256 public constant PREVIEW_MAX_PER_TX = 1_000_000; // 1 QUSDC (6 decimals)
    uint256 public constant PREVIEW_DAILY_LIMIT = 5_000_000; // 5 QUSDC

    address public immutable token;
    address[] private _allVaults;
    mapping(address => address[]) private _vaultsByCreator;

    event VaultCreated(
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

    /// @notice Caller becomes the owner. Recipients and the auto-pay limit are set afterwards by the owner.
    function createVault(address executor_, uint256 maxPerTransfer_, uint256 dailyLimit_)
        external
        returns (address vaultAddress)
    {
        if (executor_ == address(0)) revert InvalidExecutor();
        if (executor_ == msg.sender) revert ExecutorMustDifferFromOwner();
        if (maxPerTransfer_ > PREVIEW_MAX_PER_TX || dailyLimit_ > PREVIEW_DAILY_LIMIT) {
            revert AbovePreviewCap(maxPerTransfer_, dailyLimit_);
        }
        SentinelVaultV37 vault = new SentinelVaultV37(token, msg.sender, executor_, maxPerTransfer_, dailyLimit_);
        vaultAddress = address(vault);
        _allVaults.push(vaultAddress);
        _vaultsByCreator[msg.sender].push(vaultAddress);
        emit VaultCreated(msg.sender, vaultAddress, address(vault.guard()), executor_, maxPerTransfer_, dailyLimit_);
    }

    /// @notice Number of vaults ever created — the on-chain adoption counter.
    function totalVaults() external view returns (uint256) {
        return _allVaults.length;
    }

    function vaultAt(uint256 index) external view returns (address) {
        return _allVaults[index];
    }

    /// @notice Historical creator lookup; query vault.owner() for current ownership.
    function getDeployedVaults(address creator) external view returns (address[] memory) {
        return _vaultsByCreator[creator];
    }
}
