pragma ton-solidity >= 0.57.0;

import "../interfaces/structures/ICreditEventDataStructure.sol";
import "../interfaces/structures/INumeratorDenominatorStructure.sol";

/*

#layer1 = 904 bit
uint128 amount_,
int8 wid_,
uint256 user_,
uint256 creditor_,
uint256 recipient_,

#layer2 = 520 bit
uint128 tokenAmount_,
uint128 tonAmount_,
uint8 swapType_,
uint128 numerator;
uint128 denominator;

#layer 3
custom

*/

library EventDataDecoder {
    function isValid(TvmCell eventData) external returns(bool) {
        TvmSlice l1 = eventData.toSlice();
        return l1.hasNBitsAndRefs(904, 1) && l1.loadRefAsSlice().hasNBitsAndRefs(520, 1);
    }

    function decode(TvmCell eventData) external returns(ICreditEventDataStructure.CreditEventData) {
        TvmSlice l1 = eventData.toSlice();
        TvmSlice l2 = l1.loadRefAsSlice();

        (uint128 amount_, int8 wid_) = l1.decode(uint128, int8);

        return ICreditEventDataStructure.CreditEventData(
            amount_,
            address.makeAddrStd(wid_, l1.decode(uint256)),
            address.makeAddrStd(wid_, l1.decode(uint256)),
            address.makeAddrStd(wid_, l1.decode(uint256)),

            l2.decode(uint128),
            l2.decode(uint128),
            l2.decode(uint8),
            INumeratorDenominatorStructure.NumeratorDenominator(l2.decode(uint128), l2.decode(uint128)),

            l2.loadRef()
        );
    }
}
