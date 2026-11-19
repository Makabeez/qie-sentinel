// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title PolicyGuard
/// @notice Deterministic, vault-controlled payment policy. No AI or off-chain service can bypass it.
/// @dev An epoch is a UTC day (block.timestamp / 1 days). The vault is the sole administrative principal.
contract PolicyGuard {
    error OnlyVault();
    error ZeroAddress();
    error InvalidLimit();
    error RecipientNotAllowed(address recipient);
    error AmountZero();
    error TransferLimitExceeded(uint256 requested, uint256 limit);
    error DailyLimitExceeded(uint256 requested, uint256 remaining);

    address public immutable vault;
    uint256 public maxPerTransfer;
    uint256 public dailyLimit;
    mapping(address => bool) public allowedRecipients;
    mapping(uint256 => uint256) public spentByDay;

    event RecipientPermissionChanged(address indexed recipient, bool allowed);
    event LimitsChanged(uint256 maxPerTransfer, uint256 dailyLimit);
    event BudgetConsumed(uint256 indexed day, address indexed recipient, uint256 amount, uint256 dailyTotal);

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address vault_, uint256 maxPerTransfer_, uint256 dailyLimit_) {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        _setLimits(maxPerTransfer_, dailyLimit_);
    }

    function setLimits(uint256 maxPerTransfer_, uint256 dailyLimit_) external onlyVault {
        _setLimits(maxPerTransfer_, dailyLimit_);
    }

    function setRecipient(address recipient, bool allowed) external onlyVault {
        if (recipient == address(0)) revert ZeroAddress();
        allowedRecipients[recipient] = allowed;
        emit RecipientPermissionChanged(recipient, allowed);
    }

    /// @notice View-only simulation with the same predicates as the state-changing consumption.
    /// @dev Frontends can surface custom error data using eth_call but must still handle execution reverts.
    function validate(address recipient, uint256 amount)
        public
        view
        returns (uint256 day, uint256 totalAfter)
    {
        if (!allowedRecipients[recipient]) {
            revert RecipientNotAllowed(recipient);
        }
        if (amount == 0) revert AmountZero();
        if (amount > maxPerTransfer) revert TransferLimitExceeded(amount, maxPerTransfer);
        day = block.timestamp / 1 days;
        uint256 spent = spentByDay[day];
        if (spent >= dailyLimit || amount > dailyLimit - spent) {
            revert DailyLimitExceeded(amount, spent >= dailyLimit ? 0 : dailyLimit - spent);
        }
        totalAfter = spent + amount;
    }

    /// @notice Called by the vault atomically with token transfer. Reverts roll back budget consumption.
    function consume(address recipient, uint256 amount) external onlyVault {
        (uint256 day, uint256 totalAfter) = validate(recipient, amount);
        spentByDay[day] = totalAfter;
        emit BudgetConsumed(day, recipient, amount, totalAfter);
    }

    function remainingToday() external view returns (uint256) {
        uint256 used = spentByDay[block.timestamp / 1 days];
        return used >= dailyLimit ? 0 : dailyLimit - used;
    }

    function _setLimits(uint256 maxPerTransfer_, uint256 dailyLimit_) internal {
        if (maxPerTransfer_ == 0 || dailyLimit_ == 0 || maxPerTransfer_ > dailyLimit_) {
            revert InvalidLimit();
        }
        maxPerTransfer = maxPerTransfer_;
        dailyLimit = dailyLimit_;
        emit LimitsChanged(maxPerTransfer_, dailyLimit_);
    }
}
