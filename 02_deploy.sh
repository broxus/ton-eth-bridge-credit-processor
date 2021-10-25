locklift build --config locklift.config.js

locklift run --disable-build --config locklift.config.js --network local --script scripts/60-deploy-test-bridge-configuration.js --token='tst'

# деплой и настройка CreditFactory
locklift run --disable-build --config locklift.config.js --network local --script scripts/65-deploy-credit-factory.js
