// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {AssetToken} from "../src/mock/AssetToken.sol";
import {NFT} from "../src/mock/NFT.sol";

// Deploys mock tokens and mints to all 10 standard Anvil test accounts.
// Run against an Anvil fork: forge script script/DeployMocksToAnvil.s.sol --rpc-url http://localhost:8545 --broadcast
contract DeployMocksToAnvil is Script {
  // Standard Anvil test accounts (from "test test test ... junk" mnemonic)
  address[10] internal ANVIL_ACCOUNTS = [
    0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
    0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
    0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
    0x90F79bf6EB2c4f870365E785982E1f101E93b906,
    0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
    0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
    0x976EA74026E726554dB657fA54763abd0C3a0aa9,
    0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
    0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
    0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
  ];

  function run() external {
    // Use Anvil account 0's private key to broadcast
    uint256 deployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    vm.startBroadcast(deployerKey);

    AssetToken usdc = new AssetToken("USD Coin", "USDC", 6);
    AssetToken dai = new AssetToken("Dai Stablecoin", "DAI", 18);
    NFT nft = new NFT("Test NFT", "TNFT");

    // Mint tokens to all 10 Anvil accounts
    for (uint256 i = 0; i < ANVIL_ACCOUNTS.length; i++) {
      address account = ANVIL_ACCOUNTS[i];
      usdc.mint(account, 10_000 * 10 ** 6); // 10,000 USDC
      dai.mint(account, 10_000 * 10 ** 18); // 10,000 DAI
      // Mint 3 NFTs per account: tokenIds 0-2 for account 0, 3-5 for account 1, etc.
      nft.mint(account, i * 3);
      nft.mint(account, i * 3 + 1);
      nft.mint(account, i * 3 + 2);
    }

    vm.stopBroadcast();

    console.log("USDC deployed at:", address(usdc));
    console.log("DAI deployed at:", address(dai));
    console.log("NFT deployed at:", address(nft));
  }
}
