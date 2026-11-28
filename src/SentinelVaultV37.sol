// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SentinelVaultV35 } from "./SentinelVaultV35.sol";

/// @title SentinelVaultV37 — bounded autonomy
/// @notice The agent's hot key (executor) may pay ALLOWLISTED recipients up to `autoLimitPerTx`
///         with NO owner signature, inside the PolicyGuard daily budget. Anything larger still
///         needs the owner's exact EIP-712 signature via execute(). autoLimitPerTx == 0 disables it.
/// @dev Worst case if the executor key is stolen: dailyLimit per UTC day to allowlisted addresses only.
contract SentinelVaultV37 is SentinelVaultV35 {
    using SafeERC20 for IERC20;

    error AutoLimitExceeded(uint256 requested, uint256 limit);

    uint256 public autoLimitPerTx;

    event AutoLimitChanged(uint256 autoLimitPerTx);
    event AutoPaymentExecuted(uint256 indexed nonce, address indexed recipient, uint256 amount, address executor);

    constructor(address token_, address owner_, address executor_, uint256 maxPerTx_, uint256 dailyLimit_)
        SentinelVaultV35(token_, owner_, executor_, maxPerTx_, dailyLimit_)
    { }

    function setAutoLimit(uint256 autoLimitPerTx_) external onlyOwner {
        if (autoLimitPerTx_ > guard.maxPerTransfer()) revert AutoLimitExceeded(autoLimitPerTx_, guard.maxPerTransfer());
        autoLimitPerTx = autoLimitPerTx_;
        emit AutoLimitChanged(autoLimitPerTx_);
    }

    /// @notice Agent-initiated small payment. Shares the nonce space and daily budget with execute().
    function executeAuto(address recipient, uint256 amount, uint256 nonce) external nonReentrant whenNotPaused {
        if (msg.sender != executor) revert UnauthorizedExecutor(msg.sender);
        if (amount > autoLimitPerTx) revert AutoLimitExceeded(amount, autoLimitPerTx);
        if (recipient == address(this)) revert InvalidRecipient(recipient);
        if (isNonceUsed(nonce)) revert NonceAlreadyUsed(nonce);
        _useNonce(nonce); // same bitmap as execute(); invalidateNonces() cancels queued auto-payments too
        guard.consume(recipient, amount); // allowlist + per-tx + daily budget, reverts atomically
        uint256 before = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        uint256 credited = token.balanceOf(recipient) - before;
        if (credited != amount) revert UnexpectedTransferAmount(amount, amount, credited);
        emit AutoPaymentExecuted(nonce, recipient, amount, msg.sender);
    }
}
