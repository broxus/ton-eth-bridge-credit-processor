locklift build --config locklift.config.js

#prepare pair
locklift run --config locklift.config.js --disable-build --network local --script scripts/0-reset-migration.js
locklift run --config locklift.config.js --disable-build --network local --script scripts/5-deploy-account.js --key_number='0' --balance='15'
locklift run --config locklift.config.js --disable-build --network local --script scripts/5-deploy-account.js --key_number='1' --balance='1250'
locklift run --config locklift.config.js --disable-build --network local --script scripts/5-deploy-account.js --key_number='2' --balance='15'
locklift run --config locklift.config.js --disable-build --network local --script scripts/10-deploy-TokenFactory.js
locklift run --config locklift.config.js --disable-build --network local --script scripts/15-deploy-vault-and-root.js --pair_contract_name='DexPairV3' --account_contract_name='DexAccountV2'
locklift run --config locklift.config.js --disable-build --network local --script scripts/20-wton-setup.js --wrap_amount=100
locklift run --config locklift.config.js --disable-build --network local --script scripts/25-deploy-test-tokens.js --tokens='["tst"]'
locklift run --config locklift.config.js --disable-build --network local --script scripts/30-mint-test-tokens.js --mints='[{"account":2,"amount":100000,"token":"tst"}]'
locklift run --config locklift.config.js --disable-build --network local --script scripts/35-deploy-test-dex-account.js --owner_n='2' --contract_name='DexAccountV2'
locklift run --config locklift.config.js --disable-build --network local --script scripts/40-deploy-test-pair.js --pairs='[["tst", "wton"]]' --contract_name='DexPairV3'
locklift test --config locklift.config.js --disable-build --network local --tests test/45-add-pair-test.js --left='tst' --right='wton' --account=2 --contract_name='DexPairV3' --ignore_already_added='true'
locklift test --config locklift.config.js --disable-build --network local --tests test/50-deposit-to-dex-account.js --deposits='[{ "tokenId": "tst", "amount": 900 }, { "tokenId": "wton", "amount": 90 }]'
locklift test --config locklift.config.js --disable-build --network local --tests test/55-pair-deposit-liquidity.js --left_token_id 'tst' --right_token_id 'wton' --left_amount '900' --right_amount '90' --auto_change 'false' --contract_name='DexPairV3'
locklift run --config locklift.config.js --disable-build --network local --script scripts/59-hardcode-addresses.js
