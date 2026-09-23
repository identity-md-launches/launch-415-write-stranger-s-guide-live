# Time Lock

Time Lock is a Sepolia test-launch ERC-20 and an adminless token time lock. Users approve LOCK,
deposit it until a future timestamp, and withdraw the full deposit when that timestamp is reached.
There is no interest, fee, early exit, administrator, pause, rescue, proxy, or upgrade mechanism.

## Build and test offline

Prerequisites: Foundry and Solidity **0.8.26** installed in Foundry's compiler cache. Development
checks used Forge **1.8.3**, commit `cae51ad458f6abb64852b7709eb784352429825d`. Python 3 is used
only for the optional ABI export/check command. All Solidity libraries are ordinary vendored
files; no install, submodule, RPC, environment credentials, or network is needed to build or test.

```sh
forge build --offline
forge test --offline
forge fmt --check
python3 scripts/export-abi.py --check
```

`foundry.toml` enables offline mode by default, so plain `forge build` and `forge test` also work
offline. It pins solc 0.8.26, the Paris EVM target, optimizer with 200 runs, `bytecode_hash = "none"`,
and no CBOR metadata. FFI and filesystem cheatcode access are disabled. There are no deployment
scripts or transactions in these checks. Build artifacts and caches are disposable.

Dependencies: OpenZeppelin Contracts **v5.0.2** (the unmodified ERC-20, SafeERC20, ReentrancyGuard,
and their transitive source dependencies) and forge-std **v1.9.4** (test sources). Versions,
upstream archive locations, archive checksums, and per-file SHA-256 checksums are recorded in
[docs/dependencies.json](docs/dependencies.json). Licenses accompany the vendored sources.

## Contracts and deployment parameters

| Artifact | Constructor | Launch arguments |
| --- | --- | --- |
| `src/TimeLockToken.sol:TimeLockToken` | `constructor()` | None |
| `src/TimeLockBank.sol:TimeLockBank` | `constructor(address token_, uint256 maxLockSeconds_)` | `$token`, `31536000` |

Deploy the token first, then the bank. Both constructors are nonpayable; send **zero ETH**.
Bank constructor arguments are exactly two ABI static words, an address followed by uint256.
The launch chain is **Sepolia, 11155111**, and the application identifier is `TimeLockBank`.
The bank rejects a zero or code-free token address and a zero cap. It does not move the factory's
supply or require an initialization call. The 365-day cap is a fixed number of seconds, not a
calendar year. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the service handoff.

The token name is exactly **Time Lock**, symbol **LOCK** (displayed as **$LOCK**), and decimals
**18**. Its only mint happens in the no-argument constructor: **10^27 minor units**, or exactly
one billion tokens, go to `msg.sender`, which is the deploying factory. No owner or mint role
is recorded. Ordinary OpenZeppelin ERC-20 transfer and allowance behavior applies.

## Bank behavior and integration

- `deposit(amount, unlockAt)` pulls an approved positive amount from the caller. The time must
  be strictly after the executing block's timestamp and no more than `maxLockSeconds` later.
  The call returns a globally unique sequential ID starting at **1**.
- `withdraw(lockId)` is callable only by that lock's owner, once, at or after `unlockAt`.
  It sends the entire original amount to that same owner. There are no partial withdrawals,
  transferable claims, alternate recipients, or third-party withdrawal on an owner's behalf.
- `extend(lockId, newUnlockAt)` is callable only by its owner while unwithdrawn. The new time
  must be strictly later than the old time, strictly in the future, and within the cap from
  the extension transaction's timestamp. A matured lock can be extended before withdrawal.
  Repeated extensions can move a lock beyond one year from its original deposit.
- `lock(lockId)` returns `(owner, amount, unlockAt, withdrawn)`. Unknown IDs, including zero,
  revert. `locksOf(owner)` returns all that owner's IDs in creation order, including withdrawn
  locks. Their original amounts and timestamps remain queryable. `totalLocked` sums only
  unwithdrawn principal. Deposit, extension, and withdrawal emit events.

Approve exactly the intended amount before deposit when allowance is insufficient. Amounts use
18-decimal integer units and times use Unix seconds; `unlockAt` is a `uint64`. Client validation
must allow for the timestamp changing between submission and execution. The exported ABIs and
event/error details are in [docs/ABI.md](docs/ABI.md). Regenerate exports after source changes:

```sh
python3 scripts/export-abi.py
```

## Custody assumptions and limits

The configured token must be the delivered TimeLockToken. SafeERC20 checks reverted and false
token returns; it also accepts conventional tokens with no return data. This is not a general
vault for fee-on-transfer, rebasing, upgradeable, or malicious tokens. The constructor's code
check does not prove ERC-20 compatibility. The manifest reviewer must verify the `$token` link.

Effects precede token calls, and all three mutating bank methods use OpenZeppelin's reentrancy
guard. A failed transfer reverts all state, including allowance changes and the withdrawn flag,
so the owner can retry. No external code runs during extension.

For the supplied token and deposits/withdrawals through the bank, `balanceOf(bank) == totalLocked`.
Anyone can transfer LOCK directly to the bank without making a lock, so unsolicited donations
produce a surplus and the general condition is `balanceOf(bank) >= totalLocked`. Such donations,
other tokens sent by mistake, and forcibly sent ETH have **no recovery path**. Normal ETH sends
revert. Neither the depositor nor any operator can recover a lost wallet's locked balance or
override its unlock time. The contracts provide no yield or price guarantee.

Time is the executing chain's `block.timestamp`, not an off-chain clock. Transactions require
network inclusion; unlock means withdrawal becomes eligible, not that a payment occurs
automatically. Users supply Sepolia gas. The full-array `locksOf` response grows with an owner's
history; large accounts should use events and individual `lock` reads. Deposits, extensions, and
withdrawals do not loop over that history.

## Verification and responsibility

The tests cover token supply, exact transfers, allowance failures, constructor/factory behavior,
all specified lock validation and authorization failures, event values, exact timestamp
boundaries, extension from the current time, failed transfer rollback/retry, and callbacks into
all bank mutations. Fuzz tests cover amounts, durations, withdrawal order, and extensions.
A stateful invariant varies deposit, extend, withdraw, and time across three funded owners;
it compares balances, active records, and independent deposited/withdrawn counters after each
action, then matures and withdraws every remaining lock. Runtime tests scan both artifacts for
forbidden opcodes and the EIP-170 size bound.

This contribution supplies implementation, tests, documentation, and compiler-derived ABIs.
The separate manifest contribution supplies `launch.json`; an independent reviewer examines
both accepted source and the final manifest. Services then publish, attest, admit, and deploy,
and hand verified deployment data to the frontend contribution. Those later results are not
claimed here. Passing local tests is not an independent security review.
