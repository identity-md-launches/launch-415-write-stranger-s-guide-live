# Time Lock on Sepolia: a stranger's guide

> **Test network only.** Everything below is on the Sepolia test network (chain ID 11155111).
> Sepolia ETH and LOCK have **no monetary value**. The contracts have passed their own tests
> but have not had an independent audit. Do not use this code with real funds.

This guide covers the live deployment from launch 113: where it is, how to get test LOCK, and how
to use the bank from the command line with Foundry's `cast`. For building, testing, the contract
rules and custody assumptions, see [README.md](../README.md). For every function, event and error,
see [docs/ABI.md](ABI.md).

## What the two contracts do

1. `TimeLockToken` is a plain fixed-supply ERC-20 named "Time Lock" (symbol LOCK, 18 decimals).
   All 1,000,000,000 LOCK were minted once, to the launch factory, when it was deployed.
2. `TimeLockBank` holds LOCK that you deposit until a Unix timestamp you choose. The timestamp
   must be in the future and no more than 31,536,000 seconds (365 days) away.
3. Each deposit creates a numbered lock. Only the depositing address can move its unlock time
   later or withdraw it.
4. Withdrawal is all-or-nothing, only at or after the unlock time, and only once. The whole
   amount goes back to the address that deposited it.
5. Neither contract has an owner, an admin, a pause switch, fees, interest or an upgrade path.
   Nobody can unlock your tokens early, including you.

## Deployed addresses

