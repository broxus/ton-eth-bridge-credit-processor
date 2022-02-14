pragma ton-solidity >= 0.57.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IBasicEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-configuration-contracts/IEthereumEventConfiguration.sol';
import "ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IEventNotificationReceiver.sol";
import "ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IProxy.sol";

import 'ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol';
import 'ton-eth-bridge-token-contracts/contracts/interfaces/ITokenWallet.sol';
import 'ton-eth-bridge-token-contracts/contracts/interfaces/TIP3TokenWallet.sol';

import 'ton-dex/contracts/interfaces/IDexRoot.sol';
import 'ton-dex/contracts/interfaces/IDexPair.sol';
import "ton-dex/contracts/libraries/DexOperationTypes.sol";

import './interfaces/IEthereumEventWithDetails.sol';
import "./interfaces/ICreditFactory.sol";
import "./interfaces/ICreditProcessor.sol";
import "./interfaces/IReceiveTONsFromBridgeCallback.sol";
import './interfaces/IHasTokenRoot.sol';

import './Addresses.sol';

import './libraries/MessageFlags.sol';
import './libraries/CreditProcessorErrorCodes.sol';
import "./libraries/EventDataDecoder.sol";
import './libraries/OperationStatus.sol';
import './libraries/CreditGas.sol';


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

        if (msg.value >= (CreditGas.CREDIT_BODY - CreditGas.DEPLOY_PROCESSOR - CreditGas.MAX_FWD_FEE) &&
            msg.sender.value != 0 && tvm.pubkey() == 0 &&
            EventDataDecoder.isValid(eventVoteData.eventData) &&
            configuration.value != 0)
        {
            eventData = EventDataDecoder.decode(eventVoteData.eventData);

            deployer = (msg.sender == eventData.creditor ? deployer_ : msg.sender);

            if (deployer == eventData.creditor) {
                fee_ = fee;
                debt = math.max(CreditGas.CREDIT_BODY, msg.value) + fee_;
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
                    value: CreditGas.DERIVE_EVENT_ADDRESS,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onEventAddress
                }(eventVoteData);

                IEthereumEventConfiguration(configuration).getDetails{
                    value: CreditGas.GET_EVENT_CONFIG_DETAILS,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onEventConfigDetails
                }();

                ITokenRoot(WEVER_ROOT)
                    .deployWallet {
                        value: CreditGas.DEPLOY_EMPTY_WALLET_VALUE,
                        flag: MessageFlags.SENDER_PAYS_FEES,
                        callback: CreditProcessor.onWtonWallet
                    }(
                        address(this),
                        CreditGas.DEPLOY_EMPTY_WALLET_GRAMS
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
            WEVER_VAULT,
            WEVER_ROOT,

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
        require(msg.value >= CreditGas.DERIVE_EVENT_ADDRESS + CreditGas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
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
            if (address(this).balance >= eventInitialBalance + CreditGas.MAX_FWD_FEE) {
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
        require(msg.value >= eventInitialBalance + CreditGas.MAX_FWD_FEE);
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
        require(msg.value >= CreditGas.GET_EVENT_CONFIG_DETAILS + CreditGas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
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

        IHasTokenRoot(eventProxy).getTokenRoot{
            value: CreditGas.GET_PROXY_TOKEN_ROOT,
            flag: MessageFlags.SENDER_PAYS_FEES,
            callback: CreditProcessor.onTokenRoot
        }();
    }

    function requestTokenEventProxyConfig()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= CreditGas.GET_PROXY_TOKEN_ROOT + CreditGas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot.value == 0, CreditProcessorErrorCodes.NON_EMPTY_TOKEN_ROOT);
        require(eventProxy.value != 0, CreditProcessorErrorCodes.EMPTY_PROXY_ADDRESS);

        emit RequestTokenEventProxyConfigCalled(msg.sender);
        IHasTokenRoot(eventProxy).getTokenRoot{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onTokenRoot
        }();
    }

    function requestDexVault()
        override
        external
        view
        onlyUserOrCreditor
        onlyState(CreditProcessorStatus.Created)
    {
        require(msg.value >= CreditGas.GET_DEX_VAULT + CreditGas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot != WEVER_ROOT, CreditProcessorErrorCodes.TOKEN_IS_WTON);
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
        require(address(this).balance >= CreditGas.GET_DEX_PAIR_ADDRESS + CreditGas.MAX_FWD_FEE, CreditProcessorErrorCodes.LOW_GAS);
        require(tokenRoot != WEVER_ROOT, CreditProcessorErrorCodes.TOKEN_IS_WTON);
        require(tokenRoot.value != 0, CreditProcessorErrorCodes.EMPTY_TOKEN_ROOT);
        require(dexPair.value == 0, CreditProcessorErrorCodes.NON_EMPTY_DEX_PAIR);

        emit RequestDexPairAddressCalled(msg.sender);
        IDexRoot(DEX_ROOT).getExpectedPairAddress{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            callback: CreditProcessor.onPairAddress
        }(WEVER_ROOT, tokenRoot);
    }

    function onTokenRoot(address _tokenRoot) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender.value != 0 && msg.sender == eventProxy, CreditProcessorErrorCodes.NOT_PERMITTED);
        require(tokenRoot.value == 0, CreditProcessorErrorCodes.NON_EMPTY_TOKEN_ROOT);

        tvm.accept();

        tokenRoot = _tokenRoot;

        if (tokenRoot == WEVER_ROOT) {
            tokenWallet = wtonWallet;
        } else {
            IDexRoot(DEX_ROOT)
                .getVault{
                    value: CreditGas.GET_DEX_VAULT,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onDexVault
                }();

            IDexRoot(DEX_ROOT).getExpectedPairAddress{
                value: CreditGas.GET_DEX_PAIR_ADDRESS,
                flag: MessageFlags.SENDER_PAYS_FEES,
                callback: CreditProcessor.onPairAddress
            }(WEVER_ROOT, tokenRoot);

            ITokenRoot(tokenRoot)
                .deployWallet {
                    value: CreditGas.DEPLOY_EMPTY_WALLET_VALUE,
                    flag: MessageFlags.SENDER_PAYS_FEES,
                    callback: CreditProcessor.onTokenWallet
                }(
                    address(this),
                    CreditGas.DEPLOY_EMPTY_WALLET_GRAMS
                );
        }
    }

    function onWtonWallet(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender == WEVER_ROOT, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        wtonWallet = value;

        if (WEVER_ROOT == tokenRoot) {
            tokenWallet = value;
        }

        checkAddressesDerived();
    }

    function onTokenWallet(address value) external onlyState(CreditProcessorStatus.Created) {
        require(msg.sender.value != 0 && msg.sender == tokenRoot, CreditProcessorErrorCodes.NOT_PERMITTED);

        tvm.accept();

        tokenWallet = value;

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

    function onEventConfirmed(
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
    }

    function onAcceptTokensMint(
        address _tokenRoot,
        uint128 _amount,
        address _remainingGasTo,
        TvmCell _payload
    ) override external {
        require(
            msg.sender.value != 0 && tokenWallet == msg.sender,
            CreditProcessorErrorCodes.NOT_PERMITTED
        );

        if (_amount >= amount && state == CreditProcessorStatus.EventConfirmed) {
            amount = _amount;

            _onTokenWalletRequiredBalance();
        }
    }

    function onAcceptTokensBurn(
        uint128 /* _amount */,
        address /* _walletOwner */,
        address /* _wallet */,
        address /* _remainingGasTo */,
        TvmCell /* _payload */
    ) override external {
        require(msg.sender.value != 0 && msg.sender == WEVER_ROOT, CreditProcessorErrorCodes.NOT_PERMITTED);

        if (state == CreditProcessorStatus.UnwrapInProgress) {
            tvm.accept();
            _payDebtThenTransfer();
        }
    }

    function process() override external onlyState(CreditProcessorStatus.EventConfirmed) {
        bool payingDebtsBeforeProcess = debt == 0 ? msg.sender == eventData.user : (
                (msg.sender == eventData.recipient || msg.sender == eventData.user) &&
                msg.value > debt &&
                address(this).balance > debt + CreditGas.CREDIT_BODY
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

        TIP3TokenWallet(tokenWallet).balance{
            value: CreditGas.CHECK_BALANCE,
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
                address(this).balance > debt + CreditGas.CREDIT_BODY, CreditProcessorErrorCodes.LOW_GAS);
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
            require(address(this).balance >= debt + CreditGas.MAX_FWD_FEE + CreditGas.MIN_BALANCE, CreditProcessorErrorCodes.LOW_GAS);
            tvm.accept();
            deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
            debt = 0;
        } else {
            tvm.accept();
        }
        emit CancelCalled(msg.sender);
        _changeState(CreditProcessorStatus.Cancelled);
    }

    function proxyTokensTransfer(
        address _tokenWallet,
        uint128 _gasValue,
        uint128 _amount,
        address _recipient,
        uint128 _deployWalletValue,
        address _remainingGasTo,
        bool _notify,
        TvmCell _payload
    ) override external view onlyUser {
        require(CreditProcessorStatus.Cancelled == state ||
                CreditProcessorStatus.Processed == state,
            CreditProcessorErrorCodes.WRONG_STATE);

        tvm.accept();

        ITokenWallet(_tokenWallet).transfer{
            value: _gasValue,
            flag: MessageFlags.SENDER_PAYS_FEES
        }(
            _amount,
            _recipient,
            _deployWalletValue,
            _remainingGasTo,
            _notify,
            _payload
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

            _onTokenWalletRequiredBalance();
        } else {
            _changeState(prevState);
        }
    }

    function _onTokenWalletRequiredBalance() internal {
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
                _unwrapWEVER();
            } else {
                // или сигнализируем о том, что параметры unwrap невыполнимы
                _changeState(CreditProcessorStatus.UnwrapFailed);
            }

        // иначе, если это swap по маркету
        } else if (debt == 0 && eventData.tonAmount == 0 && eventData.swapType == 1 && eventData.tokenAmount != amount) {
            // если газа достаточно
            if (address(this).balance > CreditGas.SWAP_MIN_BALANCE)
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
        } else if (address(this).balance > CreditGas.GET_EXPECTED_SPENT_AMOUNT_MIN_BALANCE && slippage_.numerator < slippage_.denominator) {
            // запрашиваем требуемое количество токенов для обмена с учетом проскальзывания
            IDexPair(dexPair).expectedSpendAmount{
                value: CreditGas.GET_EXPECTED_SPENT_AMOUNT,
                flag: MessageFlags.SENDER_PAYS_FEES,
                // продолжение в onExpectedSpentAmount
                callback: CreditProcessor.onExpectedSpentAmount
            }(
                math.muldiv(eventData.tonAmount + debt, slippage_.denominator, slippage_.denominator - slippage_.numerator),
                WEVER_ROOT
            );
            _changeState(CreditProcessorStatus.CalculateSwap);
        } else {
            _changeState(CreditProcessorStatus.SwapFailed);
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
        require(address(this).balance > CreditGas.UNWRAP_MIN_VALUE + CreditGas.MIN_BALANCE,
            CreditProcessorErrorCodes.LOW_GAS);
        require(msg.sender != eventData.recipient ||
                eventData.user == eventData.recipient ||
                msg.value >= CreditGas.UNWRAP_MIN_VALUE,
            CreditProcessorErrorCodes.LOW_GAS);

        tvm.accept();

        emit RetryUnwrapCalled(msg.sender);

        _unwrapWEVER();
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
        require(address(this).balance > CreditGas.RETRY_SWAP_MIN_BALANCE, CreditProcessorErrorCodes.LOW_GAS);
        require(msg.sender != eventData.recipient ||
                eventData.recipient == eventData.user ||
                msg.value >= CreditGas.RETRY_SWAP_MIN_VALUE, CreditProcessorErrorCodes.LOW_GAS);
        tvm.accept();

        emit RetrySwapCalled(msg.sender);

        ITokenWallet(tokenWallet).balance{
            value: CreditGas.CHECK_BALANCE,
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
        builder.store(DexOperationTypes.EXCHANGE);
        builder.store(swapAttempt);
        builder.store(uint128(0));
        builder.store(eventData.tonAmount + debt);
        builder.storeRef(successBuilder);
        builder.storeRef(cancelBuilder);

        ITokenWallet(tokenWallet).transfer{
            value: CreditGas.SWAP_VALUE,
            flag: MessageFlags.SENDER_PAYS_FEES
        }(
            swapAmount,                 // amount
            dexPair,                    // recipient
            0,                          // deployWalletValue
            address(this),              // remainingGasTo
            true,                       // notify
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
            address(this).balance > CreditGas.SWAP_MIN_BALANCE)
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

    function onAcceptTokensTransfer(
        address /* tokenRoot */,
        uint128 receivedAmount,
        address senderAddress,
        address /* senderWallet */,
        address /* remainingGasTo */,
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
                    _unwrapWEVER();
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

    function onBounceTokensTransfer(
        address /* tokenRoot_ */,
        uint128 /* amount */,
        address /* revertedFrom */
    ) external override {
        require(msg.sender.value != 0);

        if (state == CreditProcessorStatus.SwapInProgress && msg.sender == tokenWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.SwapFailed);
        } else if (state == CreditProcessorStatus.UnwrapInProgress && msg.sender == wtonWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.UnwrapFailed);
        } else if (state == CreditProcessorStatus.Processed && msg.sender == tokenWallet) {
            tvm.accept();
            _changeState(CreditProcessorStatus.Cancelled);
        }
    }

    function _unwrapWEVER() private {
        if (unwrapAmount >= eventData.tonAmount + debt &&
            address(this).balance > CreditGas.UNWRAP_MIN_VALUE + CreditGas.MIN_BALANCE) {
            TvmCell empty;

            ITokenWallet(wtonWallet).transfer{
                value: CreditGas.UNWRAP_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES
            }(
                unwrapAmount,               // amount
                WEVER_VAULT,                 // recipient
                0,                          // deployWalletValue
                address(this),              // remainingGasTo
                true,                       // notify
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
            CreditGas.MIN_BALANCE +
            (debt > 0 ? debt + CreditGas.MAX_FWD_FEE : uint128(0)) +
            eventData.tonAmount +
            (currentAmount > 0 ?
                CreditGas.TRANSFER_TOKENS_VALUE + CreditGas.DEPLOY_EMPTY_WALLET_GRAMS + CreditGas.MAX_FWD_FEE :
                CreditGas.MAX_FWD_FEE + CreditGas.MIN_CALLBACK_VALUE
            ))
        {

            _changeState(CreditProcessorStatus.Processed);

            if (debt > 0) {
                deployer.transfer({ value: debt, flag: MessageFlags.SENDER_PAYS_FEES, bounce: false });
                debt = 0;
            }

            if (currentAmount > 0) {
                ITokenWallet(tokenWallet).transfer{
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED
                }(
                    currentAmount,
                    eventData.recipient,
                    (eventData.user == eventData.recipient ? CreditGas.DEPLOY_EMPTY_WALLET_GRAMS : uint128(0)),
                    eventData.user,
                    true,
                    eventVoteData.eventData
                );
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
        if (state == CreditProcessorStatus.ProcessRequiresGas && msg.value >= CreditGas.END_PROCESS_MIN_VALUE) {
            tvm.accept();

            emit GasDonation(msg.sender, msg.value);

            _payDebtThenTransfer();
        } else if (state == CreditProcessorStatus.UnwrapFailed &&
                   msg.value >= CreditGas.UNWRAP_MIN_VALUE + CreditGas.MIN_BALANCE &&
                   (tokenWallet != wtonWallet || (amount - eventData.tokenAmount >= unwrapAmount)) &&
                   unwrapAmount >= (eventData.tonAmount + debt))
        {
                tvm.accept();

                _unwrapWEVER();
        }
    }

    onBounce(TvmSlice body) external {
        tvm.accept();

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(IDexPair.expectedSpendAmount) &&
                   state == CreditProcessorStatus.CalculateSwap)
        {
            _changeState(CreditProcessorStatus.SwapFailed);
        } else if (functionId == tvm.functionId(TIP3TokenWallet.balance) &&
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
