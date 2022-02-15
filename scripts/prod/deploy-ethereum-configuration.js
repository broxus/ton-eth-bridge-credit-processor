const {
    logContract,
    isValidTonAddress,
    stringToBytesArray,
    DEX_CONTRACTS_PATH,
    EMPTY_TVM_CELL
} = require('./../utils');

const prompts = require('prompts');
const fs = require('fs');
const BigNumber = require('bignumber.js');

// FIXME:
const ETHEREUM_BRIDGE_ABI_PATH = '/path/to/bridge-contracts/ethereum/abi'

const main = async () => {
    const [keyPair] = await locklift.keys.getKeyPairs();

    // Get all contracts from the build
    const build = [...new Set(fs.readdirSync('build').map(o => o.split('.')[0]))];

    const events = fs.readdirSync(ETHEREUM_BRIDGE_ABI_PATH);

    const {
        eventAbiFile
    } = await prompts({
        type: 'select',
        name: 'eventAbiFile',
        message: 'Select Ethereum ABI, which contains target event',
        choices: events.map(e => new Object({ title: e, value: e }))
    });

    const abi = JSON.parse(fs.readFileSync(`${ETHEREUM_BRIDGE_ABI_PATH}/${eventAbiFile}`));

    const {
        event
    } = await prompts({
        type: 'select',
        name: 'event',
        message: 'Choose Ethereum event',
        choices: abi
            .filter(o => o.type == 'event' && o.anonymous == false)
            .map(event => {
                return {
                    title: `${event.name} (${event.inputs.map(i => i.type.concat(' ').concat(i.name)).join(',')})`,
                    value: event,
                }
            }),
    });

    const response = await prompts([
        {
            type: 'text',
            name: 'owner',
            message: 'Initial configuration owner',
            validate: value => isValidTonAddress(value) ? true : 'Invalid TON address'
        },
        {
            type: 'text',
            name: 'staking',
            message: 'Staking contract',
            validate: value => isValidTonAddress(value) ? true : 'Invalid TON address'
        },
        {
            type: 'number',
            name: 'eventInitialBalance',
            initial: 2,
            message: 'Event initial balance (in TONs)'
        },
        {
            type: 'select',
            name: 'eventContract',
            message: 'Choose event contract',
            choices: build.map(c => new Object({ title: c, value: c }))
        },
        {
            type: 'text',
            name: 'meta',
            message: 'Configuration meta, can be empty (TvmCell encoded)',
        },
        {
            type: 'select',
            name: 'chainId',
            message: 'Choose network',
            choices: [
                { title: 'Goerli',  value: 5 },
                { title: 'Ropsten',  value: 3 },
                { title: 'Ethereum',  value: 1 },
                { title: 'BSC',  value: 56 },
                { title: 'Fantom',  value: 250 },
                { title: 'Polygon',  value: 137 },
            ],
        },
        {
            type: 'text',
            name: 'eventEmitter',
            message: 'Contract address, which emits event (Ethereum)'
        },
        {
            type: 'number',
            name: 'eventBlocksToConfirm',
            message: 'Blocks to confirm',
            initial: 12,
        },
        {
            type: 'text',
            name: 'proxy',
            message: 'Target address in FreeTON (proxy)',
            validate: value => isValidTonAddress(value) ? true : 'Invalid TON address'
        },
        {
            type: 'number',
            name: 'startBlockNumber',
            message: 'Start block number'
        },
        {
            type: 'number',
            name: 'value',
            message: 'Configuration initial balance (in TONs)',
            initial: 10
        },
    ]);

    const EthereumEventConfiguration = await locklift.factory.getContract('CreditEthereumEventConfiguration');
    const EthereumEvent = await locklift.factory.getContract(response.eventContract);

    console.log('Deploying Ethereum event configuration');

    const Account = await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH);

    let account = await locklift.giver.deployContract({
        contract: Account,
        constructorParams: {},
        initParams: {
            _randomNonce: Math.random() * 6400 | 0,
        },
        keyPair,
    }, locklift.utils.convertCrystal('1', 'nano'));
    console.log(`Account: ${account.address}`);

    const ethereumEventConfiguration = await locklift.giver.deployContract({
        contract: EthereumEventConfiguration,
        constructorParams: {
            _owner: account.address,
            _meta: response.meta,
            _creditProcessorCode: EMPTY_TVM_CELL
        },
        initParams: {
            basicConfiguration: {
                eventABI: stringToBytesArray(JSON.stringify(event)),
                eventInitialBalance: locklift.utils.convertCrystal(response.eventInitialBalance, 'nano'),
                staking: response.staking,
                eventCode: EthereumEvent.code,
            },
            networkConfiguration: {
                chainId: response.chainId,
                eventEmitter: new BigNumber(response.eventEmitter.toLowerCase()).toFixed(),
                eventBlocksToConfirm: response.eventBlocksToConfirm,
                proxy: response.proxy,
                startBlockNumber: response.startBlockNumber,
                endBlockNumber: 0,
            }
        },
        keyPair
    }, locklift.utils.convertCrystal(response.value, 'nano'));

    const CreditProcessor = await locklift.factory.getContract('CreditProcessor');

    console.log(`CreditEthereumEventConfiguration.setCreditProcessorCode`);
    await account.runTarget({
        contract: ethereumEventConfiguration,
        method: 'setCreditProcessorCode',
        params: {
            value: CreditProcessor.code
        },
        value: locklift.utils.convertCrystal(0.2, 'nano'),
        keyPair
    });

    console.log(`CreditEthereumEventConfiguration.transferOwner`);
    await account.runTarget({
        contract: ethereumEventConfiguration,
        method: 'transferOwnership',
        params: {
            newOwner: response.owner
        },
        value: locklift.utils.convertCrystal(0.2, 'nano'),
        keyPair
    });

    await logContract(ethereumEventConfiguration);
};


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
