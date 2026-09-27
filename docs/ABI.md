# Contract interface

The JSON files [TimeLockToken.json](abi/TimeLockToken.json) and
[TimeLockBank.json](abi/TimeLockBank.json) are ABI arrays exported directly from the compiler
with `python3 scripts/export-abi.py`. Run it with `--check` to compare them against the current
build. They include constructors, function mutability, indexed events, tuple components, and
custom errors. No deployment address or service handoff hash is fabricated in this source stage.
The live Sepolia addresses and error selectors are in [SEPOLIA-GUIDE.md](SEPOLIA-GUIDE.md).

## TimeLockToken

The constructor has no arguments and is nonpayable. Standard ERC-20 views are `name() -> string`,
`symbol() -> string`, `decimals() -> uint8`, `totalSupply() -> uint256`,
`balanceOf(address) -> uint256`, and `allowance(address,address) -> uint256`.
`transfer(address,uint256)`, `approve(address,uint256)`, and
`transferFrom(address,address,uint256)` are nonpayable and return `bool`.

Events are standard `Transfer(address indexed from,address indexed to,uint256 value)` and
`Approval(address indexed owner,address indexed spender,uint256 value)`. Constructor minting
emits a Transfer from zero to the factory. ERC-20 failures use OpenZeppelin's ERC-6093 custom
errors. The exported ABI is the authoritative list of exposed errors and selectors.

## TimeLockBank

| Function | Return | Meaning |
| --- | --- | --- |
| `deposit(uint256 amount,uint64 unlockAt)` | `uint256 lockId` | Pull approved LOCK and create caller's lock |
| `withdraw(uint256 lockId)` | None | Full payout to owner at/after maturity, once |
| `extend(uint256 lockId,uint64 newUnlockAt)` | None | Move active lock later within the cap from now |
| `lock(uint256 lockId)` | One tuple: `address owner,uint256 amount,uint64 unlockAt,bool withdrawn` | Record, including history; unknown ID reverts |
| `locksOf(address owner)` | `uint256[]` | All owner's IDs in creation order |
| `totalLocked()` | `uint256` | Outstanding principal in minor units |
| `nextLockId()` | `uint256` | Next unused ID, initially 1 |
| `token()` | `address` | Immutable token address |
| `maxLockSeconds()` | `uint256` | Immutable duration cap |

The first three functions are nonpayable; the remaining functions are views. The constructor
is `(address token_, uint256 maxLockSeconds_)`, nonpayable, with no further setup calls.

Events (emitted only when the entire transaction succeeds):

```solidity
event Deposited(uint256 indexed lockId, address indexed owner, uint256 amount, uint64 unlockAt);
event Extended(uint256 indexed lockId, address indexed owner, uint64 previousUnlockAt, uint64 newUnlockAt);
event Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount);
```

| Bank error | Cause |
| --- | --- |
| `InvalidToken()` | Constructor token is zero or has no runtime code |
| `InvalidMaxLockSeconds()` | Constructor cap is zero |
| `ZeroAmount()` | Deposit amount is zero |
| `UnlockNotFuture()` | Requested timestamp is at or before the current block |
| `LockTooLong()` | Requested timestamp exceeds the cap measured from now |
| `UnknownLock(uint256 lockId)` | ID was never created |
| `NotLockOwner(uint256 lockId)` | Caller is not the recorded owner |
| `AlreadyWithdrawn(uint256 lockId)` | Attempt to withdraw or extend a withdrawn record |
| `StillLocked(uint256 lockId,uint64 unlockAt)` | Withdrawal before maturity |
| `MustExtend()` | Extension keeps or shortens the old unlock time |
| `ReentrancyGuardReentrantCall()` | Nested bank mutation during a token call |
| `SafeERC20FailedOperation(address token)` | Token transfer returned false |

SafeERC20 can also bubble token revert data (including ERC-20 allowance/balance errors) and
OpenZeppelin Address errors. Integrators should handle arbitrary transaction revert data.
