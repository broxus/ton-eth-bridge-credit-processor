pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "../../node_modules/bridge/free-ton/contracts/bridge/ProxyTokenTransfer.sol";

contract TestProxyTokenTransfer is ProxyTokenTransfer {
    constructor(address owner_) ProxyTokenTransfer(owner_) public {}
}
