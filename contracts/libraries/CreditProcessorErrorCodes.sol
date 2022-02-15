pragma ton-solidity >= 0.57.0;

library CreditProcessorErrorCodes {
    uint16 constant NOT_PERMITTED                   = 1000;
    uint16 constant WRONG_STATE                     = 1001;
    uint16 constant EMPTY_CONFIG_ADDRESS            = 1010;
    uint16 constant EMPTY_EVENT_ADDRESS             = 1020;
    uint16 constant NON_EMPTY_EVENT_ADDRESS         = 1021;
    uint16 constant EMPTY_PROXY_ADDRESS             = 1030;
    uint16 constant NON_EMPTY_PROXY_ADDRESS         = 1031;
    uint16 constant EMPTY_TOKEN_ROOT                = 1040;
    uint16 constant NON_EMPTY_TOKEN_ROOT            = 1041;
    uint16 constant EMPTY_DEX_PAIR                  = 1050;
    uint16 constant NON_EMPTY_DEX_PAIR              = 1051;
    uint16 constant EMPTY_DEX_VAULT                 = 1060;
    uint16 constant NON_EMPTY_DEX_VAULT             = 1061;
    uint16 constant TOKEN_IS_WTON                   = 1070;
    uint16 constant WRONG_UNWRAP_PARAMS             = 1080;
    uint16 constant HAS_NOT_DEBT                    = 1090;

    uint16 constant WRONG_SLIPPAGE                  = 1130;

    uint16 constant LOW_GAS                         = 2000;
}
