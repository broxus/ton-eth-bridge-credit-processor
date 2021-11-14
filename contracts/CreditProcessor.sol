pragma ton-solidity >= 0.39.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import '../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IBasicEvent.sol';
import '../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import '../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-configuration-contracts/IEthereumEventConfiguration.sol';
import '../node_modules/bridge/free-ton/contracts/bridge/interfaces/IProxyTokenTransferConfigurable.sol';
import "../node_modules/bridge/free-ton/contracts/bridge/interfaces/IEventNotificationReceiver.sol";
import "../node_modules/bridge/free-ton/contracts/bridge/interfaces/IProxy.sol";

import './interfaces/tokens/IRootTokenContract.sol';
import './interfaces/tokens/ITONTokenWallet.sol';

import '../node_modules/dex/contracts/interfaces/IDexRoot.sol';
import '../node_modules/dex/contracts/interfaces/IDexPair.sol';
import "../node_modules/dex/contracts/libraries/OperationTypes.sol";

import './interfaces/IEthereumEventWithDetails.sol';
import "./interfaces/ICreditFactory.sol";
import "./interfaces/ICreditProcessor.sol";
import "./interfaces/ICreditProcessorReadyToProcessCallback.sol";
import "./interfaces/IReceiveTONsFromBridgeCallback.sol";

import './Addresses.sol';

import './libraries/MessageFlags.sol';
import './libraries/CreditProcessorErrorCodes.sol';
import "./libraries/EventDataDecoder.sol";
import './libraries/OperationStatus.sol';
import './libraries/Gas.sol';


