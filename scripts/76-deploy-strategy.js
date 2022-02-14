const {Migration, DEX_CONTRACTS_PATH, TOKEN_CONTRACTS_PATH, getRandomNonce, Constants} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

let tokenId = 'tst';

async function main() {
    console.log(`76-deploy-strategy.js`);
    const Account1 = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account1');
    const [keyPair] = await locklift.keys.getKeyPairs();

    const token = Constants.tokens[tokenId];
    const TokenRoot = migration.load(
        await locklift.factory.getContract('TokenRootUpgradeable', TOKEN_CONTRACTS_PATH), token.symbol + 'Root'
    );

    const HiddenBridgeStrategy = await locklift.factory.getContract('HiddenBridgeStrategy');
    const HiddenBridgeStrategyFactory = await locklift.factory.getContract('HiddenBridgeStrategyFactory');
    migration.load(HiddenBridgeStrategyFactory, 'HiddenBridgeStrategyFactory');

    await Account1.runTarget({
        contract: HiddenBridgeStrategyFactory,
        method: 'deployStrategy',
        params: {
            tokenRoot: TokenRoot.address
        },
        value: locklift.utils.convertCrystal(3, 'nano'),
        keyPair
    });

   const strategyAddress = await HiddenBridgeStrategyFactory.call({
        method: 'getStrategyAddress',
        params: {
            tokenRoot: TokenRoot.address
        }
    })

    HiddenBridgeStrategy.setAddress(strategyAddress);

    migration.store(HiddenBridgeStrategy, token.symbol + 'HiddenBridgeStrategy');
    console.log(token.symbol + `HiddenBridgeStrategy: ${HiddenBridgeStrategy.address}`);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
