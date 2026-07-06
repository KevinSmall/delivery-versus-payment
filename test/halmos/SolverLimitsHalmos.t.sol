// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";

/**
 * @title SolverLimitsHalmos
 * @notice A second kind of Halmos "failure" — one that is fundamentally different from the loop-bound
 *         warning in DvpUnboundedHalmos.
 *
 * ---------------------------------------------------------------------------------------------------
 * Two very different ways Halmos "fails"
 * ---------------------------------------------------------------------------------------------------
 *   1. INCOMPLETENESS (DvpUnboundedHalmos): Halmos explores paths fine, but there are unboundedly many
 *      of them (a symbolic loop count). It gives up after `--loop` iterations and WARNS. The SMT
 *      queries it does run are easy; there are just too many of them to cover.
 *
 *   2. SOLVER INTRACTABILITY (this file): there is exactly ONE path and ONE SMT query — but that query
 *      is mathematically brutal for the solver to decide. Halmos hands Z3 a formula and Z3 cannot
 *      answer it within the time budget, so the result comes back as `unknown` / times out. The
 *      problem isn't the number of paths; it's that the underlying decision problem is too hard.
 *
 * ---------------------------------------------------------------------------------------------------
 * Why THIS query is intractable: it is integer factorization in disguise
 * ---------------------------------------------------------------------------------------------------
 * SMT solvers are strong at LINEAR arithmetic but weak at NONLINEAR arithmetic (multiplying two
 * symbolic variables). Under the hood Halmos/Z3 "bit-blast" 256-bit values into ~256 boolean bits; a
 * symbolic-by-symbolic multiply becomes a huge multiplier circuit, and asking whether some product
 * equals a specific constant becomes: "find the factors of that constant."
 *
 * Below, N is a 240-bit semiprime (the product of two 120-bit primes). The assertion `x * y != N`
 * claims N has no factors in range. A counterexample DOES exist (x = p, y = q), so a solver that could
 * crack it would report [FAIL] with those factors. But finding them is integer factorization — the
 * problem much of public-key cryptography relies on being infeasible. Z3 will churn and time out.
 *
 * This is the lesson: a property can be trivially TRUE-or-FALSE to state, yet be a terrible fit for an
 * SMT solver. When you see Halmos time out (rather than warn), suspect nonlinear arithmetic,
 * division/modulo, or hashing — and reformulate the property to avoid handing the solver a search it
 * cannot win.
 *
 * ---------------------------------------------------------------------------------------------------
 * How to run it (EXCLUDED from the default `halmos` run so it can't hang your normal runs)
 * ---------------------------------------------------------------------------------------------------
 * halmos.toml pins `contract = "Dvp.*Halmos"`, which does NOT match this contract, so a plain `halmos`
 * skips it. Run it explicitly, and give the solver a finite timeout so you get a clean result instead
 * of an indefinite hang:
 *
 *     halmos --contract SolverLimitsHalmos --solver-timeout-assertion 8000
 *
 * (8000 = 8 seconds per assertion query.) Expect a timeout / `unknown` result rather than a proof.
 * Raising the timeout will not realistically help — factoring a 240-bit semiprime is out of reach.
 */
contract SolverLimitsHalmos is SymTest, Test {
  // N = p * q, where p and q are distinct 120-bit primes:
  //   p = 1320844556273916303787664879592486887
  //   q =  689657594431076366606287481381561411
  uint256 internal constant N = 910930479297251595197827907882851593317325192240035879097216048602717557;

  /**
   * @notice Claim: no two in-range integers multiply to N. This is FALSE (x = p, y = q is a witness),
   *         but proving/refuting it requires the solver to FACTOR N. It will time out instead.
   *
   * @param x,y Symbolic factors. Bounded below 2**128 so the 256-bit multiply never overflows — this
   *            keeps the query as clean *integer* factorization rather than modular arithmetic, and
   *            avoids overflow-revert branches that would muddy the demonstration.
   */
  function check_cannotFactorSemiprime(uint256 x, uint256 y) public {
    // Exclude the trivial factors 0 and 1, and keep both factors small enough that x*y can't overflow.
    vm.assume(x > 1 && y > 1);
    vm.assume(x < 2 ** 128 && y < 2 ** 128);

    // The nonlinear heart of the query. Negating this to search for a counterexample = "factor N".
    assert(x * y != N);
  }
}