contract CreditProcessor is ICreditProcessor, Addresses {

    // init data
    IEthereumEvent.EthereumEventVoteData static eventVoteData;
    address static configuration;

    // decoded event data
    CreditEventData eventData;
    uint128 amount;
    NumeratorDenominator slippage_;
    
    CreditProcessorStatus state;
    CreditProcessorStatus prevState;
    IBasicEvent.Status eventState;

    // init info
    address deployer;
    uint128 debt;
    uint128 fee_;

    // data from responsible
    address eventAddress;
    address eventProxy;
    uint128 eventInitialBalance;
    address tokenRoot;
    address tokenWallet;
    address wtonWallet;
    address dexPair;
    address dexVault;

    uint64 swapAttempt;
    uint128 swapAmount;
    uint128 unwrapAmount;

    modifier onlyState(CreditProcessorStatus state_) {
        require (state == state_, CreditProcessorErrorCodes.WRONG_STATE);
        _;
    }

    modifier onlyDeployer() {
        require (msg.sender == deployer, CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    modifier onlyDeployerOrCreditor() {
        require (msg.sender == deployer || msg.sender == eventData.creditor, CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    modifier onlyCreditor() {
        require (msg.sender == eventData.creditor, CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    modifier onlyUser() {
        require (msg.sender == eventData.user, CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    modifier onlyUserOrCreditor() {
        require (msg.sender == eventData.user || msg.sender == eventData.creditor, CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    modifier onlyUserOrCreditorOrRecipient() {
        require (
            msg.sender == eventData.user || msg.sender == eventData.creditor || msg.sender == eventData.recipient,
            CreditProcessorErrorCodes.NOT_PERMITTED);
        _;
    }

    constructor(uint128 fee, address deployer_) public {

        if (msg.value >= (Gas.CREDIT_BODY - Gas.DEPLOY_PROCESSOR - Gas.MAX_FWD_FEE) &&
            msg.sender.value != 0 && tvm.pubkey() == 0 &&
            EventDataDecoder.isValid(eventVoteData.eventData) &&
            configuration.value != 0)
        {
            eventData = EventDataDecoder.decode(eventVoteData.eventData);

            deployer = (msg.sender == eventData.creditor ? deployer_ : msg.sender);

            if (deployer == eventData.creditor) {
                fee_ = fee;
                debt = math.max(Gas.CREDIT_BODY, msg.value) + fee_;
            }

            amount = eventData.amount;
            slippage_ = eventData.slippage;

            if ((deployer == eventData.creditor || deployer == eventData.user) &&
                eventData.user.value != 0 &&
                eventData.creditor.value != 0 &&
                eventData.recipient.value != 0 &&
                // либо число токенов на выходе меньше чем на входе
                (eventData.tokenAmount < amount ||
                 // либо равно, но тогда это происходит не в кредит, а за счет пользователя или третьей стороны и не предполагает swap и/или unwrap
                 (eventData.tokenAmount == amount && debt == 0 && eventData.tonAmount == 0)) &&
                eventData.swapType < 2 &&
                slippage_.denominator > slippage_.numerator) {

                state = CreditProcessorStatus.Created;

                IEthereumEventConfiguration(configuration).deriveEventAddress{
                    value: Gas.DERIVE_EVENT_ADDRESS,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onEventAddress
                }(eventVoteData);

                IEthereumEventConfiguration(configuration).getDetails{
                    value: Gas.GET_EVENT_CONFIG_DETAILS,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onEventConfigDetails
                }();

                IRootTokenContract(WTON_ROOT)
                    .deployEmptyWallet {
                        value: Gas.DEPLOY_EMPTY_WALLET_VALUE,
                        flag: MessageFlags.SENDER_PAYS_FEES
                    }(
                        Gas.DEPLOY_EMPTY_WALLET_GRAMS,  // deploy_grams
                        0,                              // wallet_public_key
                        address(this),                  // owner_address
                        address(this)                   // gas_back_address
                    );

                IRootTokenContract(WTON_ROOT)
                    .getWalletAddress{
                        value: Gas.GET_WALLET_ADDRESS_VALUE,
                        flag: MessageFlags.SENDER_PAYS_FEES,
                        callback: CreditProcessor.onWtonWallet
                    }(
                        0,                              // wallet_public_key_
                        address(this)                   // owner_address_
                    );

                emit CreditProcessorDeployed(_buildDetails());

            } else {
                msg.sender.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.DESTROY_IF_ZERO, bounce: false});
            }
        } else {
            msg.sender.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.DESTROY_IF_ZERO, bounce: false});
        }
    }

    function _changeState(CreditProcessorStatus newState) private {
        prevState = state;
        state = newState;
        emit CreditProcessorStateChanged(prevState, newState, _buildDetails());
    }

    function _buildDetails() private view returns(CreditProcessorDetails) {
        return CreditProcessorDetails(
            eventVoteData,
            configuration,

            amount,
            slippage_,

            DEX_ROOT,
            WTON_VAULT,
            WTON_ROOT,

            state,
            eventState,

            deployer,
            debt,
            fee_,

            eventAddress,
            tokenRoot,
            tokenWallet,
            wtonWallet,
            dexPair,
            dexVault,

            swapAttempt,
            swapAmount,
            unwrapAmount
        );
    }

    function getDetails() override external view responsible returns(CreditProcessorDetails) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } _buildDetails();
    }

    function getCreditEventData() override external view responsible returns(CreditEventData) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } eventData;
    }

    function deriveEventAddress()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= Gas.DERIVE_EVENT_ADDRESS + Gas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(eventAddress.value == 0, CreditProcessorErrorCodes.NON_EMPTY_EVENT_ADDRESS);
        require(configuration.value != 0, CreditProcessorErrorCodes.EMPTY_CONFIG_ADDRESS);

        emit DeriveEventAddressCalled(msg.sender);
        IEthereumEventConfiguration(configuration).deriveEventAddress{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onEventAddress
        }(eventVoteData);
    }

    function onEventAddress(address value)
        external
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.sender.value != 0 && msg.sender == configuration, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(eventAddress.value == 0, CreditProcessorErrorCodes.NON_EMPTY_EVENT_ADDRESS);

        tvm.accept();

        eventAddress = value;

        checkAddressesDerived();
    }

    function checkAddressesDerived() private {
        if (eventAddress.value != 0 && eventInitialBalance != 0 &&
            tokenRoot.value != 0 && tokenWallet.value != 0 && wtonWallet.value != 0 &&
            ((dexPair.value != 0 && dexVault.value != 0) || tokenWallet == wtonWallet))
        {
            if (address(this).balance >= eventInitialBalance + Gas.MAX_FWD_FEE) {
                IEthereumEventConfiguration(configuration).deployEvent{
                    value: eventInitialBalance,
                    flag: MessageFlags.SENDER_PAYS_FEES
                }(eventVoteData);

                _changeState(CreditProcessorStatus.EventDeployInProgress);
            } else {
                _changeState(CreditProcessorStatus.EventNotDeployed);
            }
        }
    }

    function deployEvent()
        override
        external
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.EventNotDeployed)
    {
        require(msg.value >= eventInitialBalance + Gas.MAX_FWD_FEE);
        emit DeployEventCalled(msg.sender);
        _changeState(CreditProcessorStatus.EventDeployInProgress);

        IEthereumEventConfiguration(configuration).deployEvent{
            flag: MessageFlags.REMAINING_GAS,
            value: 0
        }(eventVoteData);
    }

    function requestEventConfigDetails()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= Gas.GET_EVENT_CONFIG_DETAILS + Gas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(eventProxy.value == 0, CreditProcessorErrorCodes.NON_EMPTY_PROXY_ADDRESS);
        require(configuration.value != 0, CreditProcessorErrorCodes.EMPTY_CONFIG_ADDRESS);

        emit RequestEventConfigDetailsCalled(msg.sender);
        IEthereumEventConfiguration(configuration).getDetails{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onEventConfigDetails
        }();
    }

    function onEventConfigDetails(
        IEthereumEventConfiguration.BasicConfiguration _basicConfiguration,
        IEthereumEventConfiguration.EthereumEventConfiguration _networkConfiguration,
        TvmCell /* _meta */
    ) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender.value != 0 && msg.sender == configuration, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(eventProxy.value == 0, CreditProcessorErrorCodes.NON_EMPTY_PROXY_ADDRESS);

        tvm.accept();

        eventProxy = _networkConfiguration.proxy;
        eventInitialBalance = _basicConfiguration.eventInitialBalance;

        IProxyTokenTransferConfigurable(eventProxy).getConfiguration{
            value: Gas.GET_PROXY_CONFIG,
            flag: MessageFlags.SENDER_PAYS_FEES,
            callback: CreditProcessor.onTokenEventProxyConfig
        }();
    }

    function requestTokenEventProxyConfig()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= Gas.GET_PROXY_CONFIG + Gas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot.value == 0, CreditProcessorErrorCodes.NON_EMPTY_TOKEN_ROOT);
        require(eventProxy.value != 0, CreditProcessorErrorCodes.EMPTY_PROXY_ADDRESS);

        emit RequestTokenEventProxyConfigCalled(msg.sender);
        IProxyTokenTransferConfigurable(eventProxy).getConfiguration{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onTokenEventProxyConfig
        }();
    }

    function requestDexVault()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= Gas.GET_DEX_VAULT + Gas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot != WTON_ROOT, CreditProcessorErrorCodes.TOKEN_IS_WTON);
        require(tokenRoot.value != 0, CreditProcessorErrorCodes.EMPTY_TOKEN_ROOT);
        require(dexVault.value == 0, CreditProcessorErrorCodes.NON_EMPTY_DEX_VAULT);

        emit RequestDexVaultCalled(msg.sender);
        IDexRoot(DEX_ROOT).getVault{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onDexVault
        }();
    }

    function requestDexPairAddress()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(address(this).balance >= Gas.GET_DEX_PAIR_ADDRESS + Gas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot != WTON_ROOT, CreditProcessorErrorCodes.TOKEN_IS_WTON);
        require(tokenRoot.value != 0, CreditProcessorErrorCodes.EMPTY_TOKEN_ROOT);
        require(dexPair.value == 0, CreditProcessorErrorCodes.NON_EMPTY_DEX_PAIR);

        emit RequestDexPairAddressCalled(msg.sender);
        IDexRoot(DEX_ROOT).getExpectedPairAddress{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onPairAddress
        }(WTON_ROOT, tokenRoot);
    }

    function onTokenEventProxyConfig(IProxyTokenTransferConfigurable.Configuration value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender.value != 0 && msg.sender == eventProxy, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(tokenRoot.value == 0, CreditProcessorErrorCodes.NON_EMPTY_TOKEN_ROOT);

        tvm.accept();

        tokenRoot = value.tokenRoot;

        if (tokenRoot == WTON_ROOT) {
            tokenWallet = wtonWallet;
        } else {
            IDexRoot(DEX_ROOT)
                .getVault{
                    value: Gas.GET_DEX_VAULT,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onDexVault
                }();

            IDexRoot(DEX_ROOT).getExpectedPairAddress{
                value: Gas.GET_DEX_PAIR_ADDRESS,
                flag: MessageFlags.SENDER_PAYS_FEES,
                callback: CreditProcessor.onPairAddress
            }(WTON_ROOT, tokenRoot);

            IRootTokenContract(tokenRoot)
                .deployEmptyWallet {
                    value: Gas.DEPLOY_EMPTY_WALLET_VALUE,
                    flag: MessageFlags.SENDER_PAYS_FEES
                }(
                    Gas.DEPLOY_EMPTY_WALLET_GRAMS,  // deploy_grams
                    0,                              // wallet_public_key
                    address(this),                  // owner_address
                    address(this)                   // gas_back_address
                );

            IRootTokenContract(tokenRoot)
                .getWalletAddress{
                    value: Gas.GET_WALLET_ADDRESS_VALUE,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onTokenWallet
                }(
                    0,                              // wallet_public_key_
                    address(this)                   // owner_address_
                );
        }
    }

    function onWtonWallet(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender == WTON_ROOT, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        wtonWallet = value;

        if (WTON_ROOT == tokenRoot) {
            tokenWallet = value;
        }

        ITONTokenWallet(value).setReceiveCallback{ value: Gas.SET_RECEIVE_CALLBACK_VALUE, flag: MessageFlags.SENDER_PAYS_FEES }(address(this), true);
        ITONTokenWallet(value).setBouncedCallback{ value: Gas.SET_BOUNCED_CALLBACK_VALUE, flag: MessageFlags.SENDER_PAYS_FEES }(address(this));

        checkAddressesDerived();
    }

    function onTokenWallet(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender.value != 0 && msg.sender == tokenRoot, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        tokenWallet = value;

        ITONTokenWallet(value).setReceiveCallback{ value: Gas.SET_RECEIVE_CALLBACK_VALUE, flag: MessageFlags.SENDER_PAYS_FEES }(address(this), true);
        ITONTokenWallet(value).setBouncedCallback{ value: Gas.SET_BOUNCED_CALLBACK_VALUE, flag: MessageFlags.SENDER_PAYS_FEES }(address(this));

        checkAddressesDerived();
    }

    function onDexVault(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender == DEX_ROOT, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(dexVault.value == 0, CreditProcessorErrorCodes.NON_EMPTY_DEX_VAULT);

        tvm.accept();

        dexVault = value;

        checkAddressesDerived();
    }

    function onPairAddress(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender == DEX_ROOT, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        dexPair = value;

        checkAddressesDerived();
    }

    function notifyEventStatusChanged(IBasicEvent.Status eventState_) override external {
        require(msg.sender.value != 0 && msg.sender == eventAddress, CreditProcessorErrorCodes.NOT_PERMITTED);
        tvm.accept();

        eventState = eventState_;

        if(state == CreditProcessorStatus.EventDeployInProgress ||
           state == CreditProcessorStatus.EventNotDeployed)
        {
            if (eventState == IBasicEvent.Status.Confirmed) {
                _changeState(CreditProcessorStatus.EventConfirmed);
            } else if(eventState == IBasicEvent.Status.Rejected) {
                _changeState(CreditProcessorStatus.EventRejected);
            }
        }
    }

    function checkEventStatus()
        override
        external
        onlyUserOrCreditor
    {
        require(state == CreditProcessorStatus.EventDeployInProgress ||
                state == CreditProcessorStatus.EventNotDeployed,
                CreditProcessorErrorCodes.WRONG_STATE);

        emit CheckEventStatusCalled(msg.sender);

        if (eventState == IBasicEvent.Status.Confirmed) {
            _changeState(CreditProcessorStatus.EventConfirmed);
        } else if(eventState == IBasicEvent.Status.Rejected) {
            _changeState(CreditProcessorStatus.EventRejected);
        } else if(eventAddress.value != 0) {
            IEthereumEventWithDetails(eventAddress).getDetails{
                value: 0,
                flag: MessageFlags.REMAINING_GAS,
                callback: CreditProcessor.onEthereumEventDetails
            }();
        } else {
            msg.sender.transfer({value: 0, flag: MessageFlags.REMAINING_GAS + MessageFlags.IGNORE_ERRORS, bounce: false});
        }
    }

    function onEthereumEventDetails(
        IEthereumEvent.EthereumEventInitData /* _eventInitData */,
        IBasicEvent.Status _status,
        uint[] /* _confirms */,
        uint[] /* _rejects */,
        uint[] /* empty */,
        uint128 /* balance */,
        address /* _initializer */,
        TvmCell /* _meta */,
        uint32  /* _requiredVotes */
    ) external {
        require(state == CreditProcessorStatus.EventDeployInProgress ||
                state == CreditProcessorStatus.EventNotDeployed,
                CreditProcessorErrorCodes.WRONG_STATE);
        require(eventAddress.value != 0, CreditProcessorErrorCodes.EMPTY_EVENT_ADDRESS);
        require(msg.sender == eventAddress, CreditProcessorErrorCodes.NOT_PERMITTED);

        eventState = _status;

        if (_status == IBasicEvent.Status.Confirmed) {
            _changeState(CreditProcessorStatus.EventConfirmed);
        } else if (_status == IBasicEvent.Status.Rejected) {
            _changeState(CreditProcessorStatus.EventRejected);
        }

    }

    function broxusBridgeCallback(
        IEthereumEvent.EthereumEventInitData eventInitData_,
        address /* gasBackAddress */
    ) override external {
        require(state == CreditProcessorStatus.EventDeployInProgress ||
                state == CreditProcessorStatus.EventNotDeployed ||
                state == CreditProcessorStatus.EventConfirmed,
                CreditProcessorErrorCodes.WRONG_STATE);
        require(configuration == msg.sender && msg.sender.value != 0, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(eventInitData_.configuration == msg.sender, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        eventState = IBasicEvent.Status.Confirmed;

        if (state != CreditProcessorStatus.EventConfirmed) {
            _changeState(CreditProcessorStatus.EventConfirmed);
        }

        ICreditProcessorReadyToProcessCallback(deployer).onReadyToProcess{
            value: Gas.READY_TO_PROCESS_CALLBACK_VALUE,
            flag: MessageFlags.SENDER_PAYS_FEES,
            bounce: false
        }(eventVoteData, configuration);
    }

    function process() override external onlyState(CreditProcessorStatus.EventConfirmed) {
        bool payingDebtsBeforeProcess = debt == 0 ? msg.sender == eventData.user : (
                (msg.sender == eventData.recipient || msg.sender == eventData.user) &&
                msg.value > debt &&
                address(this).balance > debt + Gas.CREDIT_BODY
            );
        require(
            msg.sender == deployer || msg.sender == eventData.creditor || payingDebtsBeforeProcess,
            CreditProcessorErrorCodes.NOT_PERMITTED
        );

        tvm.accept();

        if (debt > 0 && payingDebtsBeforeProcess) {
            deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
            debt = 0;
        }

        emit ProcessCalled(msg.sender);

        ITONTokenWallet(tokenWallet).balance{
            value: Gas.CHECK_BALANCE,
            flag: MessageFlags.SENDER_PAYS_FEES,
            callback: CreditProcessor.onTokenWalletBalance
        }();

        _changeState(CreditProcessorStatus.CheckingAmount);
    }

    function payDebtForUser() override external {
        require(CreditProcessorStatus.EventConfirmed == state ||
                CreditProcessorStatus.SwapFailed == state ||
                CreditProcessorStatus.SwapUnknown == state ||
                CreditProcessorStatus.UnwrapFailed == state ||
                CreditProcessorStatus.ProcessRequiresGas == state, CreditProcessorErrorCodes.WRONG_STATE);
        require(msg.value > debt &&
                address(this).balance > debt + Gas.CREDIT_BODY, CreditProcessorErrorCodes.LOW_GAS);
        require(debt > 0, CreditProcessorErrorCodes.HAS_NOT_DEBT);

        deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
        debt = 0;
    }

    function cancel() override external onlyUser {
        require(CreditProcessorStatus.EventConfirmed == state ||
                CreditProcessorStatus.SwapFailed == state ||
                CreditProcessorStatus.SwapUnknown == state ||
                CreditProcessorStatus.UnwrapFailed == state ||
                CreditProcessorStatus.ProcessRequiresGas == state, CreditProcessorErrorCodes.WRONG_STATE);

        if (debt > 0) {
            require(address(this).balance >= debt + Gas.MAX_FWD_FEE + Gas.MIN_BALANCE, CreditProcessorErrorCodes.LOW_GAS);
            tvm.accept();
            deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
            debt = 0;
        } else {
            tvm.accept();
        }
        emit CancelCalled(msg.sender);
        _changeState(CreditProcessorStatus.Cancelled);
    }

    function proxyTransferToRecipient(
        address tokenWallet_,
        uint128 gasValue,
        uint128 amount_,
        address recipient,
        uint128 deployGrams,
        address gasBackAddress,
        bool    notifyReceiver,
        TvmCell payload
    ) override external view onlyUser {
        require(CreditProcessorStatus.Cancelled == state ||
                CreditProcessorStatus.Processed == state,
            CreditProcessorErrorCodes.WRONG_STATE);
        require(
            address(this).balance >=
                Gas.TRANSFER_TO_RECIPIENT_VALUE + Gas.MAX_FWD_FEE + Gas.MIN_BALANCE,
            CreditProcessorErrorCodes.LOW_GAS
        );
        require(
            gasValue >= Gas.TRANSFER_TO_RECIPIENT_VALUE + deployGrams,
            CreditProcessorErrorCodes.LOW_GAS
        );

        tvm.accept();

        ITONTokenWallet(tokenWallet_).transferToRecipient{
            value: gasValue,
            flag: MessageFlags.SENDER_PAYS_FEES
        }(
            0,                          // recipient_public_key
            recipient,                  // recipient_address
            amount_,                    // amount
            deployGrams,                // deploy_grams
            0,                          // transfer_grams
            gasBackAddress,             // gas_back_address
            notifyReceiver,             // notify_receiver
            payload                     // payload
        );
    }

    function sendGas(
        address to,
        uint128 value_,
        uint16  flag_
    ) override external view onlyUser {
        require(CreditProcessorStatus.Cancelled == state ||
                CreditProcessorStatus.Processed == state,
                CreditProcessorErrorCodes.WRONG_STATE);
        tvm.accept();
        to.transfer({value: value_, flag: flag_, bounce: false});
    }

    function revertRemainderGas() override external onlyDeployer onlyState(CreditProcessorStatus.EventRejected) {
        tvm.accept();

        emit RevertRemainderGasCalled(msg.sender);

        uint128 balance = address(this).balance;
        if (balance < debt) {
            debt -= balance;
        } else {
            debt = 0;
        }
        deployer.transfer({
            value: 0,
            flag: MessageFlags.ALL_NOT_RESERVED,
            bounce: false
        });
    }

    function onTokenWalletBalance(uint128 balance) external onlyState(CreditProcessorStatus.CheckingAmount) {
        require(msg.sender.value != 0 && tokenWallet == msg.sender, CreditProcessorErrorCodes.NOT_PERMITTED);
        tvm.accept();
        if (balance >= amount) {
            // кто-то мог докинуть токенов на счет CreditProcessor
            amount = balance;

            // операция происходит не в кредит И
            if (debt == 0 && eventData.tonAmount == 0 &&
                // не требует swap и/или unwrap
                (eventData.swapType == 0 || eventData.tokenAmount == eventData.amount))
            {
                unwrapAmount = 0;
                swapAmount = 0;
                _payDebtThenTransfer();

            // иначе, если пользователь переводит WTON и требуется unwrap на покрытие кредита/гарантии определенного объема газа на выходе
            } else if (tokenWallet == wtonWallet) {
                if (eventData.swapType == 0) {
                    // unwrap-им ровно столько, сколько нужно на покрытие долга + гарантию газа
                    unwrapAmount = eventData.tonAmount + debt;
                } else if (eventData.swapType == 1) {
                    // unwrap-им ровно столько, чтобы осталось ровно eventData.tokenAmount
                    unwrapAmount = amount - eventData.tokenAmount;
                }
                // при этом мы точно гарантируем определенное число WTON, TON на выходе после выплаты кредита
                if (amount - eventData.tokenAmount >= unwrapAmount && unwrapAmount >= eventData.tonAmount + debt) {
                    _unwrapWTON();
                } else {
                    // или сигнализируем о том, что параметры unwrap невыполнимы
                    _changeState(CreditProcessorStatus.UnwrapFailed);
                }

            // иначе, если это swap по маркету
            } else if (debt == 0 && eventData.tonAmount == 0 && eventData.swapType == 1 && eventData.tokenAmount != amount) {
                // если газа достаточно
                if (address(this).balance > Gas.SWAP_MIN_BALANCE)
                {
                    // совершаем обмен так, чтобы у нас осталось ровно требуемое число токенов
                    swapAmount = amount - eventData.tokenAmount;
                    _swap();

                // иначе
                } else {
                    // меняем состояние на SwapFailed
                    _changeState(CreditProcessorStatus.SwapFailed);
                }

            // т.к мы тут, значит это swap по limit-у
            // если достаточно газа и корректный slippage
            } else if (address(this).balance > Gas.GET_EXPECTED_SPENT_AMOUNT_MIN_BALANCE && slippage_.numerator < slippage_.denominator) {
                // запрашиваем требуемое количество токенов для обмена с учетом проскальзывания
                IDexPair(dexPair).expectedSpendAmount{
                    value: Gas.GET_EXPECTED_SPENT_AMOUNT,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    // продолжение в onExpectedSpentAmount
                    callback: CreditProcessor.onExpectedSpentAmount
                }(
                    math.muldiv(eventData.tonAmount + debt, slippage_.denominator, slippage_.denominator - slippage_.numerator),
                    WTON_ROOT
                );
                _changeState(CreditProcessorStatus.CalculateSwap);
            } else {
                _changeState(CreditProcessorStatus.SwapFailed);
            }
        } else {
            _changeState(prevState);
        }
    }

    function retryUnwrap()
        override
        external
        onlyUserOrCreditorOrRecipient
        onlyState(CreditProcessorStatus.UnwrapFailed)
    {
        require(tokenWallet != wtonWallet || (amount - eventData.tokenAmount >= unwrapAmount),
            CreditProcessorErrorCodes.WRONG_UNWRAP_PARAMS);
        require(unwrapAmount >= eventData.tonAmount + debt,
            CreditProcessorErrorCodes.WRONG_UNWRAP_PARAMS);
        require(address(this).balance > Gas.UNWRAP_MIN_VALUE + Gas.MIN_BALANCE,
            CreditProcessorErrorCodes.LOW_GAS);
        require(msg.sender != eventData.recipient ||
                eventData.user == eventData.recipient ||
                msg.value >= Gas.UNWRAP_MIN_VALUE,
            CreditProcessorErrorCodes.LOW_GAS);

        tvm.accept();

        emit RetryUnwrapCalled(msg.sender);

        _unwrapWTON();
    }

    function setSlippage(NumeratorDenominator slippage)
        override
        external
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.SwapFailed)
    {
        require(slippage.denominator > slippage.numerator, CreditProcessorErrorCodes.WRONG_SLIPPAGE);
        tvm.accept();
        emit SetSlippageCalled(msg.sender);
        slippage_ = slippage;
    }

    function retrySwap()
        override
        external
        onlyUserOrCreditorOrRecipient
        onlyState(CreditProcessorStatus.SwapFailed)
    {
        require(address(this).balance > Gas.RETRY_SWAP_MIN_BALANCE, CreditProcessorErrorCodes.LOW_GAS);
        require(msg.sender != eventData.recipient ||
                eventData.recipient == eventData.user ||
                msg.value >= Gas.RETRY_SWAP_MIN_VALUE, CreditProcessorErrorCodes.LOW_GAS);
        tvm.accept();

        emit RetrySwapCalled(msg.sender);

        ITONTokenWallet(tokenWallet).balance{
            value: Gas.CHECK_BALANCE,
            flag: MessageFlags.SENDER_PAYS_FEES,
            callback: CreditProcessor.onTokenWalletBalance
        }();

        _changeState(CreditProcessorStatus.CheckingAmount);
    }

    function _swap() private {
        swapAttempt++;

        TvmBuilder successBuilder;
        successBuilder.store(OperationStatus.SUCCESS);
        successBuilder.store(swapAttempt);
        successBuilder.store(eventData.tonAmount + debt);

        TvmBuilder cancelBuilder;
        cancelBuilder.store(OperationStatus.CANCEL);
        cancelBuilder.store(swapAttempt);
        cancelBuilder.store(swapAmount);

        TvmBuilder builder;
        builder.store(OperationTypes.EXCHANGE);
        builder.store(swapAttempt);
        builder.store(uint128(0));
        builder.store(eventData.tonAmount + debt);
        builder.storeRef(successBuilder);
        builder.storeRef(cancelBuilder);

        ITONTokenWallet(tokenWallet).transferToRecipient{
            value: Gas.SWAP_VALUE,
            flag: MessageFlags.SENDER_PAYS_FEES
        }(
            0,                          // recipient_public_key
            dexPair,                    // recipient_address
            swapAmount,                 // amount
            0,                          // deploy_grams
            0,                          // transfer_grams
            address(this),              // gas_back_address
            true,                       // notify_receiver
            builder.toCell()            // payload
        );

        _changeState(CreditProcessorStatus.SwapInProgress);
    }

    function onExpectedSpentAmount(
        uint128 expectedSpentAmount,
        uint128 /* expected_fee */
    ) external onlyState(CreditProcessorStatus.CalculateSwap) {
        require(msg.sender == dexPair, CreditProcessorErrorCodes.NOT_PERMITTED);
        tvm.accept();

        if (expectedSpentAmount <= (amount - eventData.tokenAmount) &&
            address(this).balance > Gas.SWAP_MIN_BALANCE)
        {
            if(eventData.swapType == 0) {
                swapAmount = expectedSpentAmount;
            } else if(eventData.swapType == 1) {
                swapAmount = amount - eventData.tokenAmount;
            }
            
            _swap();

        } else {
            _changeState(CreditProcessorStatus.SwapFailed);
        }
    }

    function tokensReceivedCallback(
        address /* token_wallet */,
        address /* token_root */,
        uint128 receivedAmount,
        uint256 /* sender_public_key */,
        address senderAddress,
        address /* sender_wallet */,
        address /* originalGasTo */,
        uint128 /* updated_balance */,
        TvmCell payload
    ) external override {
        require(msg.sender.value != 0);

        if (state == CreditProcessorStatus.SwapInProgress) {
            TvmSlice s = payload.toSlice();
            if (msg.sender == wtonWallet && senderAddress == dexVault && s.bits() == 200) {
                tvm.accept();
                (uint8 status, uint64 id, uint128 expectedAmount) = s.decode(uint8, uint64, uint128);
                if (status == OperationStatus.SUCCESS && receivedAmount >= expectedAmount && id == swapAttempt) {
                    unwrapAmount = receivedAmount;
                    _unwrapWTON();
                } else {
                    _changeState(CreditProcessorStatus.SwapUnknown);
                }
            } else if (msg.sender == tokenWallet && senderAddress == dexPair && s.bits() == 200) {
                tvm.accept();
                (uint8 status, uint64 id, uint128 expectedAmount) = s.decode(uint8, uint64, uint128);
                if (status == OperationStatus.CANCEL && receivedAmount == expectedAmount && id == swapAttempt) {
                    _changeState(CreditProcessorStatus.SwapFailed);
                } else {
                    _changeState(CreditProcessorStatus.SwapUnknown);
                }
            } else if((msg.sender == wtonWallet && senderAddress == dexVault) ||
                      (msg.sender == tokenWallet && senderAddress == dexPair)) {
                tvm.accept();
                _changeState(CreditProcessorStatus.SwapUnknown);
            }
        }
    }

    function tokensBouncedCallback(
        address wallet_,
        address /* tokenRoot_ */,
        uint128 /* amount */,
        address /* bounced_from */,
        uint128 /* updated_balance */
    ) external override {
        require(msg.sender.value != 0);

        if (state == CreditProcessorStatus.SwapInProgress && msg.sender == tokenWallet && wallet_ == tokenWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.SwapFailed);
        } else if (state == CreditProcessorStatus.UnwrapInProgress && msg.sender == wtonWallet && wallet_ == wtonWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.UnwrapFailed);
        } else if (state == CreditProcessorStatus.Processed && msg.sender == tokenWallet && wallet_ == tokenWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.Cancelled);
        }
    }

    function _unwrapWTON() private {
        if (unwrapAmount >= eventData.tonAmount + debt &&
            address(this).balance > Gas.UNWRAP_MIN_VALUE + Gas.MIN_BALANCE) {
            TvmCell empty;

            ITONTokenWallet(wtonWallet).transferToRecipient{
                value: Gas.UNWRAP_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES
            }(
                0,                          // recipient_public_key
                WTON_VAULT,                 // recipient_address
                unwrapAmount,               // amount
                0,                          // deploy_grams
                0,                          // transfer_grams
                address(this),              // gas_back_address
                true,                       // notify_receiver
                empty                       // payload
            );

            _changeState(CreditProcessorStatus.UnwrapInProgress);
        } else {
            _changeState(CreditProcessorStatus.UnwrapFailed);
        }
    }

    function _payDebtThenTransfer() private {
        uint128 currentAmount = amount - (tokenWallet == wtonWallet ? unwrapAmount : swapAmount);

        if (address(this).balance >
            Gas.MIN_BALANCE +
            (debt > 0 ? debt + Gas.MAX_FWD_FEE : uint128(0)) +
            eventData.tonAmount +
            (currentAmount > 0 ?
                Gas.TRANSFER_TO_RECIPIENT_VALUE + Gas.DEPLOY_EMPTY_WALLET_GRAMS + Gas.MAX_FWD_FEE :
                Gas.MAX_FWD_FEE + Gas.MIN_CALLBACK_VALUE
            ))
        {

            _changeState(CreditProcessorStatus.Processed);

            if (debt > 0) {
                deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
                debt = 0;
            }

            if (currentAmount > 0) {
                ITONTokenWallet(tokenWallet).transferToRecipient{
                    value: (eventData.user == eventData.recipient ?
                        Gas.TRANSFER_TO_RECIPIENT_VALUE + Gas.DEPLOY_EMPTY_WALLET_GRAMS :
                        eventData.tonAmount + Gas.TRANSFER_TO_RECIPIENT_VALUE
                    ),
                    flag: MessageFlags.SENDER_PAYS_FEES
                }(
                    0,                              // recipient_public_key
                    eventData.recipient,            // recipient_address
                    currentAmount,                  // amount
                    (eventData.user == eventData.recipient ? Gas.DEPLOY_EMPTY_WALLET_GRAMS : uint128(0)), // deploy_grams
                    0,                              // transfer_grams
                    eventData.user,                 // gas_back_address
                    true,                           // notify_receiver
                    eventVoteData.eventData         // payload
                );

                eventData.user.transfer({
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.IGNORE_ERRORS,
                    bounce: false
                });
            } else {
                IReceiveTONsFromBridgeCallback(eventData.recipient).onReceiveTONsFromBridgeCallback{
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED,
                    bounce: eventData.user != eventData.recipient
                }(eventData);
            }
        } else if(state != CreditProcessorStatus.ProcessRequiresGas) {
            _changeState(CreditProcessorStatus.ProcessRequiresGas);
        }
    }

    receive() external {
        if (state == CreditProcessorStatus.UnwrapInProgress && msg.sender == WTON_ROOT && msg.value >= unwrapAmount) {
            tvm.accept();
            _payDebtThenTransfer();
        } else if (state == CreditProcessorStatus.ProcessRequiresGas && msg.value >= Gas.END_PROCESS_MIN_VALUE) {
            tvm.accept();

            emit GasDonation(msg.sender, msg.value);

            _payDebtThenTransfer();
        } else if (state == CreditProcessorStatus.UnwrapFailed &&
                   msg.value >= Gas.UNWRAP_MIN_VALUE + Gas.MIN_BALANCE &&
                   (tokenWallet != wtonWallet || (amount - eventData.tokenAmount >= unwrapAmount)) &&
                   unwrapAmount >= (eventData.tonAmount + debt))
        {
                tvm.accept();

                _unwrapWTON();
        }
    }

    onBounce(TvmSlice body) external {
        tvm.accept();

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(IDexPair.expectedSpendAmount) &&
                   state == CreditProcessorStatus.CalculateSwap)
        {
            _changeState(CreditProcessorStatus.SwapFailed);
        } else if (functionId == tvm.functionId(ITONTokenWallet.balance) &&
            state == CreditProcessorStatus.CheckingAmount)
        {
            _changeState(prevState);
        } else if (functionId == tvm.functionId(IReceiveTONsFromBridgeCallback.onReceiveTONsFromBridgeCallback) &&
            state == CreditProcessorStatus.Processed &&
            msg.sender == eventData.recipient)
        {
            _changeState(CreditProcessorStatus.Cancelled);
        }
    }

    fallback() external {
    }
}
