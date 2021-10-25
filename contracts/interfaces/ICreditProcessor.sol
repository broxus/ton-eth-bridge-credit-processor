pragma ton-solidity >= 0.39.0;

import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/IEventNotificationReceiver.sol';
import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/IProxy.sol';
import "../interfaces/tokens/ITokensReceivedCallback.sol";
import "../interfaces/tokens/ITokensBouncedCallback.sol";
import "./structures/ICreditEventDataStructure.sol";

interface ICreditProcessor is ITokensReceivedCallback, ITokensBouncedCallback, IEventNotificationReceiver, IProxy,
                              ICreditEventDataStructure
{

    enum CreditProcessorStatus {
        Created,
        EventNotDeployed, EventDeployInProgress, EventConfirmed, EventRejected,
        CheckingAmount, CalculateSwap, SwapInProgress, SwapFailed, SwapUnknown,
        UnwrapInProgress, UnwrapFailed,
        ProcessRequiresGas, Processed, Cancelled
    }

    struct CreditProcessorDetails {
        IEthereumEvent.EthereumEventVoteData eventVoteData;
        address configuration;

        uint128 amount;
        NumeratorDenominator slippage;

        address dexRoot;
        address wtonVault;
        address wtonRoot;

        CreditProcessorStatus state;
        IBasicEvent.Status eventState;

        address deployer;
        uint128 debt;
        uint128 fee;

        address eventAddress;
        address tokenRoot;
        address tokenWallet;
        address wtonWallet;
        address dexPair;
        address dexVault;

        uint64 swapAttempt;
        uint128 swapAmount;
        uint128 unwrapAmount;
    }

    function getDetails() external view responsible returns(CreditProcessorDetails);
    function getCreditEventData() external view responsible returns(CreditEventData);

    event CreditProcessorDeployed(CreditProcessorDetails details);
    event CreditProcessorStateChanged(CreditProcessorStatus from, CreditProcessorStatus to, CreditProcessorDetails details);

    ///////////////////////////////////////////////////////////////////////////////
    // Support methods for continue Created -> EventNotDeployed/EventDeployInProgress

    function deriveEventAddress() external view;
    event DeriveEventAddressCalled(address sender);

    function requestTokenEventProxyConfig() external view;
    event RequestTokenEventProxyConfigCalled(address sender);

    function requestDexPairAddress() external view;
    event RequestDexPairAddressCalled(address sender);

    function requestDexVault() external view;
    event RequestDexVaultCalled(address sender);

    function requestEventConfigDetails() external view;
    event RequestEventConfigDetailsCalled(address sender);

    function checkEventStatus() external;
    event CheckEventStatusCalled(address sender);

    event GasDonation(address sender, uint128 value);

    ///////////////////////////////////////////////////////////////////////////////
    // Support methods for continue EventNotDeployed -> EventDeployInProgress
    function deployEvent() external;
    event DeployEventCalled(address sender);

    ///////////////////////////////////////////////////////////////////////////////
    // Support methods for UnwrapFailed -> UnwrapInProgress
    function retryUnwrap() external;
    event RetryUnwrapCalled(address sender);

    ///////////////////////////////////////////////////////////////////////////////
    // Support methods for SwapFailed -> CheckingAmount
    function retrySwap() external;
    event RetrySwapCalled(address sender);

    function setSlippage(NumeratorDenominator slippage) external;
    event SetSlippageCalled(address sender);

    ///////////////////////////////////////////////////////////////////////////////
    // Method for start processing (EventConfirmed-> CheckingAmount),  onlyDeployerOrCreditor
    function process() external;
    event ProcessCalled(address sender);

    ///////////////////////////////////////////////////////////////////////////////
    // Method for user allows change state to Cancelled
    // EventConfirmed -> Cancelled
    // SwapFailed -> Cancelled
    // SwapUnknown -> Cancelled
    // UnwrapFailed -> Cancelled
    // StrategyNotDeployed -> Cancelled
    function cancel() external;
    event CancelCalled(address sender);

    // Methods allowed to user in Cancelled state
    // Proxy call for TONTokenWallet transferToRecipient, balance must be > (0.7 TON + deployGrams)
    function proxyTransferToRecipient(
        // address of TONTokenWallet
        address tokenWallet_,
        // transferToRecipient gas value, must be > 0.5 TON + deployGrams
        uint128 gasValue,
        // TONTokenWallet.transferToRecipient params
        uint128 amount_,
        address recipient,
        uint128 deployGrams,
        address gasBackAddress,
        bool    notifyReceiver,
        TvmCell payload
    ) external view;

    // transfer gas
    function sendGas(address to, uint128 value_, uint16  flag_) external view;

    ///////////////////////////////////////////////////////////////////////////////
    // Method allows deployer returns the remaining when EthereumEvent rejected
    function revertRemainderGas() external;
    event RevertRemainderGasCalled(address sender);
}
