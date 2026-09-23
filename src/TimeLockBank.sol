// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Adminless custody of LOCK until an owner-selected timestamp.
/// @dev Intended for TimeLockToken: fee-on-transfer and rebasing tokens are unsupported.
contract TimeLockBank is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        address owner;
        uint256 amount;
        uint64 unlockAt;
        bool withdrawn;
    }

    IERC20 public immutable token;
    uint256 public immutable maxLockSeconds;
    uint256 public totalLocked;
    uint256 public nextLockId = 1;

    mapping(uint256 lockId => Lock) private _locks;
    mapping(address owner => uint256[]) private _lockIds;

    error InvalidToken();
    error InvalidMaxLockSeconds();
    error ZeroAmount();
    error UnlockNotFuture();
    error LockTooLong();
    error UnknownLock(uint256 lockId);
    error NotLockOwner(uint256 lockId);
    error AlreadyWithdrawn(uint256 lockId);
    error StillLocked(uint256 lockId, uint64 unlockAt);
    error MustExtend();

    event Deposited(uint256 indexed lockId, address indexed owner, uint256 amount, uint64 unlockAt);
    event Extended(
        uint256 indexed lockId, address indexed owner, uint64 previousUnlockAt, uint64 newUnlockAt
    );
    event Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount);

    /// @param token_ The deployed TimeLockToken address (manifest reference: $token).
    /// @param maxLockSeconds_ Maximum duration measured from each deposit or extension; launch: 31536000.
    constructor(address token_, uint256 maxLockSeconds_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        if (maxLockSeconds_ == 0) revert InvalidMaxLockSeconds();
        token = IERC20(token_);
        maxLockSeconds = maxLockSeconds_;
    }

    /// @notice Pull an approved amount and create a new lock. IDs begin at one and are never reused.
    function deposit(uint256 amount, uint64 unlockAt) external nonReentrant returns (uint256 lockId) {
        if (amount == 0) revert ZeroAmount();
        _validateUnlockTime(unlockAt);

        lockId = nextLockId++;
        _locks[lockId] = Lock(msg.sender, amount, unlockAt, false);
        _lockIds[msg.sender].push(lockId);
        totalLocked += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(lockId, msg.sender, amount, unlockAt);
    }

    /// @notice Withdraw the entire lock to its owner at or after unlockAt, exactly once.
    function withdraw(uint256 lockId) external nonReentrant {
        Lock storage position = _ownedActiveLock(lockId);
        if (block.timestamp < position.unlockAt) revert StillLocked(lockId, position.unlockAt);

        position.withdrawn = true;
        totalLocked -= position.amount;

        token.safeTransfer(position.owner, position.amount);
        emit Withdrawn(lockId, position.owner, position.amount);
    }

    /// @notice Move an active lock's unlock time later, subject to the cap measured from now.
    /// @dev A matured but unwithdrawn lock can be extended to a future timestamp.
    function extend(uint256 lockId, uint64 newUnlockAt) external nonReentrant {
        Lock storage position = _ownedActiveLock(lockId);
        uint64 previousUnlockAt = position.unlockAt;
        if (newUnlockAt <= previousUnlockAt) revert MustExtend();
        _validateUnlockTime(newUnlockAt);

        position.unlockAt = newUnlockAt;
        emit Extended(lockId, msg.sender, previousUnlockAt, newUnlockAt);
    }

    /// @notice Return an existing lock, including its original amount after withdrawal.
    function lock(uint256 lockId) external view returns (Lock memory) {
        Lock storage position = _locks[lockId];
        if (position.owner == address(0)) revert UnknownLock(lockId);
        return position;
    }

    /// @notice Return an owner's IDs in creation order, including withdrawn locks.
    function locksOf(address owner) external view returns (uint256[] memory) {
        return _lockIds[owner];
    }

    function _ownedActiveLock(uint256 lockId) private view returns (Lock storage position) {
        position = _locks[lockId];
        if (position.owner == address(0)) revert UnknownLock(lockId);
        if (position.owner != msg.sender) revert NotLockOwner(lockId);
        if (position.withdrawn) revert AlreadyWithdrawn(lockId);
    }

    function _validateUnlockTime(uint64 unlockAt) private view {
        if (unlockAt <= block.timestamp) revert UnlockNotFuture();
        // Subtraction after the future check avoids overflowing block.timestamp + maxLockSeconds.
        if (uint256(unlockAt) - block.timestamp > maxLockSeconds) revert LockTooLong();
    }
}
