pragma ton-solidity >= 0.57.0;

library CreditFactoryErrorCodes {
    uint16 constant NOT_PERMITTED                   = 1000;
    uint16 constant TOO_HIGH_FEE                    = 1070;
    uint16 constant WRONG_CREDITOR                  = 1080;
    uint16 constant WRONG_USER                      = 1090;
    uint16 constant WRONG_RECIPIENT                 = 1100;
    uint16 constant LOW_TON_AMOUNT                  = 1110;
    uint16 constant WRONG_TOKEN_AMOUNT              = 1120;
    uint16 constant WRONG_SWAP_TYPE                 = 1130;
    uint16 constant WRONG_SLIPPAGE                  = 1140;
    uint16 constant INVALID_EVENT_DATA              = 1150;
    uint16 constant WRONG_WID                       = 1160;
    uint16 constant WRONG_AMOUNT                    = 1170;
    uint16 constant WRONG_ADMIN                     = 1180;

    uint16 constant LOW_GAS                         = 2000;
}
