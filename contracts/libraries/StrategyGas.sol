pragma ton-solidity >= 0.39.0;

library StrategyGas {
    // BASE
    uint128 constant MAX_FWD_FEE                    = 0.1 ton;
    uint128 constant MIN_BALANCE                    = 0.1 ton;

    uint128 constant GET_PROXY_CONFIG               = 1 ton;

    // TOKENS
    uint128 constant TRANSFER_TO_RECIPIENT_VALUE    = 0.5 ton;
    uint128 constant DEPLOY_EMPTY_WALLET_VALUE      = 0.5 ton;
    uint128 constant DEPLOY_EMPTY_WALLET_GRAMS      = 0.1 ton;
    uint128 constant GET_WALLET_ADDRESS_VALUE       = 0.1 ton;
    uint128 constant SET_RECEIVE_CALLBACK_VALUE     = 0.01 ton;
    uint128 constant SET_BOUNCED_CALLBACK_VALUE     = 0.01 ton;
    uint128 constant GET_TOKEN_WALLET_DETAILS       = 0.2 ton;

    uint128 constant UPGRADE_MIN_BALANCE    = 10 ton;
    uint128 constant SETUP_PROXY_MIN_BALANCE        = 5 ton;
    uint128 constant STORAGE_FEE_FROM_USERS_ON      = 1 ton;
}
