/*

  Copyright 2018 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/
pragma solidity ^0.4.21;
pragma experimental ABIEncoderV2;

import "../LibOrder.sol";
import "./MExchangeCore.sol";

contract MMatchOrders is LibOrder, MExchangeCore {

    struct MatchedOrderFillAmounts {
        FillResults left;
        FillResults right;
    }

    /// @dev Validates context for matchOrders. Succeeds or throws.
    /// @param left First order to match.
    /// @param right Second order to match.
    function validateMatchOrdersContextOrRevert(
        Order memory left,
        Order memory right)
        internal;


    /// @dev Validates context for matchOrders.
    ///      Each order is filled at their respective price point. However, the calculations are
    ///      carried out as though the orders are both being filled at the right order's price point.
    ///      The profit made by the left order goes to the taker (who matched the two orders).
    /// @param left First order to match.
    /// @param right Second order to match.
    /// @param leftStatus Order status of left order.
    /// @param rightStatus Order status of right order.
    /// @param leftFilledAmount Amount of left order already filled.
    /// @param rightFilledAmount Amount of right order already filled.
    /// @return status Return status of calculating fill amounts. Returns Status.SUCCESS on success.
    /// @return matchedFillOrderAmounts Amounts to fill left and right orders.
    function getMatchedFillAmounts(
        Order memory left,
        Order memory right,
        uint8 leftStatus,
        uint8 rightStatus,
        uint256 leftFilledAmount,
        uint256 rightFilledAmount)
        internal
        returns (
            uint8 status,
            MatchedOrderFillAmounts memory matchedFillOrderAmounts);

    /// @dev Match two complementary orders that have a positive spread.
    ///      Each order is filled at their respective price point. However, the calculations are
    ///      carried out as though the orders are both being filled at the right order's price point.
    ///      The profit made by the left order goes to the taker (who matched the two orders).
    /// @param left First order to match.
    /// @param right Second order to match.
    /// @param leftSignature Proof that order was created by the left maker.
    /// @param rightSignature Proof that order was created by the right maker.
    /// @return leftFillResults Amounts filled and fees paid by maker and taker of left order.
    /// @return leftFillResults Amounts filled and fees paid by maker and taker of right order.
    function matchOrders(
        Order memory left,
        Order memory right,
        bytes leftSignature,
        bytes rightSignature)
        public
        returns (
            MatchedOrderFillAmounts memory matchedFillOrderAmounts);
}
