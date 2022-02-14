pragma ton-solidity >= 0.57.0;

library HiddenBridgeStrategyErrorCodes {
    uint16 constant NOT_PERMITTED                   = 1000;
    uint16 constant WRONG_STATE                     = 1001;
    uint16 constant NON_EMPTY_TOKEN_WALLET          = 1500;

    uint16 constant LOW_GAS                         = 2000;
}
