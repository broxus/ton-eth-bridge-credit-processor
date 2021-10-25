pragma ton-solidity >= 0.39.0;

import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import "./structures/ICreditEventDataStructure.sol";

interface IReceiveTONsFromBridgeCallback is ICreditEventDataStructure {
    function onReceiveTONsFromBridgeCallback(CreditEventData decodedEventData) external;
}
