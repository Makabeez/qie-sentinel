// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title PolicyGuardRolling
/// @notice Drop-in replacement for PolicyGuard with a burst-bounded rolling budget.
/// @dev Leaky bucket: capacity = dailyLimit, refill = dailyLimit per 24h, linear.
///      Removes the fixed UTC-midnight reset that allows 2x dailyLimit within one second.
///      Worst case over any window T: dailyLimit + dailyLimit * T / 1 days.
contract PolicyGuardRolling {
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
    uint256 public used;        // bucket level at lastUpdate
    uint256 public lastUpdate;  // timestamp of last consumption

    event RecipientPermissionChanged(address indexed recipient, bool allowed);
    event LimitsChanged(uint256 maxPerTransfer, uint256 dailyLimit);
    event BudgetConsumed(address indexed recipient, uint256 amount, uint256 usedAfter);

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(address vault_, uint256 maxPerTransfer_, uint256 dailyLimit_) {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        _setLimits(maxPerTransfer_, dailyLimit_);
        lastUpdate = block.timestamp;
    }

    function setLimits(uint256 maxPerTransfer_, uint256 dailyLimit_) external onlyVault {
        used = currentUsed(); // settle decay under the OLD rate before changing it
        lastUpdate = block.timestamp;
        _setLimits(maxPerTransfer_, dailyLimit_);
    }

    function setRecipient(address recipient, bool allowed) external onlyVault {
        if (recipient == address(0)) revert ZeroAddress();
        allowedRecipients[recipient] = allowed;
        emit RecipientPermissionChanged(recipient, allowed);
    }

    function currentUsed() public view returns (uint256) {
        uint256 decay = (block.timestamp - lastUpdate) * dailyLimit / 1 days;
        return decay >= used ? 0 : used - decay;
    }

    function remainingToday() public view returns (uint256) {
        uint256 u = currentUsed();
        return u >= dailyLimit ? 0 : dailyLimit - u;
    }

    function validate(address recipient, uint256 amount) public view returns (uint256 usedAfter) {
        if (!allowedRecipients[recipient]) revert RecipientNotAllowed(recipient);
        if (amount == 0) revert AmountZero();
        if (amount > maxPerTransfer) revert TransferLimitExceeded(amount, maxPerTransfer);
        uint256 remaining = remainingToday();
        if (amount > remaining) revert DailyLimitExceeded(amount, remaining);
        usedAfter = currentUsed() + amount;
    }

    function consume(address recipient, uint256 amount) external onlyVault {
        uint256 usedAfter = validate(recipient, amount);
        used = usedAfter;
        lastUpdate = block.timestamp;
        emit BudgetConsumed(recipient, amount, usedAfter);
    }

    function _setLimits(uint256 maxPerTransfer_, uint256 dailyLimit_) internal {
        if (maxPerTransfer_ == 0 || dailyLimit_ == 0 || maxPerTransfer_ > dailyLimit_) revert InvalidLimit();
        maxPerTransfer = maxPerTransfer_;
        dailyLimit = dailyLimit_;
        emit LimitsChanged(maxPerTransfer_, dailyLimit_);
    }
}
