pragma ton-solidity >= 0.57.0;

pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./HiddenBridgeStrategy.sol";

import "../libraries/StrategyGas.sol";
import "../libraries/MessageFlags.sol";
import "@broxus/contracts/contracts/utils/RandomNonce.sol";

contract HiddenBridgeStrategyFactory is RandomNonce {
    TvmCell public strategyCode;

    constructor(TvmCell code) public {
        tvm.accept();
        strategyCode = code;
    }

    function deployStrategy(address tokenRoot) public {
        _reserve();

        new HiddenBridgeStrategy {
            value: 0,
            flag: MessageFlags.ALL_NOT_RESERVED,
            stateInit: _buildInitData(tokenRoot)
        }(msg.sender);

    }

    function buildLayer3(uint32 id, address proxy, uint160 evmAddress, uint32 chainId) external pure returns(TvmCell) {

        TvmBuilder b;

        b.store(id);
        b.store(proxy);
        b.store(evmAddress);
        b.store(chainId);

        return b.toCell();
    }

    function getStrategyAddress(address tokenRoot) external view responsible returns(address) {
        return { value: 0, bounce: false, flag: MessageFlags.REMAINING_GAS } address(tvm.hash(_buildInitData(tokenRoot)));
    }

    function _buildInitData(address tokenRoot) private view returns(TvmCell) {
        return tvm.buildStateInit({
            contr: HiddenBridgeStrategy,
            varInit: {
                factory: address(this),
                tokenRoot: tokenRoot
            },
            pubkey: 0,
            code: strategyCode
        });
    }

    function _reserve() private view inline {
        tvm.rawReserve(math.max(StrategyGas.INITIAL_BALANCE, address(this).balance - msg.value), 0);
    }
}
