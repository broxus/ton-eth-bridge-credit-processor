pragma ton-solidity >= 0.39.0;


import '@broxus/contracts/contracts/utils/CheckPubKey.sol';
import '@broxus/contracts/contracts/utils/RandomNonce.sol';
import 'ton-eth-bridge-contracts/everscale/contracts/utils/TransferUtils.sol';
import "./CreditEthereumEventConfiguration.sol";
import "ton-eth-bridge-contracts/everscale/contracts/bridge/interfaces/event-configuration-contracts/IEthereumEventConfiguration.sol";


contract CreditEthereumEventConfigurationFactory is TransferUtils, RandomNonce, CheckPubKey {
    TvmCell public configurationCode;
    TvmCell public creditProcessorCode;

    constructor() public checkPubKey {
        tvm.accept();
    }

    function setConfigurationCodeOnce(TvmCell _configurationCode) external checkPubKey {
        require(configurationCode.toSlice().empty(), 2001);
        tvm.accept();
        configurationCode = _configurationCode;
    }

    function setCreditProcessorCodeOnce(TvmCell _creditProcessorCode) external checkPubKey {
        require(creditProcessorCode.toSlice().empty(), 2002);
        tvm.accept();
        creditProcessorCode = _creditProcessorCode;
    }

    function deploy(
        address _owner,
        IEthereumEventConfiguration.BasicConfiguration basicConfiguration,
        IEthereumEventConfiguration.EthereumEventConfiguration networkConfiguration
    ) external reserveBalance {
        TvmCell _meta;

        new CreditEthereumEventConfiguration{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED,
            code: configurationCode,
            pubkey: 0,
            varInit: {
                basicConfiguration: basicConfiguration,
                networkConfiguration: networkConfiguration
            }
        }(_owner, _meta, creditProcessorCode);
    }

    function deriveConfigurationAddress(
        IEthereumEventConfiguration.BasicConfiguration basicConfiguration,
        IEthereumEventConfiguration.EthereumEventConfiguration networkConfiguration
    ) external view returns(address) {
        TvmCell stateInit = tvm.buildStateInit({
            contr: CreditEthereumEventConfiguration,
            varInit: {
                basicConfiguration: basicConfiguration,
                networkConfiguration: networkConfiguration
            },
            pubkey: 0,
            code: configurationCode
        });

        return address(tvm.hash(stateInit));
    }
}
