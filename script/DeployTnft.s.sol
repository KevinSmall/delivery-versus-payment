// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script} from "forge-std/Script.sol";
import {NFT} from "../src/mock/NFT.sol";

contract Deploy is Script {
  function run() external returns (NFT) {
    vm.startBroadcast();
    NFT nft = new NFT("Test NFT", "TNFT");
    vm.stopBroadcast();
    return nft;
  }
}
