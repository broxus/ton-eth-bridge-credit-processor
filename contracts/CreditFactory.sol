pragma ton-solidity >= 0.39.0;

pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../node_modules/@broxus/contracts/contracts/utils/RandomNonce.sol";
import '../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';

import "./CreditProcessor.sol";

import "./access/MultiOwner.sol";

import "./interfaces/ICreditFactory.sol";
import './interfaces/ICreditProcessor.sol';

import './libraries/MessageFlags.sol';
import './libraries/CreditFactoryErrorCodes.sol';
import "./libraries/EventDataDecoder.sol";
import './libraries/Gas.sol';

contract CreditFactory is ICreditFactory, RandomNonce, MultiOwner {

    uint32 public version = 1;

    uint128 fee_;

    TvmCell creditProcessorCode;

    // recommended value of fee >= Gas.MAX_FWD_FEE,
    //                      fee <= Gas.CREDIT_BODY
    constructor(address admin_, uint[] owners_, uint128 fee) public {
        require(fee < Gas.CREDIT_BODY, CreditFactoryErrorCodes.TOO_HIGH_FEE);
        require(admin_.value != 0, CreditFactoryErrorCodes.WRONG_ADMIN);
        tvm.accept();
        for (uint i = 0; i < owners_.length; i++) {
            if (owners_[i] != 0) {
                owners.push(owners_[i]);
            }
        }
        admin = admin_;
        fee_ = fee;
    }

    function setCreditProcessorCode(TvmCell value) external anyOwner {
        tvm.accept();
        creditProcessorCode = value;
        emit CreditProcessorCodeChanged(tvm.hash(value));
    }

    function getCreditProcessorCode() override external view responsible returns(TvmCell) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } creditProcessorCode;
    }

    function setFee(uint128 value) external anyOwner {
        require(value < Gas.CREDIT_BODY, CreditFactoryErrorCodes.TOO_HIGH_FEE);
        tvm.accept();
        fee_ = value;
        emit FeeChanged(fee_);
    }

    function getDetails() override external view responsible returns(CreditFactoryDetails) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } CreditFactoryDetails(
            owners,
            fee_
        );
    }

    function deployProcessorForUser(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration
    ) override external {
        require(msg.value >= Gas.CREDIT_BODY + Gas.MAX_FWD_FEE + Gas.DEPLOY_PROCESSOR, CreditFactoryErrorCodes.LOW_GAS);
        require(EventDataDecoder.isValid(eventVoteData.eventData), CreditFactoryErrorCodes.INVALID_EVENT_DATA);
        CreditEventData eventData = EventDataDecoder.decode(eventVoteData.eventData);
        require(eventData.creditor == address(this), CreditFactoryErrorCodes.WRONG_CREDITOR);
        require(eventData.tokenAmount < eventData.amount ||
                (eventData.tokenAmount == eventData.amount && eventData.tonAmount == 0),
            CreditFactoryErrorCodes.WRONG_TOKEN_AMOUNT);
        require(eventData.swapType < 4, CreditFactoryErrorCodes.WRONG_SWAP_TYPE);
        require(eventData.user.value != 0, CreditFactoryErrorCodes.WRONG_USER);
        require(eventData.recipient.value != 0, CreditFactoryErrorCodes.WRONG_RECIPIENT);
        require(eventData.slippage.denominator > eventData.slippage.numerator, CreditFactoryErrorCodes.WRONG_SLIPPAGE);

        emit DeployProcessorForUserCalled(eventVoteData, configuration, msg.sender);

        new CreditProcessor{
            value: 0,
            flag: MessageFlags.REMAINING_GAS,
            pubkey: 0,
            code: creditProcessorCode,
            varInit: {
                eventVoteData: eventVoteData,
                configuration: configuration
            }
        }(0, eventData.user);
    }

    function deployProcessor(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration,
        uint128 grams
    ) override external anyOwner {
        require(EventDataDecoder.isValid(eventVoteData.eventData), CreditFactoryErrorCodes.INVALID_EVENT_DATA);
        tvm.accept();

        CreditEventData eventData = EventDataDecoder.decode(eventVoteData.eventData);

        if (eventData.creditor == address(this) &&
            address(this).balance > grams + Gas.MAX_FWD_FEE &&
            grams >= Gas.CREDIT_BODY &&
            eventData.tokenAmount < eventData.amount &&
            eventData.swapType < 4 &&
            eventData.user.value != 0 &&
            eventData.recipient.value != 0 &&
            eventData.slippage.denominator > eventData.slippage.numerator)
        {
            new CreditProcessor{
                value: grams,
                flag: 0,
                pubkey: 0,
                code: creditProcessorCode,
                varInit: {
                    eventVoteData: eventVoteData,
                    configuration: configuration
                }
            }(fee_, address(this));
        }
    }

    function getCreditProcessorAddress(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration
    ) override external view responsible returns(address) {
        TvmCell stateInit = tvm.buildStateInit({
            contr: CreditProcessor,
            varInit: {
                eventVoteData: eventVoteData,
                configuration: configuration
            },
            pubkey: 0,
            code: creditProcessorCode
        });

        return {value: 0, flag: MessageFlags.REMAINING_GAS} address(tvm.hash(stateInit));
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
    ) external view onlyAdmin {
        require(
            address(this).balance >=
                Gas.TRANSFER_TO_RECIPIENT_VALUE + Gas.MAX_FWD_FEE + Gas.MIN_BALANCE,
            CreditFactoryErrorCodes.LOW_GAS
        );
        require(
            gasValue >= Gas.TRANSFER_TO_RECIPIENT_VALUE + deployGrams,
            CreditFactoryErrorCodes.LOW_GAS
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
    ) external view anyOwner {
        tvm.accept();
        to.transfer({value: value_, flag: flag_, bounce: false});
    }

    function runRevertRemainderGas(address creditProcessor) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).revertRemainderGas();
    }

    function runProcess(address creditProcessor) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).process();
    }

    function runDeriveEventAddress(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).deriveEventAddress{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runRequestEventConfigDetails(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).requestEventConfigDetails{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runDeployEvent(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).deployEvent{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runRequestTokenEventProxyConfig(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).requestTokenEventProxyConfig{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runRequestDexPairAddress(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).requestDexPairAddress{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runRequestDexVault(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).requestDexVault{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runCheckEventStatus(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).checkEventStatus{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }();
    }

    function runRetryUnwrap(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).retryUnwrap{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams  }();
    }

    function runRetrySwap(address creditProcessor, uint128 grams) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).retrySwap{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams  }();
    }

    function runSetSlippage(address creditProcessor, uint128 grams, NumeratorDenominator slippage) override external view anyOwner {
        tvm.accept();
        ICreditProcessor(creditProcessor).setSlippage{ flag: MessageFlags.SENDER_PAYS_FEES, value: grams }(slippage);
    }

    receive() external view {
    }

    function upgrade(TvmCell code) external onlyAdmin {
        require(address(this).balance > Gas.UPGRADE_FACTORY_MIN_BALANCE, CreditFactoryErrorCodes.LOW_GAS);

        tvm.accept();

        TvmBuilder builder;

        builder.store(version);
        builder.store(fee_);
        builder.store(creditProcessorCode);

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell data) private {}
}
