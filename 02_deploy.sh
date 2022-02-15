npx locklift build --config locklift.config.js

npx locklift run --disable-build --config locklift.config.js --network dev --script scripts/60-deploy-test-bridge-configuration.js --token='tst'

# деплой и настройка CreditFactory
npx locklift run --disable-build --config locklift.config.js --network dev --script scripts/65-deploy-credit-factory.js

npx locklift run --disable-build --config locklift.config.js --network dev --script scripts/75-deploy-strategy-factory.js
npx locklift run --disable-build --config locklift.config.js --network dev --script scripts/76-deploy-strategy.js
