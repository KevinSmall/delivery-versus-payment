// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";
import {DeliveryVersusPaymentV1} from "../../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {IDeliveryVersusPaymentV1} from "../../src/dvp/V1/IDeliveryVersusPaymentV1.sol";

/**
 * @title DvpUnboundedHalmos
 * @notice A DELIBERATELY UN-PROVABLE Halmos test, written to show how Halmos "fails" on unbounded
 *         problems. This is a teaching artifact — it is expected to emit a WARNING, not to pass cleanly.
 *
 * ---------------------------------------------------------------------------------------------------
 * The lesson: Halmos cannot reason about an unbounded number of loop iterations
 * ---------------------------------------------------------------------------------------------------
 * Symbolic execution unrolls loops. When a loop's iteration count is a SYMBOLIC value (not a compile
 * time constant), Halmos cannot unroll it forever, so it unrolls only up to the `--loop` bound
 * (this repo sets `loop = 4` in halmos.toml) and then STOPS. When it stops early it prints:
 *
 *     WARNING  ... loop unrolling bound 4 exceeded ...
 *
 * Crucially, Halmos may still report the test as [PASS] — but that "pass" is UNSOUND: it only checked
 * executions with up to 4 iterations. A counterexample needing 5+ iterations would go unnoticed. The
 * warning is Halmos telling you "I did not actually prove this for all inputs." Learning to treat that
 * warning as a failure is one of the most important habits when using Halmos.
 *
 * ---------------------------------------------------------------------------------------------------
 * Why THIS property is unbounded
 * ---------------------------------------------------------------------------------------------------
 * We try to prove the GLOBAL balance-consistency invariant directly: after `n` parties each create and
 * approve their own single-ETH-flow settlement, the contract's ETH balance equals the running sum of
 * every deposit. Because `n` is symbolic (a `check_` parameter), the driving loop below runs a symbolic
 * number of times — exactly the kind of unbounded loop Halmos can't fully explore. This is the same
 * "sum over an unbounded collection" that we noted is Halmos's blind spot (and Certora's home turf).
 *
 * Contrast with DvpEthBalanceHalmos.t.sol, which proves the *per-transaction* delta rule (a single,
 * bounded call) and therefore passes cleanly with no warning.
 *
 * ---------------------------------------------------------------------------------------------------
 * How to run it (it is intentionally EXCLUDED from the default `halmos` run)
 * ---------------------------------------------------------------------------------------------------
 * halmos.toml pins `contract = "DvpEthBalanceHalmos"`, so a plain `halmos` will not touch this file.
 * Run this one explicitly (the --contract flag overrides the toml):
 *
 *     halmos --contract DvpUnboundedHalmos
 *
 * Watch for the `loop unrolling bound ... exceeded` WARNING in the output. To see the bound change the
 * behaviour, try raising it (slower, still never a real proof): `halmos --contract DvpUnboundedHalmos --loop 8`.
 */
contract DvpUnboundedHalmos is SymTest, Test {
  DeliveryVersusPaymentV1 internal dvp;

  function setUp() public {
    dvp = new DeliveryVersusPaymentV1();
  }

  /**
   * @notice Attempt to prove `address(dvp).balance == sum of all deposits` over a SYMBOLIC, unbounded
   *         number `n` of settlements. Halmos cannot do this: the `for (i < n)` loop has a symbolic
   *         bound, so Halmos unrolls it only up to `--loop` and warns that it gave up early.
   *
   * @param n Symbolic number of settlements to create+approve. It is intentionally left unbounded
   *          (no `vm.assume(n <= K)`), which is precisely what defeats the solver.
   */
  function check_globalBalanceConsistency_unbounded(uint256 n) public {
    // A fixed party/recipient keeps the noise down; the unbounded thing we care about is `n`.
    address party = address(0xBEEF);
    address to = address(0xCAFE);

    // Give the settlements a far-future cutoff and assume "now" is before it, so create/approve succeed.
    uint128 cutoff = type(uint128).max;
    vm.assume(block.timestamp < cutoff);

    // We track the expected total deposit ourselves. For the invariant to hold, the contract's ETH
    // balance must equal this running sum after every iteration.
    uint256 expectedTotal = 0;

    // >>> The unbounded loop. `n` is symbolic, so this cannot be fully unrolled. <<<
    for (uint256 i = 0; i < n; i++) {
      // A fresh symbolic ETH amount for each settlement.
      uint256 amt = svm.createUint256("amt");
      // Keep each amount positive and small enough that the running total can't overflow within the
      // few iterations Halmos actually explores (overflow is a *different* failure mode; we want to
      // isolate the unbounded-loop one here).
      vm.assume(amt > 0 && amt < 1e18);

      // One ETH flow: party -> to for `amt` wei.
      IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
      flows[0] = IDeliveryVersusPaymentV1.Flow({
        token: address(0),
        isNFT: false,
        from: party,
        to: to,
        amountOrId: amt
      });

      uint256 id = dvp.createSettlement(flows, "unbounded", cutoff, false);

      // Fund `party` for exactly this deposit and approve as `party`.
      vm.deal(party, amt);
      uint256[] memory ids = new uint256[](1);
      ids[0] = id;
      vm.prank(party);
      dvp.approveSettlements{value: amt}(ids);

      expectedTotal += amt;
    }

    // The global invariant. Even if Halmos reports this as [PASS], the accompanying
    // "loop unrolling bound exceeded" WARNING means it was only verified for n <= --loop, NOT for all n.
    assertEq(address(dvp).balance, expectedTotal, "contract balance must equal the sum of all deposits");
  }
}
