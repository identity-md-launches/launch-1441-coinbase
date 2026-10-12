# Coinbase (COINBASE)

A fixed-supply ERC-20 token. The production contract is
[`src/CoinbaseToken.sol`](src/CoinbaseToken.sol), Solidity identifier `CoinbaseToken`.
It uses the vendored OpenZeppelin Contracts ERC-20 implementation.

## Token behavior and assumptions

| Property | Value |
| --- | --- |
| Name | `Coinbase` |
| Symbol | `COINBASE` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Initial recipient | The constructor's `msg.sender` |
| Constructor arguments | None (`[]`) |
| Native ETH required at deployment | `0` |
| Initialization / external settings | None |

The constructor mints the entire supply once and emits a single
`Transfer(address(0), deployer, supply)` event. There is no subsequent minting,
burning, ownership, pausing, blacklist, transfer tax, rebasing, proxy, upgrade, or
privileged balance movement. The deployer has the same transfer rights as every
other holder. The constructor makes no external calls and does not depend on
existing contracts, chain state, an oracle, a key, or an environment variable.

Transfers deliver the exact amount and return `true`. Invalid transfers revert
with OpenZeppelin ERC-20 custom errors. Zero-value transfers between nonzero
addresses are allowed and emit `Transfer`; self-transfers preserve balances.
Transfers to the zero address and approvals for the zero spender revert.

`approve` replaces an allowance, and `transferFrom` requires approval even when
the caller is the holder. Finite allowances decrease when spent; the standard
maximum-`uint256` allowance is treated as unlimited and does not decrease.
`approve` emits `Approval`. OpenZeppelin v5 does not emit another `Approval` when
`transferFrom` spends the allowance, so integrations should query `allowance()`.
Failed operations revert both balance and allowance changes.

ERC-20 transfers do not call recipient hooks. This contract does not accept
ordinary native ETH transfers and has no asset-recovery function. Tokens sent
to the token contract itself, or to another address unable to return them, can
become inaccessible. Forced native ETH also cannot be recovered.

## Build and checks

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. The target chain is Ethereum, chain ID 1.
No FFI, filesystem permissions, network forks, compiler binaries, submodules,
or external dependency installation are needed. All imported Solidity sources
are ordinary files under `lib/`. The offline verifier supplies the pinned
compiler; a fresh development machine must install that compiler first.

The tests use isolated deployments and no environment variables. Unit and fuzz
tests cover constructor minting, CREATE2 factory deployment, events, full/zero/
self transfers, allowances, revocation, exact distribution flows, failed-operation
rollback, invalid addresses, unauthorized spending, unsupported administrative
selectors, and the runtime opcode restrictions. Four fuzz properties run 512
cases each. Two stateful invariants each run 128 sequences of 64 actions, checking
constant supply, aggregate balances, and metadata across transfers, approvals,
delegated transfers, and deliberate failed transfers.

The distribution test models token movements for the factory, distributor,
pool manager, and trader. It does not deploy Uniswap or claim to test real pool
initialization, pricing, liquidity settlement, or swaps. The supplied protected
launch harness covers those integrations in the launch's separate environment.

## Deployment parameters and responsibilities

Deploy `src/CoinbaseToken.sol:CoinbaseToken` directly from its creation bytecode,
with no constructor arguments and no ETH. To inspect the compiled artifact:

```sh
forge inspect src/CoinbaseToken.sol:CoinbaseToken bytecode
forge inspect src/CoinbaseToken.sol:CoinbaseToken abi
```

On the specified launch, the factory deploys the token and receives all `10^27`
units. A direct wallet deployment instead credits that wallet; using an
intermediary credits the intermediary. The deploying address must be able to
transfer the tokens it receives. Do not deploy behind a proxy: the supply and
metadata are established by the constructor.

The launch infrastructure, outside this token, handles the stated allocations:
10% to its MerkleDistributor, 88% for pool seeding, and the remaining 2% to
`0x12a7aad083cef06fef7c295514b52fc8bc81960d`. These are factory operations,
not additional constructor recipients or token fees. Pool settings and the
10 ETH initial market capitalization belong to the separate launch manifest
and factory. No application contracts or launch manifest are delivered here.

### After launch

- The deployment operator checks the chain, contract address, exact metadata,
  total supply, mint event, and factory distributions against the approved launch
  manifest, then verifies the source with the compiler/settings above.
- No owner, initializer, setter, keeper, or follow-up token configuration exists.
- Holders control their transfers and approvals. Integrations should request
  only the allowance needed. To replace an existing nonzero allowance, revoke
  it to zero and confirm that transaction before granting a new allowance; a
  spender may use an outstanding allowance before a pending revocation lands.
- The launch operator is responsible for pool creation, seeding, distribution,
  and any independent security review before release. Local tests are not an
  independent audit. No deployment or transaction broadcast is performed here.

## Dependencies and review scope

[`dependencies.json`](dependencies.json) records pinned upstream commits and
SHA-256 hashes for every vendored dependency file:

- OpenZeppelin Contracts **v5.4.0**, commit
  `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0`: ERC-20 and its five required source/
  license files; MIT license at `lib/openzeppelin-contracts/LICENSE`.
- forge-std **v1.9.7**, commit
  `77041d2ce690e692d6e03cc812b57d1ddaa4d505`: test support source and MIT/Apache-2.0
  licenses under `lib/forge-std/`. This is a test-only dependency.

The pinned security reference was reviewed against this implementation. The
token has no external calls, callbacks, price or randomness inputs, signatures,
delegate calls, or privileged roles. Those features therefore need no oracle,
reentrancy guard, or configuration mechanism. Review focused on supply scaling,
the constructor recipient, transfer accounting, allowances, failure rollback,
and the absence of callable mint/burn/admin paths. The performed automated
checks are Foundry build, unit tests, fuzz tests, invariants, and formatting;
Slither, Mythril, and an independent audit were not run.
