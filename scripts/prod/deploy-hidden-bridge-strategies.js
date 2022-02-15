const {Migration, DEX_CONTRACTS_PATH, TOKEN_CONTRACTS_PATH, getRandomNonce, Constants} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();
const https = require('https');


let tokens = [];

https.get('https://raw.githubusercontent.com/broxus/ton-assets/migration-1/manifest.json', (res) => {
    let body = "";

    res.on("data", (chunk) => {
        body += chunk;
    });

    res.on("end", () => {
        try {
            let json = JSON.parse(body);
            tokens = json.tokens;

            main()
                .then(() => process.exit(0))
                .catch(e => {
                    console.log(e);
                    process.exit(1);
                });

        } catch (error) {
            console.error(error.message);
        }
    });
}).on("error", (error) => {
    console.error(error.message);
});

program
    .allowUnknownOption()
    .option('-f, --factory <factory>', 'factory');

program.parse(process.argv);

const options = program.opts();

async function main() {
    console.log(`deploy-hidden-bridge-strategies.js`);
    console.log(`Deploy strategy for ${tokens.length} tokens`);

    if (tokens.length === 0) {
        return;
    }

    const [keyPair] = await locklift.keys.getKeyPairs();
    const Account = await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH);

    let account = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: Math.random() * 6400 | 0,
        },
        keyPair,
    }, locklift.utils.convertCrystal('100', 'nano'));
    console.log(`Account: ${account.address}`);

    const HiddenBridgeStrategyFactory = await locklift.factory.getContract('HiddenBridgeStrategyFactory');
    HiddenBridgeStrategyFactory.setAddress(options.factory);

    for (let token of tokens) {
        console.log(``);
        console.log(`${token.symbol}: `);
        const HiddenBridgeStrategy = await locklift.factory.getContract('HiddenBridgeStrategy');
        const strategyAddress = await HiddenBridgeStrategyFactory.call({
            method: 'getStrategyAddress',
            params: {
                tokenRoot: token.address
            }
        })
        HiddenBridgeStrategy.setAddress(strategyAddress);

        let isDeployed = false;
        try {
            const details = await HiddenBridgeStrategy.call({
                method: 'getDetails',
                params: {}
            })
            if (details.factory_ === options.factory) {
                console.log(`Already exists: ${strategyAddress}`);
                console.log(details);
                isDeployed = true;
            }
        } catch (e) {}

        if(!isDeployed) {
            await Account.runTarget({
                contract: HiddenBridgeStrategyFactory,
                method: 'deployStrategy',
                params: {
                    tokenRoot: token.address
                },
                value: locklift.utils.convertCrystal(3, 'nano'),
                keyPair
            });
            console.log(`Deployed: ${strategyAddress}`);
        }
    }
}
