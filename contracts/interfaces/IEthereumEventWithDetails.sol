pragma ton-solidity >= 0.39.0;

import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IBasicEvent.sol';

interface IEthereumEventWithDetails {
    function getDetails() external view responsible returns (
        IEthereumEvent.EthereumEventInitData _eventInitData,
        IBasicEvent.Status _status,
        uint[] _confirms,
        uint[] _rejects,
        uint[] empty,
        uint128 balance,
        address _initializer,
        TvmCell _meta,
        uint32 _requiredVotes
    );
}
