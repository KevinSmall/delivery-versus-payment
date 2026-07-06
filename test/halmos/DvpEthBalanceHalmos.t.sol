// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {Test} from "forge-std/Test.sol";
import {DeliveryVersusPaymentV1} from "../../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {IDeliveryVersusPaymentV1} from "../../src/dvp/V1/IDeliveryVersusPaymentV1.sol";

/**
 * @title DvpEthBalanceHalmos
 * @notice A first, deliberately small Halmos (symbolic execution) test for DeliveryVersusPaymentV1.
 *
 * ---------------------------------------------------------------------------------------------------
 * How this differs from the existing Foundry invariant test (test/invariant/*)
 * ---------------------------------------------------------------------------------------------------
 * The Foundry invariant suite is *stateful fuzzing*: it fires many RANDOM sequences of handler calls
 * and, after each sequence, checks that a property (e.g. balance == total deposited) still holds. It
 * gives strong evidence, but never a proof — it only ever samples a finite number of concrete runs.
 *
 * Halmos is *symbolic execution*: instead of picking concrete numbers, it treats the inputs as
 * mathematical variables and explores EVERY reachable path, asking an SMT solver whether any input at
 * all can violate an assertion. If Halmos reports the test passes, it has effectively PROVEN the
 * assertion for all inputs within the modelled bounds — not just for the samples it happened to try.
 *
 * ---------------------------------------------------------------------------------------------------
 * The canonical Halmos pattern used here: a `check_` symbolic unit test
 * ---------------------------------------------------------------------------------------------------
 * The idiomatic way to use Halmos (as done by OpenZeppelin, Morpho, Snekmate, etc.) is to write a
 * function whose name starts with `check_`. Halmos automatically treats that function's PARAMETERS as
 * fresh symbolic values. We then:
 *   1. constrain the inputs to the "interesting" region with vm.assume(...),
 *   2. drive the contract through a single, real transaction,
 *   3. assert the property we care about.
 *
 * The property below is the per-function ("delta") expression of the balance-consistency invariant
 * `address(dvp).balance == sum of all recorded ETH deposits`. Proving the global sum over unbounded
 * mappings isn't something Halmos can enumerate directly, so we prove the local rule that makes the
 * global invariant true: a single ETH approval increases the contract balance by EXACTLY msg.value,
 * and records a deposit equal to EXACTLY that amount. If every state-changing function preserves its
 * own local rule, the global invariant is preserved too.
 *
 * ---------------------------------------------------------------------------------------------------
 * Why the scope is ETH-only, single-flow, non-auto-settled (kept intentionally simple)
 * ---------------------------------------------------------------------------------------------------
 * ETH flows use `token == address(0)`. On that path the contract performs NO external token/ERC-165
 * calls (createSettlement skips _isERC20/_isERC721, getSettlementPartyStatus skips token status), so
 * Halmos only has to reason about arithmetic and storage — no symbolic external calls. Keeping
 * isAutoSettled = false also avoids the execution path, which would `sendValue` to a symbolic address.
 * Later tests can relax each of these one at a time.
 */
contract DvpEthBalanceHalmos is SymTest, Test {
  DeliveryVersusPaymentV1 internal dvp;

  function setUp() public {
    // A fresh contract for every symbolic run: starting balance is 0, so the invariant holds trivially
    // at the start and we are proving that ONE approval preserves it.
    dvp = new DeliveryVersusPaymentV1();
  }

  /**
   * @notice Prove: for ALL amounts / parties / recipients / cutoffs, approving a single ETH flow
   *         increases the DVP contract's ETH balance by exactly `amount`, and the amount recorded as
   *         the party's deposit is exactly `amount`.
   *
   * @dev Because the name starts with `check_`, Halmos makes `amount`, `party`, `to` and `cutoff`
   *      symbolic. Every `vm.assume` below narrows those symbols to the values needed to reach a
   *      successful create + approve (any input that would revert is simply excluded from the proof —
   *      Halmos would otherwise flag the revert as an uninteresting "failure" path).
   *
   *      NOTE: Under `forge test` this function does nothing useful (its name isn't `test*`), so it is
   *      effectively inert for Foundry. It is meant to be run with the `halmos` tool. See README.md.
   */
  function check_approveEth_balanceMatchesDeposit(uint256 amount, address party, address to, uint128 cutoff)
    public
  {
    // --- Constrain the symbolic inputs to a valid, reachable scenario -------------------------------
    // createSettlement reverts on a zero from/to address, so exclude those.
    vm.assume(party != address(0));
    vm.assume(to != address(0));
    // The party must be a plain EOA-like address: not the DVP contract itself (its receive() reverts),
    // and not a precompile/cheatcode address. Excluding the DVP address keeps msg.sender sane.
    vm.assume(party != address(dvp));
    // For ETH/ERC-20 flows the contract rejects a zero amount (InvalidAmountOrId).
    vm.assume(amount > 0);
    // createSettlement and approveSettlements both revert once block.timestamp > cutoffDate, so require
    // the cutoff to still be in the future for this transaction.
    vm.assume(cutoff >= block.timestamp);

    // --- Build a single ETH flow: party sends `amount` wei to `to` ---------------------------------
    // token == address(0) marks this as an ETH transfer (no ERC-20/ERC-721 involved).
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = IDeliveryVersusPaymentV1.Flow({
      token: address(0),
      isNFT: false,
      from: party,
      to: to,
      amountOrId: amount
    });

    // isAutoSettled = false so approval does NOT trigger execution (we are only testing the deposit).
    uint256 id = dvp.createSettlement(flows, "halmos", cutoff, false);

    // Snapshot the balance before the approval. It is 0 on a fresh contract, but writing the assertion
    // as a delta (before + amount) keeps it valid even if the setup changes later.
    uint256 balanceBefore = address(dvp).balance;

    // --- Perform the approval as `party`, depositing exactly the required ETH ----------------------
    // vm.deal gives `party` enough ETH to cover the deposit; vm.prank makes the next call come from it.
    vm.deal(party, amount);
    uint256[] memory ids = new uint256[](1);
    ids[0] = id;
    vm.prank(party);
    dvp.approveSettlements{value: amount}(ids);

    // --- The properties we are proving --------------------------------------------------------------
    // 1) Delta: the contract's ETH balance rose by exactly the deposited amount (no more, no less).
    assertEq(address(dvp).balance, balanceBefore + amount, "balance must increase by exactly the deposit");

    // 2) Consistency: the amount the contract recorded as this party's deposit equals what was sent.
    //    getSettlementPartyStatus returns (isApproved, etherRequired, etherDeposited, tokenStatuses);
    //    for an ETH-only flow it makes no external token calls, so it is safe to call under Halmos.
    (, , uint256 etherDeposited, ) = dvp.getSettlementPartyStatus(id, party);
    assertEq(etherDeposited, amount, "recorded deposit must equal the amount sent");
  }
}
