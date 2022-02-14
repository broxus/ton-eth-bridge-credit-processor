pragma ton-solidity >= 0.57.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "ton-eth-bridge-token-contracts/contracts/interfaces/IAcceptTokensTransferCallback.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenWallet.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol";
import "ton-eth-bridge-token-contracts/contracts/interfaces/IBurnableTokenWallet.sol";

import "../interfaces/IReceiveTONsFromBridgeCallback.sol";

import "../libraries/StrategyGas.sol";
import "../libraries/MessageFlags.sol";
import "../libraries/EventDataDecoder.sol";
import "../libraries/HiddenBridgeStrategyErrorCodes.sol";

contract HiddenBridgeStrategy is IReceiveTONsFromBridgeCallback, IAcceptTokensTransferCallback {

    event BurnTokens(
        uint32 id,
        address user,
        address processor,
        uint128 amount,
        uint160 evmAddress,
        uint32  chainId
    );

    address public static factory;
    address public static tokenRoot;
    
    address public tokenWallet;

    address deployer;

    constructor(address deployer_) public {
       if (msg.sender == factory &&
           msg.value >= StrategyGas.DEPLOY_VALUE &&
           tvm.pubkey() == 0 &&
           tokenRoot.value != 0 &&
           factory.value != 0)
       {
            _reserve();
            deployer = deployer_;

            ITokenRoot(tokenRoot).deployWallet {
                value: StrategyGas.DEPLOY_EMPTY_WALLET_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES,
                callback: HiddenBridgeStrategy.onTokenWallet
            }(
                address(this),
                StrategyGas.DEPLOY_EMPTY_WALLET_GRAMS
            );
       } else {
            factory.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.DESTROY_IF_ZERO, bounce: false});
       }   
    }

    function getDetails() external view responsible returns (
        address factory_,
        address tokenRoot_,
        address tokenWallet_
    ) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } (factory, tokenRoot, tokenWallet);
    }

    function onTokenWallet(address wallet) external {
        require(msg.sender.value != 0 && msg.sender == tokenRoot, HiddenBridgeStrategyErrorCodes.NOT_PERMITTED);
        require(tokenWallet.value == 0, HiddenBridgeStrategyErrorCodes.NON_EMPTY_TOKEN_WALLET);
        _reserve();

        tokenWallet = wallet;

        address deployer_ = deployer;
        deployer = address(0);
        deployer_.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.IGNORE_ERRORS, bounce: false});
    }

    function onAcceptTokensTransfer(
        address _tokenRoot,
        uint128 amount,
        address senderAddress,
        address senderWallet,
        address originalGasTo,
        TvmCell payload
    ) override external {
        require(msg.sender.value != 0 && msg.sender == tokenWallet, HiddenBridgeStrategyErrorCodes.NOT_PERMITTED);
        _reserve();
        TvmCell empty;

        if (
            EventDataDecoder.isValid(payload) &&
            msg.value >= StrategyGas.MIN_CALLBACK_VALUE
        )
        {
            CreditEventData eventData = EventDataDecoder.decode(payload);
            TvmSlice l3 = eventData.layer3.toSlice();

            if (l3.bits() == 491) {
                (
                    uint32 id,
                    address proxy,
                    uint160 evmAddress,
                    uint32 chainId
                ) = l3.decode(uint32, address, uint160, uint32);

                TvmBuilder burnPayload;
                burnPayload.store(evmAddress);
                burnPayload.store(chainId);
                burnPayload.store(id);

                if (senderAddress.value != 0) {
                    burnPayload.store(senderAddress);
                }

                emit BurnTokens(id, eventData.user, senderAddress, amount, evmAddress, chainId);

                IBurnableTokenWallet(msg.sender).burn{
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED
                }(
                    amount,
                    eventData.user,
                    proxy,
                    burnPayload.toCell()
                );
            } else {
                ITokenWallet(msg.sender).transfer{
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED
                }(
                    amount,                                 // amount
                    eventData.user,                         // recipient
                    StrategyGas.DEPLOY_EMPTY_WALLET_GRAMS,  // deployWalletValue
                    eventData.user,                         // remainingGasTo
                    true,                                   // notify
                    empty                                   // payload
                );
            }
        } else {
            ITokenWallet(msg.sender).transferToWallet{value: 0, flag: MessageFlags.ALL_NOT_RESERVED}(
                amount,
                senderWallet,
                originalGasTo,
                originalGasTo == senderAddress,
                empty
            );
        }
    }

    function buildLayer3(uint32 id, address proxy, uint160 evmAddress, uint32 chainId) external pure returns(TvmCell) {

        TvmBuilder b;

        b.store(id);
        b.store(proxy);
        b.store(evmAddress);
        b.store(chainId);

        return b.toCell();
    }

    function onReceiveTONsFromBridgeCallback(CreditEventData decodedEventData) override external {
        _reserve();
        decodedEventData.user.transfer({
            value: 0,
            flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.IGNORE_ERRORS,
            bounce: false
        });
    }

    onBounce(TvmSlice body) external {
        tvm.accept();

        uint32 functionId = body.decode(uint32);

        if (functionId == tvm.functionId(ITokenRoot.deployWallet) && tokenWallet.value == 0) {
            factory.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.DESTROY_IF_ZERO, bounce: false});
        }
    }

    function _reserve() private view inline {
        tvm.rawReserve(StrategyGas.INITIAL_BALANCE, 0);
    }
}
