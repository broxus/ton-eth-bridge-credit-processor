pragma ton-solidity >= 0.39.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../interfaces/tokens/ITokensReceivedCallback.sol";
import "../interfaces/tokens/ITONTokenWallet.sol";
import "../interfaces/tokens/IRootTokenContract.sol";
import "../interfaces/tokens/IBurnableByOwnerTokenWallet.sol";

import "../interfaces/IReceiveTONsFromBridgeCallback.sol";

import "../libraries/StrategyGas.sol";
import "../libraries/MessageFlags.sol";
import "../libraries/EventDataDecoder.sol";
import "../libraries/HiddenBridgeStrategyErrorCodes.sol";

contract HiddenBridgeStrategy is IReceiveTONsFromBridgeCallback, ITokensReceivedCallback {

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

            IRootTokenContract(tokenRoot).deployEmptyWallet {
                value: StrategyGas.DEPLOY_EMPTY_WALLET_VALUE,
                flag: MessageFlags.SENDER_PAYS_FEES
            }(
                StrategyGas.DEPLOY_EMPTY_WALLET_GRAMS,  // deploy_grams
                0,                                      // wallet_public_key
                address(this),                          // owner_address
                deployer                                // gas_back_address
            );

            IRootTokenContract(tokenRoot).getWalletAddress{
                value: 0,
                flag: MessageFlags.ALL_NOT_RESERVED,
                callback: HiddenBridgeStrategy.onTokenWallet
            }(
                0,                                      // wallet_public_key_
                address(this)                           // owner_address_
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

        ITONTokenWallet(tokenWallet).setReceiveCallback{
            value: StrategyGas.SET_RECEIVE_CALLBACK_VALUE,
            flag: MessageFlags.SENDER_PAYS_FEES
        }(address(this), false);

        address deployer_ = deployer;
        deployer = address(0);
        deployer_.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.IGNORE_ERRORS, bounce: false});
    }

    function tokensReceivedCallback(
        address tokenWallet_,
        address tokenRoot_,
        uint128 amount,
        uint256 senderPublicKey,
        address senderAddress,
        address senderWallet,
        address originalGasTo,
        uint128 /* updatedBalance */,
        TvmCell payload
    ) override external {
        require(msg.sender.value != 0 && msg.sender == tokenWallet, HiddenBridgeStrategyErrorCodes.NOT_PERMITTED);
        _reserve();
        TvmCell empty;

        if (
            tokenWallet_ == tokenWallet &&
            tokenRoot_ == tokenRoot &&
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

                emit BurnTokens(id, eventData.user, senderAddress, amount, evmAddress, chainId);

                IBurnableByOwnerTokenWallet(msg.sender).burnByOwner{
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED
                }(
                    amount,
                    0,
                    eventData.user,
                    proxy,
                    burnPayload.toCell()
                );
            } else {
                ITONTokenWallet(msg.sender).transferToRecipient{
                    value: StrategyGas.TRANSFER_TO_RECIPIENT_VALUE,
                    flag: MessageFlags.SENDER_PAYS_FEES
                }(
                    0,                                      // recipient_public_key
                    eventData.user,                         // recipient_address
                    amount,                                 // amount
                    StrategyGas.DEPLOY_EMPTY_WALLET_GRAMS,  // deploy_grams
                    0,                                      // transfer_grams
                    eventData.user,                         // gas_back_address
                    true,                                   // notify_receiver
                    empty                                   // payload
                );

                eventData.user.transfer({
                    value: 0,
                    flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.IGNORE_ERRORS,
                    bounce: false
                });
            }
        } else {
            ITONTokenWallet(msg.sender).transfer{value: 0, flag: MessageFlags.ALL_NOT_RESERVED}(
                senderWallet,
                amount,
                0,
                originalGasTo,
                false,
                empty
            );
        }
    }

    function buildLevel3(uint32 id, address proxy, uint160 evmAddress, uint32 chainId) external pure returns(TvmCell) {

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

        if (functionId == tvm.functionId(IRootTokenContract.getWalletAddress) ||
            functionId == tvm.functionId(ITONTokenWallet.setReceiveCallback))
        {
            factory.transfer({value: 0, flag: MessageFlags.ALL_NOT_RESERVED + MessageFlags.DESTROY_IF_ZERO, bounce: false});
        }
    }

    function _reserve() private view inline {
        tvm.rawReserve(StrategyGas.INITIAL_BALANCE, 0);
    }
}
