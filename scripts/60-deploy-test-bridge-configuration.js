const {Migration, DEX_CONTRACTS_PATH, stringToBytesArray, BRIDGE_CONTRACTS_PATH, EMPTY_TVM_CELL,
    getRandomNonce, TOKEN_CONTRACTS_PATH, Constants} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

const logTx = (tx) => console.log(`Transaction: ${tx.transaction.id}`);

program
  .allowUnknownOption()
  .option('-t, --token <token>', 'token');

program.parse(process.argv);

const options = program.opts();

options.token = options.token || 'tst';

async function main() {
    console.log(`60-deploy-test-bridge-configuration.js`);
    const token = Constants.tokens[options.token];
    const account = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account1');
    const [keyPair] = await locklift.keys.getKeyPairs();

    const tokenRoot = migration.load(
        await locklift.factory.getContract('TokenRootUpgradeable', TOKEN_CONTRACTS_PATH), token.symbol + 'Root'
    );

    const ethereumEventAbi = {
            "name": "LandOnFreeTON",
            "type": "event",
            "inputs": [
                { "name": "amount",                 "type": "uint128" },
                { "name": "wid",                    "type": "int8" },
                { "name": "user",                   "type": "uint256" },
                { "name": "creditor",               "type": "uint256" },
                { "name": "recipient",              "type": "uint256" },

                { "name": "tokenAmount",            "type": "uint128" },
                { "name": "tonAmount",              "type": "uint128" },
                { "name": "swapType",               "type": "uint8" },
                { "name": "slippageNumerator",      "type": "uint128" },
                { "name": "slippageDenominator",    "type": "uint128" },

                { "name": "separator",              "type": "bytes1" }, // == 0x03

                { "name": "level3",                 "type": "bytes" }
            ],
            "outputs":[]
        };
    console.log(`Ethereum event ABI: ${JSON.stringify(ethereumEventAbi)}`);

    const CreditProcessor = await locklift.factory.getContract('CreditProcessor');
    const TestEthereumEventConfiguration = await locklift.factory.getContract('TestEthereumEventConfiguration');
    const TestEthereumEvent = await locklift.factory.getContract('TestEthereumEvent');
    const ProxyTokenTransfer = await locklift.factory.getContract('TestProxyTokenTransfer');

    console.log(`Deploying TestProxyTokenTransfer`);
    const proxyTokenTransfer = await locklift.giver.deployContract({
        contract: ProxyTokenTransfer,
        constructorParams: {
          owner_: account.address
        },
        initParams: {},
        keyPair
    }, locklift.utils.convertCrystal(10, 'nano'));
    migration.store(proxyTokenTransfer, token.symbol + 'ProxyTokenTransfer');
    console.log(`${token.symbol}ProxyTokenTransfer: ${proxyTokenTransfer.address}`);

    console.log(`Deploying TestEthereumEventConfiguration`);
    const initParams = {
        basicConfiguration: {
            eventABI: stringToBytesArray(JSON.stringify(ethereumEventAbi)),
            eventInitialBalance: locklift.utils.convertCrystal('2', 'nano'),
            staking: locklift.utils.zeroAddress,
            eventCode: TestEthereumEvent.code,
        },
        networkConfiguration: {
            chainId: '0',
            eventEmitter: '0',
            eventBlocksToConfirm: '1',
            proxy: proxyTokenTransfer.address,
            startBlockNumber: '0',
            endBlockNumber: '0',
        }
    };
    const testEthereumEventConfiguration = await locklift.giver.deployContract({
        contract: TestEthereumEventConfiguration,
        constructorParams: {},
        initParams,
        keyPair
    }, locklift.utils.convertCrystal(20, 'nano'));
    migration.store(testEthereumEventConfiguration, token.symbol + 'TestEthereumEventConfiguration');
    console.log(`TestEthereumEventConfiguration: ${testEthereumEventConfiguration.address}`);

    console.log(`TestEthereumEventConfiguration.setCreditProcessorCode`);
    let tx = await account.runTarget({
        contract: testEthereumEventConfiguration,
        method: 'setCreditProcessorCode',
        params: {
            value: CreditProcessor.code
        },
        value: locklift.utils.convertCrystal(0.2, 'nano'),
        keyPair
    });
    logTx(tx);

    console.log(`ProxyTokenTransfer.setConfiguration`);
    tx = await account.runTarget({
        contract: proxyTokenTransfer,
        method: 'setConfiguration',
        params: {
          _config: {
            tonConfiguration: locklift.utils.zeroAddress,
            ethereumConfigurations: [
                testEthereumEventConfiguration.address
            ],
            outdatedTokenRoots: [],
            tokenRoot: tokenRoot.address,
            settingsDeployWalletGrams: locklift.utils.convertCrystal(0.1, 'nano')
          },
          gasBackAddress: account.address
        },
        value: locklift.utils.convertCrystal(0.5, 'nano'),
        keyPair
    });
    logTx(tx);

    if (token === 'wever') {
        // TODO: добавление прокси в tunnel
    } else {
        console.log(`TokenRoot.transferOwnership`);
        tx = await account.runTarget({
            contract: tokenRoot,
            method: 'transferOwnership',
            params: {
                newOwner: proxyTokenTransfer.address,
                remainingGasTo: account.address,
                callbacks: {}
            },
            value: locklift.utils.convertCrystal(0.5, 'nano'),
            keyPair
        });
        logTx(tx);
    }


    // const name = `Account${key_number+1}`;
    // migration.store(account, name);
    // console.log(`${name}: ${account.address}`);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
