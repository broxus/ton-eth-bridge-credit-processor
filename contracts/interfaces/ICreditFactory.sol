pragma ton-solidity >= 0.57.0;

import 'ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-contracts/IEthereumEvent.sol';
import "./structures/ICreditEventDataStructure.sol";

interface ICreditFactory is ICreditEventDataStructure {

    struct CreditFactoryDetails {
        uint256[] owners;
        uint128 fee;
    }

    event FeeChanged(uint128 value);
    event CreditProcessorCodeChanged(uint256 hash);
    event DeployProcessorForUserCalled(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration,
        address sender
    );

    function getDetails() external view responsible returns(CreditFactoryDetails);

    function getCreditProcessorCode() external view responsible returns(TvmCell);

    function deployProcessorForUser(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration
    ) external;

    function deployProcessor(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration,
        uint128 grams
    ) external;

    function getCreditProcessorAddress(
        IEthereumEvent.EthereumEventVoteData eventVoteData,
        address configuration
    ) external view responsible returns(address);

    function runProcess(address creditProcessor) external view;
    function runRevertRemainderGas(address creditProcessor) external view;
    function runDeriveEventAddress(address creditProcessor, uint128 grams) external view;
    function runRequestEventConfigDetails(address creditProcessor, uint128 grams) external view;
    function runDeployEvent(address creditProcessor, uint128 grams) external view;
    function runRequestTokenEventProxyConfig(address creditProcessor, uint128 grams) external view;
    function runRequestDexPairAddress(address creditProcessor, uint128 grams) external view;
    function runRequestDexVault(address creditProcessor, uint128 grams) external view;
    function runCheckEventStatus(address creditProcessor, uint128 grams) external view;
    function runSetSlippage(address creditProcessor, uint128 grams, NumeratorDenominator slippage) external view;
    function runRetrySwap(address creditProcessor, uint128 grams) external view;
    function runRetryUnwrap(address creditProcessor, uint128 grams) external view;
}
