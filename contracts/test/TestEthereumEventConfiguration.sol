pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-configuration-contracts/IEthereumEventConfiguration.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/utils/ErrorCodes.sol';
import './TestEthereumEvent.sol';
import '@broxus/contracts/contracts/libraries/MsgFlag.sol';
import '../CreditProcessor.sol';
import "../interfaces/structures/ICreditEventDataStructure.sol";


contract TestEthereumEventConfiguration is IEthereumEventConfiguration, IProxy, ICreditEventDataStructure {

    BasicConfiguration static basicConfiguration;
    EthereumEventConfiguration static networkConfiguration;

    TvmCell meta;
    TvmCell creditProcessorCode;

    constructor() public {
        tvm.accept();
    }

    function setCreditProcessorCode(TvmCell value) external {
        tvm.accept();
        creditProcessorCode = value;
    }

    function setMeta(TvmCell value) override external {
        tvm.accept();
        meta = value;
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

    function deployEvent(
        IEthereumEvent.EthereumEventVoteData eventVoteData
    )
        external
        override
    {
        require(msg.value >= basicConfiguration.eventInitialBalance, ErrorCodes.TOO_LOW_DEPLOY_VALUE);
        require(
            eventVoteData.eventBlockNumber >= networkConfiguration.startBlockNumber,
            ErrorCodes.EVENT_BLOCK_NUMBER_LESS_THAN_START
        );

        tvm.rawReserve(address(this).balance - msg.value, 0);

        if (networkConfiguration.endBlockNumber != 0) {
            require(
                eventVoteData.eventBlockNumber <= networkConfiguration.endBlockNumber,
                ErrorCodes.EVENT_BLOCK_NUMBER_HIGHER_THAN_END
            );
        }

        IEthereumEvent.EthereumEventInitData eventInitData = buildEventInitData(eventVoteData);

        new TestEthereumEvent{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            code: basicConfiguration.eventCode,
            pubkey: 0,
            varInit: {
                eventInitData: eventInitData
            }
        }(msg.sender, meta);
    }

    function deriveEventAddress(
        IEthereumEvent.EthereumEventVoteData eventVoteData
    )
        override
        public
        view
        responsible
        returns(
            address eventContract
        )
    {
        IEthereumEvent.EthereumEventInitData eventInitData = buildEventInitData(eventVoteData);

        TvmCell stateInit = tvm.buildStateInit({
            contr: TestEthereumEvent,
            varInit: {
                eventInitData: eventInitData
            },
            pubkey: 0,
            code: basicConfiguration.eventCode
        });

        return {value: 0, flag: MsgFlag.REMAINING_GAS} address(tvm.hash(stateInit));
    }

    function getDetails()
        override
        external
        view
        responsible
        returns(
            BasicConfiguration _basicConfiguration,
            EthereumEventConfiguration _networkConfiguration,
            TvmCell _meta
        )
    {
        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} (basicConfiguration, networkConfiguration, meta);
    }

    function setEndBlockNumber(uint32 endBlockNumber) override external { }

    function getType() override external pure responsible returns(EventType _type) {
        return {value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS} EventType.Ethereum;
    }

    function onEventConfirmed(
        IEthereumEvent.EthereumEventInitData eventInitData,
        address gasBackAddress
    ) override external {
        require(eventInitData.configuration == address(this));
        tvm.rawReserve(address(this).balance - msg.value, 0);

        TvmCell stateInit = tvm.buildStateInit({
            contr: TestEthereumEvent,
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

    function encodeEventData(CreditEventData eventData) pure external returns (TvmCell) {
        require(eventData.amount > 0, 1001);
        require(eventData.tokenAmount < eventData.amount, 1002);
        require(eventData.swapType < 2, 1003);
        require(eventData.user.wid == eventData.creditor.wid &&
            eventData.recipient.wid == eventData.creditor.wid,
            1004);
        require(eventData.creditor.value != 0, 1005);
        require(eventData.user.value != 0, 1006);
        require(eventData.recipient.value != 0, 1007);
        require(eventData.slippage.numerator <= eventData.slippage.denominator, 1008);

        TvmBuilder l1;
        l1.store(eventData.amount);
        l1.store(eventData.user.wid);
        l1.store(eventData.user.value);
        l1.store(eventData.creditor.value);
        l1.store(eventData.recipient.value);

        TvmBuilder l2;
        l2.store(eventData.tokenAmount);
        l2.store(eventData.tonAmount);
        l2.store(eventData.swapType);
        l2.store(eventData.slippage.numerator);
        l2.store(eventData.slippage.denominator);

        l2.store(eventData.layer3);
        l1.storeRef(l2);

        return l1.toCell();
    }
}
