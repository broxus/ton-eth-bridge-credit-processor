pragma ton-solidity >= 0.57.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IEventNotificationReceiver.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IBasicEvent.sol';
import '../interfaces/IEthereumEventWithDetails.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IProxy.sol';
import '@broxus/contracts/contracts/libraries/MsgFlag.sol';


contract TestEthereumEvent is IEthereumEvent, IBasicEvent, IEthereumEventWithDetails {

    EthereumEventInitData static eventInitData;

    Status status;
    address initializer;
    TvmCell meta;

    constructor(address _initializer, TvmCell _meta) public {
        status = Status.Initializing;
        initializer = _initializer;
        meta = _meta;
        onInit();
    }

    function onInit() internal view {
        notifyEventStatusChanged();
    }

    function testConfirm() external {
        tvm.accept();
        status = Status.Confirmed;
        onConfirm();
    }

    function testReject() external {
        tvm.accept();
        status = Status.Rejected;
        onReject();
    }

    function onConfirm() internal view {
        notifyEventStatusChanged();

        IProxy(eventInitData.configuration).onEventConfirmed{
            flag: MsgFlag.ALL_NOT_RESERVED
        }(eventInitData, initializer);
    }

    function onReject() internal view {
        notifyEventStatusChanged();
        initializer.transfer({ flag: 129, value: 0 });
    }

    function notifyEventStatusChanged() internal view {
        (, int8 wid_, uint256 user_)  = eventInitData.voteData.eventData.toSlice().decode(uint128, int8, uint256);

        if (user_ != 0) {
            IEventNotificationReceiver(address.makeAddrStd(wid_, user_)).notifyEventStatusChanged{flag: 0, bounce: false}(status);
        }

        if (initializer.value != 0) {
            IEventNotificationReceiver(initializer).notifyEventStatusChanged{flag: 0, bounce: false}(status);
        }
    }

   function getDetails() override public view responsible returns (
        EthereumEventInitData _eventInitData,
        Status _status,
        uint[] _confirms,
        uint[] _rejects,
        uint[] empty,
        uint128 balance,
        address _initializer,
        TvmCell _meta,
        uint32 _requiredVotes
    ) {
        uint[] empty_arr;

        return {value: 0, flag: MsgFlag.REMAINING_GAS} (
            eventInitData,
            status,
            empty_arr,
            empty_arr,
            empty_arr,
            address(this).balance,
            initializer,
            meta,
            uint32(0)
        );
    }
}
