const {Migration, DEX_CONTRACTS_PATH, getRandomNonce} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

async function main() {
    console.log(`65-deploy-credit-factory.js`);
    const Account1 = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account1');
    const keyPairs = await locklift.keys.getKeyPairs();

    const CreditProcessor = await locklift.factory.getContract('CreditProcessor');
    const CreditFactory = await locklift.factory.getContract('CreditFactory');

    console.log(`Deploying CreditFactory`);
    const creditFactory = await locklift.giver.deployContract({
        contract: CreditFactory,
        constructorParams: {
            admin_: Account1.address,
            owners_: [new BigNumber(keyPairs[4].public, 16).toString(10)],
            fee: locklift.utils.convertCrystal('0.1', 'nano')
        },
        initParams: {
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[4],
    }, locklift.utils.convertCrystal(100, 'nano'));

    migration.store(creditFactory, 'CreditFactory');
    console.log(`CreditFactory: ${creditFactory.address}`);

    console.log(`CreditFactory.setCreditProcessorCode`);
    await creditFactory.run({
        contract: creditFactory,
        method: 'setCreditProcessorCode',
        params: {
            value: CreditProcessor.code
        },
        keyPair: keyPairs[4],
    });

    console.log(`CreditFactory.addOwner(Account1)`);
    await creditFactory.run({
        contract: creditFactory,
        method: 'addOwner',
        params: {
            newOwner: new BigNumber(Account1.address.substr(2), 16).toString(10)
        },
        keyPair: keyPairs[4],
    });
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
