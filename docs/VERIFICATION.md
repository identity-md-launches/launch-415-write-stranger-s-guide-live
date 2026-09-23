# Local verification

Checked on 2026-09-23 using Forge 1.8.3 and solc 0.8.26 with the checked-in configuration.
These are contributor checks, not independent review or service attestation results.

A fresh directory containing only `src/`, `test/` (excluding scratch), `lib/`, `docs/`,
`scripts/`, `foundry.toml`, `.gitignore`, and `README.md` was built without copying any build
cache, `.imd` inputs, or Git metadata. Offline mode was enabled in the configuration.

| Check | Result |
| --- | --- |
| `forge build` | Passed from clean artifacts; 40 Solidity files compiled |
| `forge test` | 47 passed, 0 failed, 0 skipped |
| Fuzz tests | 3 tests, 256 cases each |
| Stateful conservation invariant | 128 sequences, depth 64, 8,192 handler calls, 0 reverts |
| `forge fmt --check` | Passed |
| `python3 scripts/export-abi.py --check` | Both exported ABIs matched compiler output |
| Vendored source integrity | Every source/license matched its recorded SHA-256 |
| Token runtime size | 1,771 bytes |
| Bank runtime size | 2,923 bytes |

The supplied protected suites were also copied unchanged into temporary scratch tests and run
against the compiled creation bytecode: all **8 passed**, none skipped. The project probe used
Sepolia chain ID 11155111, a local test factory, CREATE2 predictions calculated from these
artifacts, and bank constructor words `(predictedTokenAddress, 31536000)`. Both creation-code
and token-decimals inputs were provided, so the protected token suite did not skip its checks.
Temporary protected copies were removed afterwards; delivered tests have no `.imd` dependency.

Forge's timestamp lint reports the intentional `block.timestamp` comparisons required for the
lock boundary and cap. The on-chain-time assumption is documented in the README. No compiler
errors, failed tests, network-dependent tests, deployment transactions, or independent security
audit are represented by these results.