Everything below was deployed by the IdentityMD launch factory in transaction
[`0xb504e6cf…7383b2`](https://sepolia.etherscan.io/tx/0xb504e6cfa47c92ac913bdbbf172680fc2ab5df38865fe94e183bfc1b827383b2),
block [11761675](https://sepolia.etherscan.io/block/11761675).

| What | Address | In this repo? |
| --- | --- | --- |
| TimeLockToken (LOCK) | [`0x1befeab42d891b69441405a676de77565619e084`](https://sepolia.etherscan.io/address/0x1befeab42d891b69441405a676de77565619e084) | Yes, `src/TimeLockToken.sol` |
| TimeLockBank | [`0x4e0aa49ef9691c8f929daf94562681ac79108a39`](https://sepolia.etherscan.io/address/0x4e0aa49ef9691c8f929daf94562681ac79108a39) | Yes, `src/TimeLockBank.sol` |
| Reward MerkleDistributor (factory's) | [`0x8db9c22d47cbfe099aa5a0d91c7e6ca7e2a7c30a`](https://sepolia.etherscan.io/address/0x8db9c22d47cbfe099aa5a0d91c7e6ca7e2a7c30a) | **No.** It belongs to the launch factory, and nothing here documents or tests it. |
| Uniswap v4 PoolManager (Sepolia) | [`0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`](https://sepolia.etherscan.io/address/0xE03A1074c86CFeDd5C142C4F04F1a1536e203543) | No. This is Uniswap's contract. |
| Launch factory (the deploying transaction's `to`) | [`0x770e474e3d4eb5d8cdfd45ba2dea9a02ed5fc9fd`](https://sepolia.etherscan.io/address/0x770e474e3d4eb5d8cdfd45ba2dea9a02ed5fc9fd) | No |

State read from Sepolia on 2026-09-27:

| Call | Result |
| --- | --- |
| `LOCK.symbol()`, `decimals()`, `totalSupply()` | `LOCK`, `18`, `1000000000000000000000000000` (10^27 = one billion LOCK) |
| `bank.token()` | `0x1BEfEAB42d891b69441405a676DE77565619E084` (the LOCK token) |
| `bank.maxLockSeconds()` | `31536000` |
| `bank.totalLocked()` | `0` |
| `bank.nextLockId()` | `1`, so no lock had been created yet and nobody had used the bank |
| `bank.lock(1)` | reverts `UnknownLock(1)` |

The LOCK/ETH pool was initialized in the same transaction. Its `Initialize` event gives pool
ID `0x147b813b463cddbef368c29b8a516fcf3459a6cb5d27d298b0c946d1a8bf8c00` with currency0 native
Sepolia ETH (`0x0000000000000000000000000000000000000000`), currency1 LOCK, fee `3000`
(0.30%), tick spacing `60`, and no hook (`hooks = 0x0000000000000000000000000000000000000000`).

This guide does not claim that the contracts' source code is verified on Etherscan. Etherscan may
show only bytecode. The commands below pass function signatures explicitly, so they work either
way.

## Getting test LOCK

**There is no LOCK faucet.** You have two ways to get LOCK:

- **Swap Sepolia ETH for LOCK** in the pool above, using any interface that supports Uniswap v4
  on Sepolia. Pick the pool by its key: native ETH / LOCK
  `0x1befeab42d891b69441405a676de77565619e084`, fee 3000, tick spacing 60, no hooks. You need
  Sepolia ETH for the swap and for gas. Get it from a Sepolia ETH faucet of your choice; none is
  run by this project.
- **Receive LOCK from someone who already holds it**, as an ordinary ERC-20 transfer.

The reward MerkleDistributor above pays out launch rewards to specific contributors. It is not a
faucet, and this repository does not describe how to claim from it.

## Using the bank with `cast`

You need [Foundry](https://getfoundry.sh) (these commands were checked with cast 1.8.3) and a
Sepolia RPC endpoint.

### One-time setup: a keystore account, not a pasted key

Never put a private key on the command line or in your shell history. Import it once into an
encrypted Foundry keystore instead. Both prompts are hidden:

```sh
cast wallet import sepolia-me --interactive   # asks for the private key, then a password
cast wallet list                              # shows: sepolia-me (Local)
```

From now on, every transaction uses `--account sepolia-me` and cast asks for the keystore
password. Use a throwaway test wallet, not one that holds anything real.

```sh
export ETH_RPC_URL=https://your-sepolia-rpc.example   # any Sepolia RPC you trust
export LOCK=0x1befeab42d891b69441405a676de77565619e084
export BANK=0x4e0aa49ef9691c8f929daf94562681ac79108a39
export ME=$(cast wallet address --account sepolia-me)

cast chain-id                                          # must print 11155111
cast call $BANK "token()(address)"                     # must print the LOCK address
cast call $LOCK "balanceOf(address)(uint256)" $ME      # your LOCK, in 18-decimal units
```

Amounts are integers with 18 decimals: `cast to-wei 100` prints `100000000000000000000`
(100 LOCK). `cast from-wei <n>` converts back.

### How failures show up

When a call would revert, `cast send` fails while estimating gas. **It does not send a
transaction, so no gas is spent.** The message ends with the decoded error, for example:

```text
Error: Failed to estimate gas: server returned an error response: error code 3: execution reverted: custom error 0x8b79d5ce, data: "0x8b79d5ce": UnlockNotFuture
```

If your cast version prints only the 4-byte selector, look it up here:

| Error | Selector | Raised by |
| --- | --- | --- |
| `ZeroAmount()` | `0x1f2a2005` | `deposit` |
| `UnlockNotFuture()` | `0x8b79d5ce` | `deposit`, `extend` |
| `LockTooLong()` | `0xd6946a43` | `deposit`, `extend` |
| `UnknownLock(uint256 lockId)` | `0x3e70de66` | `lock`, `extend`, `withdraw` |
| `NotLockOwner(uint256 lockId)` | `0x6102dd67` | `extend`, `withdraw` |
| `AlreadyWithdrawn(uint256 lockId)` | `0x54225c2b` | `extend`, `withdraw` |
| `StillLocked(uint256 lockId, uint64 unlockAt)` | `0x8ea8d84a` | `withdraw` |
| `MustExtend()` | `0x4aa64756` | `extend` |
| `ERC20InsufficientAllowance(address,uint256,uint256)` | `0xfb8f41b2` | the LOCK token, during `deposit` |
| `ERC20InsufficientBalance(address,uint256,uint256)` | `0xe450d38c` | the LOCK token, during `deposit` |

The last two errors come from the token, not the bank. The bank passes them through unchanged.

### 1. Approve

The bank pulls LOCK from you, so first allow it to take exactly the amount you will lock.
Anyone may call `approve`; it only affects your own allowance.

```sh
AMOUNT=$(cast to-wei 100)                       # 100 LOCK
cast send $LOCK "approve(address,uint256)" $BANK $AMOUNT --account sepolia-me
cast call $LOCK "allowance(address,address)(uint256)" $ME $BANK
```

If you skip this step or approve too little, `deposit` fails with
`ERC20InsufficientAllowance(bank, allowance, needed)`. If you hold less LOCK than `AMOUNT`, it
fails with `ERC20InsufficientBalance(you, balance, needed)`.

### 2. Deposit: `deposit(uint256 amount, uint64 unlockAt)`

Anyone holding LOCK may call this. `unlockAt` is a Unix time in seconds. Compute it from the
current time. It must be strictly later than the block's timestamp and at most 31,536,000
seconds after it, when the transaction executes.

```sh
UNLOCK_AT=$(( $(date +%s) + 600 ))              # ten minutes from now
cast send $BANK "deposit(uint256,uint64)" $AMOUNT $UNLOCK_AT --account sepolia-me
```

For the longest allowed lock, leave a margin below the cap, because your clock and the chain's
clock differ and inclusion takes time:

```sh
UNLOCK_AT=$(( $(date +%s) + 31536000 - 600 ))   # 365 days minus ten minutes
```

The new lock's ID is the `nextLockId()` value from before your transaction. It is also
the first indexed topic of the `Deposited` event in your receipt, and the last entry of
`locksOf($ME)`. The first lock ever made on this bank gets ID 1.

| Wrong use | Error |
| --- | --- |
| `amount` is 0 | `ZeroAmount()` |
| `unlockAt` is now or in the past (for example `$(date +%s)` with no offset) | `UnlockNotFuture()` |
| `unlockAt` more than 31,536,000 s after the executing block (for example `+ 31536000 + 3600`) | `LockTooLong()` |
| allowance too low | `ERC20InsufficientAllowance(...)` from the token |
| balance too low | `ERC20InsufficientBalance(...)` from the token |

### 3. Read a lock: `lock(uint256 lockId)`

This is a free read-only view that anyone may call. It returns `(owner, amount, unlockAt,
withdrawn)`. Withdrawn locks stay readable with their original amount.

```sh
cast call $BANK "lock(uint256)((address,uint256,uint64,bool))" 1
# (0xYourAddress, 100000000000000000000 [1e20], 1790532821 [1.79e9], false)
```

| Wrong use | Error |
| --- | --- |
| ID 0, or an ID not yet created (at or above `nextLockId()`) | `UnknownLock(lockId)` |

### 4. List your locks: `locksOf(address owner)`

This is a free view that anyone may call for any address. It returns every lock ID that
address ever created, oldest first, including withdrawn ones.

```sh
cast call $BANK "locksOf(address)(uint256[])" $ME        # e.g. [1]
```

It never reverts. An address with no locks returns `[]`. For an address with a very long
history, use the events below and individual `lock` reads instead.

### 5. Extend: `extend(uint256 lockId, uint64 newUnlockAt)`

Only the lock's owner may call this, and only while the lock has not been withdrawn. It moves
the unlock time later. It can never move it earlier. The new time must also be in the future and
within 31,536,000 seconds of the executing block. That means repeated extensions can keep a
lock going past one year from the original deposit. You can also extend a lock that has already
matured, as long as you have not withdrawn it.

```sh
ID=1
OLD=$(cast call $BANK "lock(uint256)((address,uint256,uint64,bool))" $ID | cut -d, -f3 | awk '{print $1}')
cast send $BANK "extend(uint256,uint64)" $ID $(( OLD + 86400 )) --account sepolia-me   # one more day
```

The checks run in this order, so the first one that fails is the error you see:

| Wrong use | Error |
| --- | --- |
| ID never created | `UnknownLock(lockId)` |
| you are not the owner | `NotLockOwner(lockId)` |
| lock already withdrawn | `AlreadyWithdrawn(lockId)` |
| `newUnlockAt` equal to or earlier than the current `unlockAt` | `MustExtend()` |
| `newUnlockAt` later than the old time but not in the future (matured lock) | `UnlockNotFuture()` |
| `newUnlockAt` more than 31,536,000 s after the executing block | `LockTooLong()` |

### 6. Withdraw: `withdraw(uint256 lockId)`

Only the lock's owner may call this, once, when the latest block's timestamp is at or after
`unlockAt`. The whole amount goes to the owner. You cannot take part of it, and you cannot
send it to a different address. Nothing happens automatically at the unlock time: you have to
send this transaction and pay the gas yourself.

```sh
cast block latest --field timestamp                       # chain time; compare with unlockAt
cast send $BANK "withdraw(uint256)" 1 --account sepolia-me
cast call $LOCK "balanceOf(address)(uint256)" $ME
```

| Wrong use | Error |
| --- | --- |
| ID never created | `UnknownLock(lockId)` |
| you are not the owner (checked before the withdrawn flag) | `NotLockOwner(lockId)` |
| already withdrawn | `AlreadyWithdrawn(lockId)` |
| chain time still before `unlockAt` | `StillLocked(lockId, unlockAt)` |

### Other read-only views

```sh
cast call $BANK "totalLocked()(uint256)"      # LOCK held for unwithdrawn locks (donations excluded)
cast call $BANK "nextLockId()(uint256)"       # next ID to be assigned; 1 means none yet
cast call $BANK "maxLockSeconds()(uint256)"   # 31536000
cast call $BANK "token()(address)"            # LOCK
```

These views never revert. The bank has no other public functions. It also has no `receive`
function, so sending it plain ETH reverts.

## Reading events with `cast logs`

The bank emits three events. The lock ID and the owner are indexed, so you can filter on them.
Start from the deployment block, 11761675. There is nothing earlier to find.

```sh
cast logs --from-block 11761675 --address $BANK \
  "Deposited(uint256 indexed lockId, address indexed owner, uint256 amount, uint64 unlockAt)"

cast logs --from-block 11761675 --address $BANK \
  "Extended(uint256 indexed lockId, address indexed owner, uint64 previousUnlockAt, uint64 newUnlockAt)"

cast logs --from-block 11761675 --address $BANK \
  "Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount)"
```

To see only your own events, add topic filters after the signature. Leave the lock ID empty
(`""`) and give the owner address:

```sh
cast logs --from-block 11761675 --address $BANK \
  "Deposited(uint256 indexed lockId, address indexed owner, uint256 amount, uint64 unlockAt)" "" $ME
```

Each log lists `topics` (the event signature hash, then `lockId`, then `owner`) and `data`
(the rest). To decode the data of a `Deposited` log:

```sh
cast decode-abi --input "f(uint256,uint64)" <data>        # amount, unlockAt
```

Use `f(uint64,uint64)` for `Extended` (previousUnlockAt, newUnlockAt) and `f(uint256)` for
`Withdrawn` (amount).

On 2026-09-27 these queries returned nothing, because nobody had used the bank yet.
Some public RPC endpoints return incomplete old logs or limit block ranges. While writing this
guide, one public Sepolia endpoint returned no logs at all for the deployment block, even though
the receipt contains nine. If a result looks empty or wrong, compare it with `nextLockId()` and
`totalLocked()`, or try another endpoint.

## Trust assumptions, in plain words

- **No admin.** Nobody controls the bank. There is no owner, operator, pause, rescue or upgrade.
  The token address and the 365-day cap were fixed at deployment and can never change. The code
  on Sepolia is the code you will always get.
- **No early exit.** Once you deposit, your LOCK stays locked until the unlock time. You can
  push that time later but never earlier, and nobody can make an exception.
- **Lost keys lose the lock.** Only the depositing address can withdraw, and the tokens can only
  go back to that address. Nobody can recover a lock whose key is lost, and locks cannot be
  transferred to another address.
- **Donations are stranded.** LOCK (or any other token) sent straight to the bank address
  without calling `deposit` does not create a lock and cannot be recovered by anyone. The same
  applies to ETH forced into the bank.
- **Time is the chain's timestamp.** The bank compares against Sepolia's `block.timestamp`, not
  your computer's clock. A withdrawal becomes allowed when a block at or after `unlockAt`
  includes it. You still have to send it.
- **What this repository does not cover.** The reward MerkleDistributor, the factory and the
  Uniswap pool are outside this repository. This guide only reports what can be seen of them
  on-chain. It makes no promise about the LOCK price or about liquidity.

More detail is in the README's
[custody assumptions and limits](../README.md#custody-assumptions-and-limits).

## Where the brief and the code differ

This guide was written from a brief. Where the code says something the brief did not, the guide
follows the code:

- The brief lists eight bank errors. Two more failures happen during `deposit`, and they come
  from the LOCK token, not the bank: `ERC20InsufficientAllowance` and `ERC20InsufficientBalance`.
- `lock(id)` and `locksOf(address)` are read-only views. `lock` can only fail with
  `UnknownLock`, and `locksOf` never fails.
- `withdraw` checks the caller before the withdrawn flag. So a stranger who tries to withdraw
  an already-withdrawn lock gets `NotLockOwner`, not `AlreadyWithdrawn`.
- `extend` checks `MustExtend` before the future-time and cap checks.
- The deployment addresses, pool details and factory address are from on-chain reads on
  2026-09-27. They do not come from any file in `src/`. The repository's own deployment notes
  ([docs/DEPLOYMENT.md](DEPLOYMENT.md)) were written before deployment and contain no
  addresses.

---

Everything here is on the **Sepolia test network**. LOCK and Sepolia ETH have **no monetary
value**.
