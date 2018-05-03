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

import "./mixins/MExchangeCore.sol";
import "./mixins/MMatchOrders.sol";
import "./mixins/MSettlement.sol";
import "./mixins/MTransactions.sol";
import "../../utils/SafeMath/SafeMath.sol";
import "./LibOrder.sol";
import "./LibStatus.sol";
import "./LibPartialAmount.sol";
import "../../utils/LibBytes/LibBytes.sol";

contract MixinMatchOrders is
    SafeMath,
    LibBytes,
    LibStatus,
    LibOrder,
    LibPartialAmount,
    MExchangeCore,
    MMatchOrders,
    MSettlement,
    MTransactions
    {

    function validateMatchOrdersContextOrRevert(Order memory left, Order memory right)
        private
    {
        require(areBytesEqual(left.makerAssetData, right.takerAssetData));
        require(areBytesEqual(left.takerAssetData, right.makerAssetData));

        // Make sure there is a positive spread
        // TODO: Explain
        // TODO: SafeMath
        require(
            left.makerAssetAmount * right.makerAssetAmount >=
            left.takerAssetAmount * right.takerAssetAmount);
    }


    function getMatchedFillAmounts(Order memory left, Order memory right, uint8 leftStatus, uint8 rightStatus, uint256 leftFilledAmount, uint256 rightFilledAmount)
        private
        returns (uint8 status, MatchedOrderFillAmounts memory matchedFillOrderAmounts)
    {
        // The goal is for taker to obtain the maximum number of left maker
        // token.

        // The constraint can be either on the left or on the right. We need to
        // determine where it is.

        uint256 ratio = 0;


        uint256 rightTakerAssetAmountRemaining = safeSub(right.takerAssetAmount, rightFilledAmount);
        ratio = safeDiv(rightTakerAssetAmountRemaining, right.takerAssetAmount);
        uint256 rightMakerAssetAmountRemaining = safeMul(right.makerAssetAmount, ratio);

        uint256 leftTakerAssetAmountRemaining = safeSub(left.takerAssetAmount, leftFilledAmount);
        ratio = safeDiv(leftTakerAssetAmountRemaining, left.takerAssetAmount);
        uint256 leftMakerAssetAmountRemaining = safeMul(left.makerAssetAmount, ratio);


        // TODO: SafeMath
        //         if(safeMul(right.makerAssetAmount, rightTakerAssetAmountRemaining) < safeMul(right.takerAssetAmount, leftTakerAssetAmountRemaining))

        if(safeMul(leftTakerAssetAmountRemaining, right.takerAssetAmount) <= safeMul(rightTakerAssetAmountRemaining, right.makerAssetAmount))
        {
            // leftTakerAssetAmountRemaining is the constraint: maximally fill left
            (   status,
                matchedFillOrderAmounts.left
            ) = getFillAmounts(
                left,
                leftStatus,
                leftFilledAmount,
                leftTakerAssetAmountRemaining,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return;
            }

            // Compute how much we should fill right to satisfy
            // lefttakerAssetFilledAmount
            // TODO: Check if rounding is in the correct direction.
            uint256 rightFill = getPartialAmount(
                right.takerAssetAmount,
                right.makerAssetAmount,
                matchedFillOrderAmounts.left.takerAssetFilledAmount);

            // Compute right fill amounts
            (   status,
                matchedFillOrderAmounts.right
            ) = getFillAmounts(
                right,
                rightStatus,
                rightFilledAmount,
                rightFill,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return;
            }

            // Unfortunately, this is no longer exact and taker may end up
            // with some left.takerAssets. This will be a rounding error amount.
            // We should probably not bother and just give them to the makers.
            assert(matchedFillOrderAmounts.right.makerAssetFilledAmount >= matchedFillOrderAmounts.left.takerAssetFilledAmount);

            // TODO: Make sure the difference is neglible

        } else {
            // rightTakerAssetAmountRemaining is the constraint: maximally fill right
            (   status,
                matchedFillOrderAmounts.right
            ) = getFillAmounts(
                right,
                rightStatus,
                rightFilledAmount,
                rightTakerAssetAmountRemaining,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return;
            }

            // We now have rightmakerAssets to fill left with
            assert(matchedFillOrderAmounts.right.makerAssetFilledAmount <= /* remainingLeft ? */ leftTakerAssetAmountRemaining);

            // Fill left with all the right.makerAsset we received
            (   status,
                matchedFillOrderAmounts.left
            ) = getFillAmounts(
                left,
                leftStatus,
                leftFilledAmount,
                matchedFillOrderAmounts.right.makerAssetFilledAmount,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return;
            }

            // Taker should not have lefttakerAssets left
            assert(matchedFillOrderAmounts.right.makerAssetFilledAmount == matchedFillOrderAmounts.left.takerAssetFilledAmount);
        }
    }

    // Match two complementary orders that overlap.
    // The taker will end up with the maximum amount of left.makerAsset
    // Any right.makerAsset that taker would gain because of rounding are
    // transfered to right.
    function matchOrders(
        Order memory left,
        Order memory right,
        bytes leftSignature,
        bytes rightSignature)
        public
        returns (
            uint256 leftFilledAmount,
            uint256 rightFilledAmount)
    {
        // Get left status
        uint8 leftStatus;
        bytes32 leftOrderHash;
        (   leftStatus,
            leftOrderHash,
            leftFilledAmount
        ) = getOrderStatus(left);
        if(leftStatus != uint8(Status.ORDER_FILLABLE)) {
            emit ExchangeStatus(uint8(leftStatus), leftOrderHash);
            return;
        }

        // Get right status
        uint8 rightStatus;
        bytes32 rightOrderHash;
        (   rightStatus,
            rightOrderHash,
            rightFilledAmount
        ) = getOrderStatus(right);
        if(rightStatus != uint8(Status.ORDER_FILLABLE)) {
            emit ExchangeStatus(uint8(rightStatus), leftOrderHash);
            return;
        }

        // Fetch taker address
        address takerAddress = getCurrentContextAddress();

        // Either our context is valid or we revert
        validateMatchOrdersContextOrRevert(left, right);

        // Compute proportional fill amounts
        MatchedOrderFillAmounts memory matchedFillOrderAmounts;
        uint8 matchedFillAmountsStatus;
        (matchedFillAmountsStatus, matchedFillOrderAmounts) = getMatchedFillAmounts(left, right, leftStatus, rightStatus, leftFilledAmount, rightFilledAmount);
        if(matchedFillAmountsStatus != uint8(Status.SUCCESS)) {
            return;
        }

        // Settle matched orders
        settleMatchedOrders(left, right, matchedFillOrderAmounts, takerAddress);

        // TODO: THIS
        // Update exchange internal state
        updateFilledState(
            left,
            right.makerAddress,
            leftOrderHash,
            matchedFillOrderAmounts.left
        );
        updateFilledState(
            right,
            left.makerAddress,
            rightOrderHash,
            matchedFillOrderAmounts.right
        );
    }
}
