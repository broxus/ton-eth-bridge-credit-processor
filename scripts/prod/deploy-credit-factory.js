const {Migration, DEX_CONTRACTS_PATH, getRandomNonce} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

// FIXME: msg address
const admin = ''
// FIXME: backend and managers public keys
const managers = []

async function main() {
    console.log(`deploy-credit-factory.js`);
    const keyPairs = await locklift.keys.getKeyPairs();

    const CreditFactory = await locklift.factory.getContract('CreditFactory');

    console.log(`Deploying CreditFactory`);
    const creditFactory = await locklift.giver.deployContract({
        contract: CreditFactory,
        constructorParams: {
            admin_: admin,
            owners_: managers.map(v => new BigNumber(v, 16).toString(10)),
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
