// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 *       _                                        _                 _
 *    __| |_   ___ __   ___  __ _ ___ _   _      | |_ _ __ __ _  __| | ___
 *   / _` \ \ / / '_ \ / _ \/ _` / __| | | |     | __| '__/ _` |/ _` |/ _ \
 *  | (_| |\ V /| |_) |  __/ (_| \__ \ |_| |  _  | |_| | | (_| | (_| |  __/
 *   \__,_| \_/ | .__/ \___|\__,_|___/\__, | (_)  \__|_|  \__,_|\__,_|\___|
 *              |_|                   |___/
 */

/**
 * @title IDeliveryVersusPaymentV1
 * @dev Interface sufficient for DVP Helper contract to interact with a DVP contract.
 * UI implemented at https://dvpeasy.trade.
 */
interface IDeliveryVersusPaymentV1 {
  /// @dev A Flow is a single transfer from one address to another
  struct Flow {
    /// @dev address of ERC-20, ERC-721 or zero address for ETH
    address token;
    /// @dev flag of token is NFT
    bool isNFT;
    /// @dev party from address
    address from;
    /// @dev party to address
    address to;
    /// @dev Stores amount for ERC-20, ETH or tokenId for ERC-721
    uint256 amountOrId;
  }

  /**
   * @dev Returns the last settlement id used.
   */
  function settlementIdCounter() external view returns (uint256);

  /**
   * @dev Retrieves settlement details.
   * @param settlementId The settlement ID.
   * @return settlementReference A free-text reference.
   * @return cutoffDate The settlement's cutoff date.
   * @return flows An array of flows contained in the settlement.
   * @return isSettled True if the settlement has been executed.
   * @return isAutoSettled True if the settlement is set for auto-settlement.
   */
  function getSettlement(uint256 settlementId)
    external
    view
    returns (
      string memory settlementReference,
      uint256 cutoffDate,
      Flow[] memory flows,
      bool isSettled,
      bool isAutoSettled
    );
}
