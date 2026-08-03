# Halmos symbolic tests

This folder holds [Halmos](https://github.com/a16z/halmos) symbolic-execution tests for `DeliveryVersusPaymentV1`.

| File | Run by default? | What it does |
|------|-----------------|--------------|
| `DvpEthBalanceHalmos.t.sol` | ✅ yes | **The proof.** Approving a single ETH flow increases the contract's ETH balance by **exactly** `msg.value`, and records a deposit equal to **exactly** that amount — the per-function ("delta") form of the `constraint_eth_balance_consistency` invariant. |
| `DvpUnboundedHalmos.t.sol` | ❌ no (teaching artifact) | Demonstrates Halmos's **loop-unrolling incompleteness**: a symbolic loop count makes the global sum unprovable, so Halmos passes but WARNS `loop unrolling bound exceeded` — an *unsound* pass. |
| `SolverLimitsHalmos.t.sol` | ❌ no (teaching artifact) | Demonstrates **solver intractability**: a single nonlinear query (semiprime factorization) that Z3 cannot decide within the time budget, so it times out. |

Scope: this suite currently proves exactly one property — the `constraint_eth_balance_consistency`
invariant, in its per-transaction delta form. `halmos.toml` pins `contract = "DvpEthBalanceHalmos"`, so
a plain `halmos` run (and CI) executes **only that sound proof**. The two teaching artifacts stay in the
repo to document how Halmos "fails", but are deliberately excluded from the default run — see below for
how to run them on demand.

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

Because `halmos.toml` is scoped to the sound proof, this runs **only** `DvpEthBalanceHalmos` and you
should see `check_approveEth_balanceMatchesDeposit` reported as passing.

You may also see lower-case `warning[block-timestamp]` lines before the results. Those come from
forge's build-time **linter** (Halmos drives `forge build` under the hood), *not* from Halmos itself —
they are informational and harmless. They are distinct from Halmos's own upper-case `WARNING` (e.g.
`loop unrolling bound exceeded`), which signals an *unsound* proof and which CI does fail on (see
below). Useful variations:

```bash
halmos --function check_approveEth_balanceMatchesDeposit   # run just this test
halmos -vvvv                                               # verbose: show explored paths
halmos --statistics                                        # timing / solver-query counts
```

If a test **fails**, Halmos prints a concrete counterexample (specific values for `amount`, `party`,
`to`, `cutoff`) that violates the assertion — the symbolic equivalent of a failing fuzz case.

## Running the teaching artifacts

These are excluded from the default run on purpose. Run them explicitly with `--contract`, which
overrides the `halmos.toml` scope:

```bash
halmos --contract DvpUnboundedHalmos                            # watch for the "loop unrolling bound exceeded" WARNING
halmos --contract SolverLimitsHalmos --solver-timeout-assertion 8000   # expect a timeout / unknown, not a proof
```

See the header comment in each file for the full explanation of the failure mode it illustrates.

## Continuous integration

CI runs Halmos as a dedicated `halmos` job in `.github/workflows/foundry-ci.yml`, separate from the
Forge build/test job. It installs Halmos under a supported Python and runs the same plain `halmos`
command, so CI verifies exactly the sound proof(s) scoped in `halmos.toml` — the teaching artifacts are
never run there.

Because Halmos exits successfully even when it prints a soundness `WARNING` (e.g. `loop unrolling bound
exceeded`), the CI step also **fails the job if any Halmos `WARNING` is emitted**. That keeps a green run
meaningful — it enforces the "treat a warning as a failure" discipline automatically, so an unsound proof
added to the scope later can't slip through. The guard is case-sensitive: it matches Halmos's upper-case
`WARNING` only, not forge's lower-case `warning[...]` build lints (e.g. `block-timestamp`), which are
unrelated informational output and are not failed on here.
