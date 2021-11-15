pragma ton-solidity >= 0.39.0;

import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';

interface ICreditProcessorReadyToProcessCallback {
    function onReadyToProcess(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration
    ) external;
}
