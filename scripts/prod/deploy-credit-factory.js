const {Migration, DEX_CONTRACTS_PATH, getRandomNonce} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

// FIXME:
const admin = ''
const additionalOwner = ''

async function main() {
    console.log(`deploy-credit-factory.js`);
    const Account1 = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account1');
    const keyPairs = await locklift.keys.getKeyPairs();

    const CreditProcessor = await locklift.factory.getContract('CreditProcessor');
    const CreditFactory = await locklift.factory.getContract('CreditFactory');

    console.log(`Deploying CreditFactory`);
    const creditFactory = await locklift.giver.deployContract({
        contract: CreditFactory,
        constructorParams: {
            admin_: admin,
            owners_: [new BigNumber(additionalOwner, 16).toString(10)],
            fee: locklift.utils.convertCrystal('0.1', 'nano')
        },
        initParams: {
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[4],
    }, locklift.utils.convertCrystal(100, 'nano'));

    migration.store(creditFactory, 'CreditFactory');
    console.log(`CreditFactory: ${creditFactory.address}`);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });