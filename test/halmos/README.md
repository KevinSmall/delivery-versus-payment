# Halmos symbolic tests

This folder holds [Halmos](https://github.com/a16z/halmos) symbolic-execution tests for `DeliveryVersusPaymentV1`.

| File | Property proven |
|------|-----------------|
| `DvpEthBalanceHalmos.t.sol` | Approving a single ETH flow increases the contract's ETH balance by **exactly** `msg.value`, and records a deposit equal to **exactly** that amount — the per-function ("delta") form of the `constraint_eth_balance_consistency` invariant. |

Halmos tests use the canonical `check_` function-name prefix. Halmos automatically treats each
`check_` function's **parameters** as symbolic inputs; `vm.assume(...)` then narrows them to the
reachable, non-reverting scenario we want to reason about.

## Install Halmos

Halmos is a Python tool (it drives `forge build` under the hood and ships the Z3 solver as a
dependency). The cleanest install is via [pipx](https://pipx.pypa.io/), which puts `halmos` on your
PATH in its own isolated environment:

```bash
brew install pipx        # or: python3 -m pip install --user pipx
pipx install halmos
halmos --version
```

Alternatively, in a throwaway virtualenv:

```bash
python3 -m venv .venv-halmos
source .venv-halmos/bin/activate
pip install halmos
```

> Note: Halmos targets released Python versions. If your default `python3` is a very new release that
> Halmos hasn't pinned yet, install it under a supported Python (e.g. `pipx install --python
> python3.12 halmos`).

## Run it

From the repo root (the `halmos.toml` there configures everything, so no flags are needed):

```bash
halmos
```

You should see `check_approveEth_balanceMatchesDeposit` reported as passing. Useful variations:

```bash
halmos --function check_approveEth_balanceMatchesDeposit   # run just this test
halmos -vvvv                                               # verbose: show explored paths
halmos --statistics                                        # timing / solver-query counts
```

If a test **fails**, Halmos prints a concrete counterexample (specific values for `amount`, `party`,
`to`, `cutoff`) that violates the assertion — the symbolic equivalent of a failing fuzz case.
