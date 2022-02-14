pragma ton-solidity >= 0.57.0;

library CreditGas {
    // BASE
    uint128 constant MAX_FWD_FEE                            = 0.1 ton;
    uint128 constant MIN_BALANCE                            = 0.1 ton;

    uint128 constant CREDIT_BODY                            = 5 ton;
    uint128 constant DEPLOY_PROCESSOR                       = 0.2 ton;
    uint128 constant MIN_CALLBACK_VALUE                     = 0.1 ton;
    uint128 constant READY_TO_PROCESS_CALLBACK_VALUE        = 0.1 ton;

    // EVENT
    uint128 constant DERIVE_EVENT_ADDRESS                   = 0.2 ton;
    uint128 constant GET_EVENT_CONFIG_DETAILS               = 1 ton;
    uint128 constant GET_PROXY_TOKEN_ROOT                   = 0.2 ton;

    // TOKENS
    uint128 constant CHECK_BALANCE                          = 0.1 ton;
    uint128 constant TRANSFER_TOKENS_VALUE                  = 0.5 ton;
    uint128 constant DEPLOY_EMPTY_WALLET_VALUE              = 0.5 ton;
    uint128 constant DEPLOY_EMPTY_WALLET_GRAMS              = 0.1 ton;
    uint128 constant GET_WALLET_ADDRESS_VALUE               = 0.1 ton;
    uint128 constant SET_RECEIVE_CALLBACK_VALUE             = 0.01 ton;
    uint128 constant SET_BOUNCED_CALLBACK_VALUE             = 0.01 ton;
    uint128 constant GET_TOKEN_WALLET_DETAILS               = 0.2 ton;

    // WTON
    uint128 constant UNWRAP_VALUE                           = 0.5 ton;

    // DEX
    uint128 constant GET_EXPECTED_SPENT_AMOUNT              = 0.1 ton;
    uint128 constant GET_DEX_VAULT                          = 0.1 ton;
    uint128 constant GET_DEX_PAIR_ADDRESS                   = 0.1 ton;

    uint128 constant UNWRAP_MIN_VALUE                       = 0.6 ton; //UNWRAP_VALUE + MAX_FWD_FEE;
    uint128 constant SWAP_VALUE                             = 2.5 ton; // 2 ton + TRANSFER_TOKENS_VALUE;
    uint128 constant SWAP_MIN_BALANCE                       = 2.7 ton; //SWAP_VALUE + MAX_FWD_FEE + MIN_BALANCE;
    uint128 constant GET_EXPECTED_SPENT_AMOUNT_MIN_BALANCE  = 2.9 ton; //GET_EXPECTED_SPENT_AMOUNT + MAX_FWD_FEE + SWAP_MIN_BALANCE;
    uint128 constant RETRY_SWAP_MIN_BALANCE                 = 3.1 ton; // CHECK_BALANCE + MAX_FWD_FEE + GET_EXPECTED_SPENT_AMOUNT_MIN_BALANCE;
    uint128 constant RETRY_SWAP_MIN_VALUE                   = 3 ton; //RETRY_SWAP_MIN_BALANCE - MIN_BALANCE;

    uint128 constant END_PROCESS_MIN_VALUE                  = 1 ton;

    uint128 constant UPGRADE_FACTORY_MIN_BALANCE            = 10 ton;
}
