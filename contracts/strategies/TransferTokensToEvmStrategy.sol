pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../../node_modules/@broxus/contracts/contracts/utils/RandomNonce.sol";
import '../../node_modules/bridge/free-ton/contracts/bridge/interfaces/IProxyTokenTransferConfigurable.sol';

import "../access/MultiOwner.sol";
import "../interfaces/tokens/ITokensReceivedCallback.sol";
import "../interfaces/tokens/ITONTokenWallet.sol";
import "../interfaces/tokens/IRootTokenContract.sol";

import "../libraries/StrategyGas.sol";
import "../libraries/MessageFlags.sol";

contract TransferTokensToEvmStrategy is ITokensReceivedCallback, RandomNonce, MultiOwner {

    bool paused_;

    bool public deployInProgress;
    address public deployProxy;
    address public deployTokenRoot;
    address public deployTokenWallet;

    mapping(address => address) proxies;
    mapping(address => address) wallets;

    constructor(address admin_, uint[] owners_) public {
        require(admin_.value != 0, CreditFactoryErrorCodes.WRONG_ADMIN);
        tvm.accept();
        for (uint i = 0; i < owners_.length; i++) {
            if (owners_[i] != 0) {
                owners.push(owners_[i]);
            }
        }
        admin = admin_;
    }

    function setPaused(bool paused) external onlyAdmin {
        tvm.accept();
        paused_ = paused;
    }

    function isPaused() external view responisble returns (bool paused) {
        return { value: 0, bounce: false, flag: 64 } paused_;
    }

    function connectProxy(address eventProxy) external anyOwner {
        require(!deployInProgress, WRONG_STATE);
        require(address(this).balance >= StrategyGas.SETUP_PROXY_MIN_BALANCE, LOW_BALANCE);

        tvm.accept();

        deployInProgress = true;
        deployProxy = eventProxy;

        IProxyTokenTransferConfigurable(eventProxy).getConfiguration{
            value: StrategyGas.GET_PROXY_CONFIG,
            flag: MessageFlags.SENDER_PAYS_FEES,
            callback: TransferTokensToEvmStrategy.onTokenEventProxyConfig
        }();
    }

    function removeProxy(address eventProxy) external onlyAdmin {
        require(address(this).balance >= StrategyGas.SETUP_PROXY_MIN_BALANCE, LOW_BALANCE);
        tvm.accept();
    }

    function resetDeploy() external onlyAdmin {
        tvm.accept();
        _resetDeploy();
    }

    function _resetDeploy() private {
        deployInProgress = false;
        deployProxy = address(0);
        deployTokenRoot = address(0);
        deployTokenWallet = address(0);
    }

    function onTokenEventProxyConfig(IProxyTokenTransferConfigurable.Configuration config) external {
        require(deployInProgress, WRONG_STATE);
        require(msg.sender.value != 0 && msg.sender == deployProxy, NOT_PERMITTED);

        tvm.accept();

        if(config.tokenRoot.value != 0) {
            deployTokenRoot = value.tokenRoot;

            IRootTokenContract(deployTokenRoot).deployEmptyWallet {
                value: StrategyGas.DEPLOY_EMPTY_WALLET_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES
            }(
                StrategyGas.DEPLOY_EMPTY_WALLET_GRAMS,  // deploy_grams
                0,                              // wallet_public_key
                address(this),                  // owner_address
                address(this)                   // gas_back_address
            );

            IRootTokenContract(deployTokenRoot).getWalletAddress{
                value: StrategyGas.GET_WALLET_ADDRESS_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES,
                callback: TransferTokensToEvmStrategy.onTokenWallet
            }(
                0,                              // wallet_public_key_
                address(this)                   // owner_address_
            );
        } else {
            _resetDeploy();
        }
    }

    function onTokenWallet(address wallet) external {
        require(deployInProgress, WRONG_STATE);
        require(msg.sender.value != 0 && msg.sender == deployTokenRoot, NOT_PERMITTED);

        tvm.accept();

        if(wallet.value != 0) {
            deployTokenWallet = wallet;

            ITONTokenWallet(wallet).setReceiveCallback{
                value: StrategyGas.SET_RECEIVE_CALLBACK_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES
            }(address(this), false);

            ITONTokenWallet(wallet).getDetails{
                value: StrategyGas.GET_TOKEN_WALLET_DETAILS,
                flag: MessageFlags.SENDER_PAYS_FEES,
                callback: TransferTokensToEvmStrategy.onTokenWalletDetails
            }();
        } else {
            _resetDeploy();
        }
    }

    function onTokenWalletDetails(ITONTokenWallet.ITONTokenWalletDetails details) external {
        require(deployInProgress, WRONG_STATE);
        require(msg.sender.value != 0 && msg.sender == deployTokenWallet, NOT_PERMITTED);
        tvm.accept();

        if (
            deployProxy.value != 0 &&
            details.root_address == deployTokenRoot && deployTokenRoot.value != 0 &&
            details.wallet_public_key == 0 &&
            details.owner_address == address(this) &&
            details.receive_callback == address(this) &&
            !details.allow_non_notifiable
        ) {
            wallets[deployTokenRoot] = deployTokenWallet;
            proxies[deployTokenRoot] = deployProxy;
        } else {
            _resetDeploy();
        }
    }


    function tokensReceivedCallback(
        address tokenWallet,
        address tokenRoot,
        uint128 amount,
        uint256 senderPublicKey,
        address senderAddress,
        address senderWallet,
        address originalGasTo,
        uint128 /* updatedBalance */,
        TvmCell eventData
    ) override external {
       // TODO
    }

    onBounce(TvmSlice body) external {
        tvm.accept();

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(ITONTokenWallet.getDetails) ||
            functionId == tvm.functionId(IRootTokenContract.getWalletAddress) ||
            functionId == tvm.functionId(IProxyTokenTransferConfigurable.getConfiguration))
        {
            _resetDeploy();
        }
    }


    function upgrade(TvmCell code) override external onlyAdmin {
        require(address(this).balance > StrategyGas.UPGRADE_MIN_BALANCE, LOW_BALANCE);

        tvm.accept();

        TvmBuilder builder;

        builder.store(paused);
        builder.store(proxies);
        builder.store(wallets);

        tvm.setcode(code);
        tvm.setCurrentCode(code);

        onCodeUpgrade(builder.toCell());
    }

    function onCodeUpgrade(TvmCell data) private {}
}
