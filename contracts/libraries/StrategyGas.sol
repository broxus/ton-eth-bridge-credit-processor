pragma ton-solidity >= 0.39.0;

library StrategyGas {

    uint128 constant DEPLOY_VALUE                   = 2 ton;
    uint128 constant INITIAL_BALANCE                = 1 ton;
    uint128 constant MIN_CALLBACK_VALUE             = 3 ton;

    // TOKENS
    uint128 constant DEPLOY_EMPTY_WALLET_VALUE      = 0.5 ton;
    uint128 constant DEPLOY_EMPTY_WALLET_GRAMS      = 0.1 ton;
    uint128 constant TRANSFER_TO_RECIPIENT_VALUE    = 0.5 ton;
    uint128 constant SET_RECEIVE_CALLBACK_VALUE     = 0.01 ton;
}
