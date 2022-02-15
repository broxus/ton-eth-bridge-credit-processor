pragma ton-solidity >= 0.57.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/event-contracts/base/EthereumBaseEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IEventNotificationReceiver.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IProxy.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/utils/ErrorCodes.sol';

import '@broxus/contracts/contracts/libraries/MsgFlag.sol';

import '../libraries/EventDataDecoder.sol';
import '../interfaces/structures/ICreditEventDataStructure.sol';


/// @title Ethereum event
/// @dev Usually it deployed by CreditProcessor for specific event. Relays send their
/// rejects / confirms with external message directly into this contract.
/// In case enough confirmations is collected - callback is executed.
/// This implementation is used for cross chain token transfers with paying gas from transfer amount part
/// Different from basic example in eventData structure and is that tokens minted for CreditProcessor (not for user directly)
contract CreditTokenTransferEthereumEvent is ICreditEventDataStructure, EthereumBaseEvent {

    constructor(address _initializer, TvmCell _meta) EthereumBaseEvent(_initializer, _meta) public {}

    function afterSignatureCheck(TvmSlice body, TvmCell /*message*/) private inline view returns (TvmSlice) {
        body.decode(uint64, uint32);
        TvmSlice bodyCopy = body;
        uint32 functionId = body.decode(uint32);
        if (isExternalVoteCall(functionId)){
            require(votes[msg.pubkey()] == Vote.Empty, ErrorCodes.KEY_VOTE_NOT_EMPTY);
        }
        return bodyCopy;
    }

    function onInit() override internal {
        notifyEventStatusChanged();
    }

    function onConfirm() override internal {
        notifyEventStatusChanged();

        IProxy(eventInitData.configuration).onEventConfirmed{
            flag: MsgFlag.ALL_NOT_RESERVED
        }(eventInitData, initializer);
    }

    function onReject() override internal {
        notifyEventStatusChanged();
        transferAll(initializer);
    }

    function getOwner() private view returns(address) {
        (, int8 wid_, uint256 user_)  = eventInitData.voteData.eventData.toSlice().decode(uint128, int8, uint256);
        return address.makeAddrStd(wid_, user_);
    }

    /// @dev Get event details
    /// @return _eventInitData Init data
    /// @return _status Current event status
    /// @return _confirms List of relays who have confirmed event
    /// @return _rejects List of relays who have rejected event
    /// @return empty List of relays who have not voted
    /// @return balance This contract's balance
    /// @return _initializer Account who has deployed this contract
    /// @return _meta Meta data from the corresponding event configuration
    /// @return _requiredVotes The required amount of votes to confirm / reject event.
    /// Basically it's 2/3 + 1 relays for this round
    function getDetails() public view responsible returns (
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
        return {value: 0, flag: MsgFlag.REMAINING_GAS} (
            eventInitData,
            status,
            getVoters(Vote.Confirm),
            getVoters(Vote.Reject),
            getVoters(Vote.Empty),
            address(this).balance,
            initializer,
            meta,
            requiredVotes
        );
    }

    /*
        @dev Get decoded event data
        @returns ICreditEventDataStructure.CreditEventData
    */
    function getDecodedData() public responsible returns(CreditEventData) {
        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} EventDataDecoder.decode(eventInitData.voteData.eventData);
    }

    /// @dev Notify owner and initializer that event contract status has been changed
    /// @dev Used to easily collect all confirmed events by user's wallet
    function notifyEventStatusChanged() internal view {
        address owner = getOwner();

        if (owner.value != 0) {
            IEventNotificationReceiver(owner).notifyEventStatusChanged{flag: 0, bounce: false}(status);
        }

        if (initializer.value != 0 && initializer != owner) {
            IEventNotificationReceiver(initializer).notifyEventStatusChanged{flag: 0, bounce: false}(status);
        }
    }
}
