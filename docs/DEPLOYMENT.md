# Contract-stage handoff

This source assignment is complete when the contracts, tests, ABI exports, and documentation
pass local offline checks. It does not generate `launch.json`, publish source, attest artifacts,
use wallet keys, broadcast transactions, or build the post-deployment frontend.

## Concrete deployment inputs

- Kind: `evm_project`; target: Sepolia chain ID `11155111`.
- Token artifact: `src/TimeLockToken.sol:TimeLockToken`, constructor arguments `[]`.
- Token metadata: name `Time Lock`, symbol `LOCK`, decimals `18`, total supply `1000000000000000000000000000`.
- One application, identifier `TimeLockBank`, artifact `src/TimeLockBank.sol:TimeLockBank`.
- Application constructor types: `address`, `uint256`; arguments in order: `$token`, `31536000`.
- Dependency order: token before bank; constructor value zero for both; no initializer.
- No `$owner` argument, owner assignment, manager, privileged beneficiary, or emergency operator.
- Compile with the checked-in Foundry configuration. Tests/mocks are never launch artifacts.

The token mints exclusively to its constructor caller. In the real launch that caller must be
ProjectFactory; deploying from an EOA changes the initial recipient. The bank constructor
stores only the supplied token and cap and does not consume or approve any factory balance.
`$token` must resolve to this launch's TimeLockToken. A different address, duration, constructor
value, or privileged source modification is a concrete review finding.

## Stage responsibilities

The manifest assignment describes these accepted artifacts in `launch.json` and carries the
constructor reference. The independent review inspects the implementation, tests, exported
ABIs, and final manifest together, including authorization and custody assumptions. Policy and
signed artifact linkage are service responsibilities; they are not application roles or
additional source constructors. The manifest is not present in this source-only deliverable.

The approved workflow pins Sepolia policy v5: 2% for this launch's accepted contributors, 8%
for eligible unique contributors in the preceding 12 hours, 80% LP, 10% treasury, one-hour
reward unlock, and a 20 ETH opening fully diluted valuation. Services freeze and combine
allocations; this repository contains no invented recipients or reward distribution logic.
The approved native-ETH pool has no hook, fee 3000, tick spacing 60, and token-only seeding.
The reference manifest initial price is `79228162514264337593543950336`; the pinned policy
derives and overrides the effective opening price. These policy details are handoff context,
not parameters or adjustable economics in TimeLockBank.

After review, services publish source, attest and admit the artifacts, deploy with the resolved
arguments, and verify code, supply, metadata, chain and immutable bank configuration. Services
provide actual deployment addresses, source and ABI linkage through the deployment handoff.
Only then should the separate frontend contribution use that data, verify its canonical ABI
hashes, and publish the approved minimal UI. There are no invented addresses or claimed
publication/deployment results here. No mainnet activity is part of this assignment.

## Operational responsibilities

Users retain their keys, approve LOCK, choose timestamps, pay gas, and submit withdrawals after
maturity. The bank needs no keeper or operator. An owner can extend a matured, unwithdrawn lock
but cannot shorten or transfer it. There is no administrator able to repair a mistaken deposit,
recover keys, change the token/cap, rescue surplus, pause withdrawals, or upgrade the bank.
Integration must use on-chain time and refreshed receipt state; see the README's custody limits.

Review should specifically confirm the deployment uses the supplied non-rebasing, fee-free
token. The bank cannot enforce the semantics of an arbitrary contract passed as its token.
Direct token donations remain surplus with no rescue mechanism. The fuzz equality invariant
therefore models only bank deposits/withdrawals, while the donation unit test covers surplus.

## After deployment

The launch has since been deployed on Sepolia (block 11761675). The observed addresses and
how to use them are in [SEPOLIA-GUIDE.md](SEPOLIA-GUIDE.md). The text above is the
pre-deployment handoff and has been left as it was.
