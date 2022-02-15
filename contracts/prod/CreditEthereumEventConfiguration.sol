pragma ton-solidity >= 0.57.0;
pragma AbiHeader expire;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-configuration-contracts/IEthereumEventConfiguration.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IProxy.sol';

import '../CreditProcessor.sol';
import './CreditTokenTransferEthereumEvent.sol';

import 'ton-eth-bridge-contracts/everscale/contracts/utils/TransferUtils.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/utils/ErrorCodes.sol';

import '@broxus/contracts/contracts/access/InternalOwner.sol';
import '@broxus/contracts/contracts/utils/CheckPubKey.sol';
import '@broxus/contracts/contracts/libraries/MsgFlag.sol';


contract CreditEthereumEventConfiguration is IEthereumEventConfiguration, IProxy, TransferUtils, InternalOwner, CheckPubKey {
    BasicConfiguration public static basicConfiguration;
    EthereumEventConfiguration public static networkConfiguration;

    TvmCell public meta;
    TvmCell creditProcessorCode;

    /// @param _owner Event configuration owner
    constructor(address _owner, TvmCell _meta, TvmCell _creditProcessorCode) public checkPubKey {
        tvm.accept();

        setOwnership(_owner);
        meta = _meta;
        creditProcessorCode = _creditProcessorCode;
    }

    /**
        @notice
            Set new configuration meta.
        @param _meta New configuration meta
    */
    function setMeta(TvmCell _meta) override onlyOwner cashBack external {
        meta = _meta;
    }

    function setCreditProcessorCode(TvmCell value) external onlyOwner {
        creditProcessorCode = value;
    }

    function getCreditProcessorCode() public view responsible returns(TvmCell) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} creditProcessorCode;
    }

    /// @dev Set end block number. Can be set only in case current value is 0.
    /// @param endBlockNumber End block number
    function setEndBlockNumber(
        uint32 endBlockNumber
    )
        override
        onlyOwner
        external
    {
        require(
            networkConfiguration.endBlockNumber == 0,
            ErrorCodes.END_BLOCK_NUMBER_ALREADY_SET
        );

        require(
            endBlockNumber >= networkConfiguration.startBlockNumber,
            ErrorCodes.TOO_LOW_END_BLOCK_NUMBER
        );

        networkConfiguration.endBlockNumber = endBlockNumber;
    }

    /// @dev Build initial data for event contract
    /// @dev Extends event vote data with configuration params
    /// @param eventVoteData Event vote data structure, passed by relay
    function buildEventInitData(
        IEthereumEvent.EthereumEventVoteData eventVoteData
    ) internal view returns(
        IEthereumEvent.EthereumEventInitData eventInitData
    ) {
        eventInitData.voteData = eventVoteData;

        eventInitData.configuration = address(this);
        eventInitData.staking = basicConfiguration.staking;
        eventInitData.chainId = networkConfiguration.chainId;
    }

    /// @dev Deploy event contract
    /// @param eventVoteData Event vote data
    function deployEvent(
        IEthereumEvent.EthereumEventVoteData eventVoteData
    )
        external
        override
        reserveBalance
    {
        require(msg.value >= basicConfiguration.eventInitialBalance, ErrorCodes.TOO_LOW_DEPLOY_VALUE);
        require(
            eventVoteData.eventBlockNumber >= networkConfiguration.startBlockNumber,
            ErrorCodes.EVENT_BLOCK_NUMBER_LESS_THAN_START
        );

        if (networkConfiguration.endBlockNumber != 0) {
            require(
                eventVoteData.eventBlockNumber <= networkConfiguration.endBlockNumber,
                ErrorCodes.EVENT_BLOCK_NUMBER_HIGHER_THAN_END
            );
        }

        IEthereumEvent.EthereumEventInitData eventInitData = buildEventInitData(eventVoteData);

        address eventContract = deriveEventAddress(eventVoteData);

        emit NewEventContract(eventContract);

        new CreditTokenTransferEthereumEvent{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            code: basicConfiguration.eventCode,
            pubkey: 0,
            varInit: {
                eventInitData: eventInitData
            }
        }(msg.sender, meta);
    }

    /// @dev Derive the Ethereum event contract address from it's init data
    /// @param eventVoteData Ethereum event vote data
    /// @return eventContract Address of the corresponding ethereum event contract
    function deriveEventAddress(
        IEthereumEvent.EthereumEventVoteData eventVoteData
    )
        override
        public
        view
        responsible
    returns(
        address eventContract
    ) {
        IEthereumEvent.EthereumEventInitData eventInitData = buildEventInitData(eventVoteData);

        TvmCell stateInit = tvm.buildStateInit({
            contr: CreditTokenTransferEthereumEvent,
            varInit: {
                eventInitData: eventInitData
            },
            pubkey: 0,
            code: basicConfiguration.eventCode
        });

        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} address(tvm.hash(stateInit));
    }

    /**
        @dev Get configuration details.
        @return _basicConfiguration Basic configuration init data
        @return _networkConfiguration Network specific configuration init data
    */
    function getDetails() override public view responsible returns(
        BasicConfiguration _basicConfiguration,
        EthereumEventConfiguration _networkConfiguration,
        TvmCell _meta
    ) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false}(
            basicConfiguration,
            networkConfiguration,
            meta
        );
    }

    /// @dev Get event configuration type
    /// @return _type Configuration type - Ethereum or TON
    function getType() override public pure responsible returns(EventType _type) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false} EventType.Ethereum;
    }

    function onEventConfirmed(
        IEthereumEvent.EthereumEventInitData eventInitData,
        address gasBackAddress
    ) override external reserveBalance {
        require(eventInitData.configuration == address(this));

        TvmCell stateInit = tvm.buildStateInit({
            contr: CreditTokenTransferEthereumEvent,
            varInit: {
                eventInitData: eventInitData
            },
            pubkey: 0,
            code: basicConfiguration.eventCode
        });

        address eventContract = address(tvm.hash(stateInit));

        require(eventContract == msg.sender);

        (uint128 amount_) = eventInitData.voteData.eventData.toSlice().decode(uint128);

        TvmCell processorStateInit = tvm.buildStateInit({
            contr: CreditProcessor,
            varInit: {
                eventVoteData: eventInitData.voteData,
                configuration: address(this)
            },
            pubkey: 0,
            code: creditProcessorCode
        });

        address processor = address(tvm.hash(processorStateInit));

        IProxy(processor).onEventConfirmed{ flag: 0, value: 0.1 ton }(eventInitData, gasBackAddress);

        TvmBuilder builder;
        builder.store(uint256(amount_));
        builder.store(int128(processor.wid));
        builder.store(processor.value);

        IEthereumEvent.EthereumEventInitData eventInitData_ = IEthereumEvent.EthereumEventInitData(
            IEthereumEvent.EthereumEventVoteData(
                eventInitData.voteData.eventTransaction,
                eventInitData.voteData.eventIndex,
                builder.toCell(),
                eventInitData.voteData.eventBlockNumber,
                eventInitData.voteData.eventBlock
            ),
            eventInitData.configuration,
            eventInitData.staking,
            eventInitData.chainId
        );

        IProxy(networkConfiguration.proxy).onEventConfirmed{
            flag: MsgFlag.ALL_NOT_RESERVED
        }(eventInitData_, gasBackAddress);
    }
}
