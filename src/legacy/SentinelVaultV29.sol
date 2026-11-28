// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PolicyGuard } from "../PolicyGuard.sol";

/// @title SentinelVaultV29
/// @notice Experimental V2.9 authorization-epoch vault; LOCAL TESTS ONLY, NOT DEPLOYED. QUSDC-only agent vault. A delegated executor submits owner-signed, narrowly scoped payments.
/// @dev A vault owner can always recover its holdings; this is an explicitly privileged escape hatch.
contract SentinelVaultV29 is EIP712, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error UnauthorizedExecutor(address caller);
    error ExpiredIntent(uint256 deadline, uint256 timestamp);
    error InvalidSignature();
    error NonceAlreadyUsed(uint256 nonce);
    error InvalidRecoveryAmount();
    error StaleOwnerEpoch(uint256 supplied, uint256 current);
    error StaleExecutorEpoch(uint256 supplied, uint256 current);

    bytes32 public constant PAYMENT_TYPEHASH = keccak256(
        "Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor,uint256 ownerEpoch,uint256 executorEpoch)"
    );

    IERC20 public immutable token;
    PolicyGuard public immutable guard;
    address public executor;
    uint256 public ownerEpoch;
    uint256 public executorEpoch;
    mapping(uint256 => uint256) private _nonceBitmap;

    struct Payment {
        address token;
        address recipient;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
        address executor;
        uint256 ownerEpoch;
        uint256 executorEpoch;
    }

    event ExecutorChanged(address indexed oldExecutor, address indexed newExecutor);
    event AuthorizationEpochChanged(uint256 ownerEpoch, uint256 executorEpoch);
    event PaymentExecuted(
        bytes32 indexed digest,
        uint256 indexed nonce,
        address indexed recipient,
        uint256 amount,
        address executor
    );
    event NonceInvalidated(uint256 indexed word, uint256 mask);
    event EmergencyRecovered(address indexed recipient, uint256 amount);

    constructor(address token_, address owner_, address executor_, uint256 maxPerTx_, uint256 dailyLimit_)
        EIP712("QIE Sentinel Vault V2", "2")
        Ownable(owner_)
    {
        if (token_ == address(0) || owner_ == address(0) || executor_ == address(0)) revert ZeroAddress();
        token = IERC20(token_);
        executor = executor_;
        executorEpoch = 1;
        guard = new PolicyGuard(address(this), maxPerTx_, dailyLimit_);
        emit ExecutorChanged(address(0), executor_);
    }

    function execute(Payment calldata payment, bytes calldata signature) external nonReentrant whenNotPaused {
        if (msg.sender != executor || payment.executor != msg.sender) {
            revert UnauthorizedExecutor(msg.sender);
        }
        if (block.timestamp > payment.deadline) revert ExpiredIntent(payment.deadline, block.timestamp);
        if (payment.ownerEpoch != ownerEpoch) revert StaleOwnerEpoch(payment.ownerEpoch, ownerEpoch);
        if (payment.executorEpoch != executorEpoch) revert StaleExecutorEpoch(payment.executorEpoch, executorEpoch);
        if (payment.token != address(token)) revert InvalidSignature();
        if (isNonceUsed(payment.nonce)) revert NonceAlreadyUsed(payment.nonce);

        bytes32 digest = paymentDigest(payment);
        if (!SignatureChecker.isValidSignatureNow(owner(), digest, signature)) revert InvalidSignature();

        _useNonce(payment.nonce);
        guard.consume(payment.recipient, payment.amount);
        token.safeTransfer(payment.recipient, payment.amount);
        emit PaymentExecuted(digest, payment.nonce, payment.recipient, payment.amount, msg.sender);
    }

    function paymentDigest(Payment calldata payment) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PAYMENT_TYPEHASH,
                payment.token,
                payment.recipient,
                payment.amount,
                payment.nonce,
                payment.deadline,
                payment.executor,
                payment.ownerEpoch,
                payment.executorEpoch
            )
        );
        return _hashTypedDataV4(structHash);
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function isNonceUsed(uint256 nonce) public view returns (bool) {
        uint256 word = nonce >> 8;
        uint256 bit = uint256(1) << (nonce & 255);
        return (_nonceBitmap[word] & bit) != 0;
    }

    /// @notice Cancel any subset of 256 consecutive nonces. Works even when paused.
    function invalidateNonces(uint256 word, uint256 mask) external onlyOwner {
        _nonceBitmap[word] |= mask;
        emit NonceInvalidated(word, mask);
    }

    function setExecutor(address newExecutor) external onlyOwner {
        if (newExecutor == address(0)) revert ZeroAddress();
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
        ++executorEpoch; // Even setting same address explicitly revokes all old executor-epoch authorizations.
        emit AuthorizationEpochChanged(ownerEpoch, executorEpoch);
    }

    /// @dev Ownable2Step finalizes ownership via _transferOwnership. Epoch changes
    ///      invalidate all previously issued payment intents even if ownership
    ///      later returns to the same address. Does not invalidate nonce bitmap.
    function _transferOwnership(address newOwner) internal override {
        super._transferOwnership(newOwner);
        ++ownerEpoch;
        emit AuthorizationEpochChanged(ownerEpoch, executorEpoch);
    }

    function setRecipient(address recipient, bool allowed) external onlyOwner {
        guard.setRecipient(recipient, allowed);
    }

    function setLimits(uint256 maxPerTx_, uint256 dailyLimit_) external onlyOwner {
        guard.setLimits(maxPerTx_, dailyLimit_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Break-glass recovery; completely independent of agent policy and daily budget.
    /// @dev Recovery is available only while paused and only to a recipient chosen by the owner.
    function emergencyRecover(address recipient, uint256 amount) external onlyOwner whenPaused nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidRecoveryAmount();
        token.safeTransfer(recipient, amount);
        emit EmergencyRecovered(recipient, amount);
    }

    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function _useNonce(uint256 nonce) internal {
        uint256 word = nonce >> 8;
        uint256 bit = uint256(1) << (nonce & 255);
        _nonceBitmap[word] |= bit;
    }
}
