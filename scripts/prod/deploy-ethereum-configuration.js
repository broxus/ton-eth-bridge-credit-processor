const {
  logContract,
  isValidTonAddress,
  stringToBytesArray,
} = require('../../node_modules/bridge/free-ton/test/utils');

const prompts = require('prompts');
const fs = require('fs');
const ethers = require('ethers');
const ora = require('ora');
const BigNumber = require('bignumber.js');


const main = async () => {
  const [keyPair] = await locklift.keys.getKeyPairs();

  // Get all contracts from the build
  const build = [...new Set(fs.readdirSync('build').map(o => o.split('.')[0]))];

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
      ],
    },
    {
      type: 'text',
      name: 'eventEmitter',
      message: 'Contract address, which emits event (Ethereum)',
      validate: value => ethers.utils.isAddress(value) ? true : 'Invalid Ethereum address'
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
  const EthereumEvent = await locklift.factory.getContract('CreditTokenTransferEthereumEvent');

  const spinner = ora('Deploying Ethereum event configuration').start();

  const ethereumEventConfiguration = await locklift.giver.deployContract({
    contract: EthereumEventConfiguration,
    constructorParams: {
      _owner: response.owner,
      _meta: response.meta,
    },
    initParams: {
      basicConfiguration: {
        eventABI: stringToBytesArray(JSON.stringify(ethereumEventAbi)),
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

  spinner.stop();

  await logContract(ethereumEventConfiguration);
};


main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
