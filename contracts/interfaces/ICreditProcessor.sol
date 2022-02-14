pragma ton-solidity >= 0.57.0;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/IProxy.sol';
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensMintCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensBurnCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IBounceTokensTransferCallback.sol";
import "./structures/ICreditEventDataStructure.sol";

interface ICreditProcessor is
    IAcceptTokensTransferCallback,
    IAcceptTokensMintCallback,
    IAcceptTokensBurnCallback,
    IBounceTokensTransferCallback,
    IProxy,
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
    // Public method allows to pay debt for user
    function payDebtForUser() external;

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
    function proxyTokensTransfer(
        address _tokenWallet,
        uint128 _gasValue,
        uint128 _amount,
        address _recipient,
        uint128 _deployWalletValue,
        address _remainingGasTo,
        bool _notify,
        TvmCell _payload
    ) external view;

    // transfer gas
    function sendGas(address to, uint128 value_, uint16  flag_) external view;

    ///////////////////////////////////////////////////////////////////////////////
    // Method allows deployer returns the remaining when EthereumEvent rejected
    function revertRemainderGas() external;
    event RevertRemainderGasCalled(address sender);
}
