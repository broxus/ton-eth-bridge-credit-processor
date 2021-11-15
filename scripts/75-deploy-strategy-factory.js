const {Migration, DEX_CONTRACTS_PATH, getRandomNonce} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

async function main() {
    console.log(`75-deploy-hidden-bridge-strategy.js`);
    const keyPairs = await locklift.keys.getKeyPairs();

    const HiddenBridgeStrategyFactory = await locklift.factory.getContract('HiddenBridgeStrategyFactory');
    const HiddenBridgeStrategy = await locklift.factory.getContract('HiddenBridgeStrategy');

    console.log(`Deploying HiddenBridgeStrategyFactory`);
    const strategyFactory = await locklift.giver.deployContract({
        contract: HiddenBridgeStrategyFactory,
        constructorParams: {
            code: HiddenBridgeStrategy.code
        },
        initParams: {
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[0],
    }, locklift.utils.convertCrystal(5, 'nano'));

    migration.store(strategyFactory, 'HiddenBridgeStrategyFactory');
    console.log(`HiddenBridgeStrategyFactory: ${strategyFactory.address}`);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
