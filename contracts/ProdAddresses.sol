pragma ton-solidity >= 0.57.0;

abstract contract ProdAddresses {
    address constant DEX_ROOT = address.makeAddrStd(0, 0x5eb5713ea9b4a0f3a13bc91b282cde809636eb1e68d2fcb6427b9ad78a5a9008);
    address constant WEVER_VAULT = address.makeAddrStd(0, 0x557957cba74ab1dc544b4081be81f1208ad73997d74ab3b72d95864a41b779a4);
    address constant WEVER_ROOT = address.makeAddrStd(0, 0xa49cd4e158a9a15555e624759e2e4e766d22600b7800d891e46f9291f044a93d);
}
