const {expect} = require('chai');
const logger = require('mocha-logger');
const {Migration, afterRun, Constants, DEX_CONTRACTS_PATH} = require(process.cwd() + '/scripts/utils');
const { Command } = require('commander');
const program = new Command();
const migration = new Migration();

program
    .allowUnknownOption()
    .option('-l, --left <left>', 'left root')
    .option('-r, --right <right>', 'right root')
    .option('-a, --account <account>', 'dex account number')
    .option('-ig, --ignore_already_added <ignore_already_added>', 'ignore already added check')
    .option('-cn, --contract_name <contract_name>', 'DexPair contract name');

program.parse(process.argv);

const options = program.opts();

options.left = options.left || 'foo';
options.right = options.right || 'bar';
options.account = options.account || 2;
options.ignore_already_added = options.ignore_already_added === 'true';
options.contract_name = options.contract_name || 'DexPair';

const tokenLeft = Constants.tokens[options.left];
const tokenRight = Constants.tokens[options.right];

let DexAccount;

let dexPair;
let dexAccount;
let account;
let left_root;
let right_root;
let lp_root;
let keyPairs;

async function logGas() {
  await migration.balancesCheckpoint();
  const diff = await migration.balancesLastDiff();
  if (diff) {
    logger.log(`### GAS STATS ###`);
    for (let alias in diff) {
      logger.log(`${alias}: ${diff[alias].gt(0) ? '+' : ''}${diff[alias].toFixed(9)} TON`);
    }
  }
}

describe('Check DexAccount add Pair', async function () {
  this.timeout(Constants.TESTS_TIMEOUT);
  before('Load contracts', async function () {
    keyPairs = await locklift.keys.getKeyPairs();
    DexAccount = await locklift.factory.getContract('DexAccount', DEX_CONTRACTS_PATH);
    account = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account' + options.account);
    account.afterRun = afterRun;
    dexAccount = migration.load(DexAccount, 'DexAccount' + options.account);
    dexPair = migration.load(await locklift.factory.getContract(options.contract_name, DEX_CONTRACTS_PATH), 'DexPair' + tokenLeft.symbol + tokenRight.symbol);
    let dexPairFooBarRoots = await dexPair.call({method: 'getTokenRoots'});
    left_root = dexPairFooBarRoots.left;
    right_root = dexPairFooBarRoots.right;
    lp_root = dexPairFooBarRoots.lp;
    await migration.balancesCheckpoint();
  })

  if (!options.ignore_already_added) {
    describe('Check pair not added already', async function () {
      it('Check DexAccount pair wallets', async function () {
        expect((await dexAccount.call({method: 'getWalletData', params: {token_root: left_root}})).wallet)
          .to
          .equal(locklift.ton.zero_address, 'DexAccount wallet address for LeftRoot is not empty');
        expect((await dexAccount.call({method: 'getWalletData', params: {token_root: right_root}})).wallet)
          .to
          .equal(locklift.ton.zero_address, 'DexAccount wallet address for RightRoot is not empty');
        expect((await dexAccount.call({method: 'getWalletData', params: {token_root: lp_root}})).wallet)
          .to
          .equal(locklift.ton.zero_address, 'DexAccount wallet address for LPRoot is not empty');
      });
    });
  }
  describe('Add new DexPair to DexAccount', async function () {
    before('Adding new pair', async function () {
      let tx = await account.runTarget({
        contract: dexAccount,
        method: 'addPair',
        params: {
          left_root,
          right_root
        },
        value: locklift.utils.convertCrystal(3.1, 'nano'),
        keyPair: keyPairs[options.account - 1]
      });
      logger.log(`txId: ${tx.transaction.id}`);
      await afterRun();
      await logGas();
    });
    it('Check FooBar pair in DexAccount2', async function () {
      expect((await dexAccount.call({method: 'getWalletData', params: {token_root: left_root}})).wallet)
        .to
        .not.equal(locklift.ton.zero_address, 'DexAccount wallet address for LeftRoot is empty');
      expect((await dexAccount.call({method: 'getWalletData', params: {token_root: right_root}})).wallet)
        .to
        .not.equal(locklift.ton.zero_address, 'DexAccount wallet address for RightRoot is empty');
      expect((await dexAccount.call({method: 'getWalletData', params: {token_root: lp_root}})).wallet)
        .to
        .not.equal(locklift.ton.zero_address, 'DexAccount wallet address for LPRoot is empty');
    });
  });
});
