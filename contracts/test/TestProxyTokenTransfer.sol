pragma ton-solidity >= 0.57.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "ton-eth-bridge-contracts/everscale/contracts/bridge/proxy/ProxyTokenTransfer.sol";

contract TestProxyTokenTransfer is ProxyTokenTransfer {
    constructor(address owner_) ProxyTokenTransfer(owner_) public {}
}
