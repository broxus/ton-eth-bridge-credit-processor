const {getRandomNonce, Migration, afterRun, DEX_CONTRACTS_PATH} = require(process.cwd()+'/scripts/utils')
const { Command } = require('commander');
const program = new Command();

program
    .allowUnknownOption()
    .option('-pcn, --pair_contract_name <pair_contract_name>', 'DexPair contract name')
    .option('-acn, --account_contract_name <account_contract_name>', 'DexAccount contract name');

program.parse(process.argv);

const options = program.opts();
options.pair_contract_name = options.pair_contract_name || 'DexPair';
options.account_contract_name = options.account_contract_name || 'DexAccount';

let tx;
const displayTx = (_tx) => {
  console.log(`txId: ${_tx.transaction.id}`);
};

async function main() {
  const migration = new Migration();
  const account = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account1');
  account.afterRun = afterRun;

  const DexPlatform = await locklift.factory.getContract('DexPlatform', DEX_CONTRACTS_PATH);
  const DexAccount = await locklift.factory.getContract(options.account_contract_name, DEX_CONTRACTS_PATH);
  const DexPair = await locklift.factory.getContract(options.pair_contract_name, DEX_CONTRACTS_PATH);
  const DexVaultLpTokenPending = await locklift.factory.getContract('DexVaultLpTokenPending', DEX_CONTRACTS_PATH);

  const [keyPair] = await locklift.keys.getKeyPairs();

  const DexRoot = await locklift.factory.getContract('DexRoot', DEX_CONTRACTS_PATH);
  console.log(`Deploying DexRoot...`);
  const dexRoot = await locklift.giver.deployContract({
    contract: DexRoot,
    constructorParams: {
      initial_owner: account.address,
      initial_vault: locklift.ton.zero_address
    },
    initParams: {
      _nonce: getRandomNonce(),
    },
    keyPair,
  }, locklift.utils.convertCrystal(2, 'nano'));
  console.log(`DexRoot address: ${dexRoot.address}`);

  const DexVault = await locklift.factory.getContract('DexVault', DEX_CONTRACTS_PATH);
  console.log(`Deploying DexVault...`);
  const dexVault = await locklift.giver.deployContract({
    contract: DexVault,
    constructorParams: {
      owner_: account.address,
      token_factory_: migration.load(await locklift.factory.getContract('TokenFactory', DEX_CONTRACTS_PATH), 'TokenFactory').address,
      root_: dexRoot.address
    },
    initParams: {
      _nonce: getRandomNonce(),
    },
    keyPair,
  }, locklift.utils.convertCrystal(2, 'nano'));
  console.log(`DexVault address: ${dexVault.address}`);

  console.log(`DexVault: installing Platform code...`);
  tx = await account.runTarget({
    contract: dexVault,
    method: 'installPlatformOnce',
    params: {code: DexPlatform.code},
    keyPair
  });
  displayTx(tx);

  console.log(`DexVault: installing VaultLpTokenPending code...`);
  tx = await account.runTarget({
    contract: dexVault,
    method: 'installOrUpdateLpTokenPendingCode',
    params: {code: DexVaultLpTokenPending.code},
    keyPair
  });
  displayTx(tx);

  console.log(`DexRoot: installing vault address...`);
  tx = await account.runTarget({
    contract: dexRoot,
    method: 'setVaultOnce',
    params: {new_vault: dexVault.address},
    keyPair
  });
  displayTx(tx);

  console.log(`DexRoot: installing Platform code...`);
  tx = await account.runTarget({
    contract: dexRoot,
    method: 'installPlatformOnce',
    params: {code: DexPlatform.code},
    keyPair
  });
  displayTx(tx);

  console.log(`DexRoot: installing DexAccount code...`);
  tx = await account.runTarget({
    contract: dexRoot,
    method: 'installOrUpdateAccountCode',
    params: {code: DexAccount.code},
    keyPair
  });
  displayTx(tx);

  console.log(`DexRoot: installing DexPair code...`);
  tx = await account.runTarget({
    contract: dexRoot,
    method: 'installOrUpdatePairCode',
    params: {code: DexPair.code},
    keyPair
  });
  displayTx(tx);

  console.log(`DexRoot: set Dex is active...`);
  tx = await account.runTarget({
    contract: dexRoot,
    method: 'setActive',
    params: {new_active: true},
    keyPair
  });
  displayTx(tx);

  migration.store(dexRoot, 'DexRoot');
  migration.store(dexVault, 'DexVault');
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
