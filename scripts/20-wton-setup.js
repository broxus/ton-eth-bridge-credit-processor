const logger = require('mocha-logger');
const fs = require('fs');
const BigNumber = require('bignumber.js');
BigNumber.config({ EXPONENTIAL_AT: 257 });
const {Constants, Migration, afterRun, EMPTY_TVM_CELL,
    TOKEN_CONTRACTS_PATH, WTON_CONTRACTS_PATH, DEX_CONTRACTS_PATH,
    stringToBytesArray, getRandomNonce} = require(process.cwd()+'/scripts/utils');
const { Command } = require('commander');
const program = new Command();

const logTx = (tx) => logger.success(`Transaction: ${tx.transaction.id}`);

async function main() {

    console.log(`20-wton-setup.js`);
    const migration = new Migration();

    program
        .allowUnknownOption()
        .option('-wa, --wrap_amount <wrap_amount>', 'wrap amount');

    program.parse(process.argv);

    const options = program.opts();
    options.wrap_amount = options.wrap_amount || '60';

    const tokenData = Constants.tokens['wton'];


    logger.log(`Giver balance: ${locklift.utils.convertCrystal(await locklift.ton.getBalance(locklift.networkConfig.giver.address), 'ton')}`);

    const keyPairs = await locklift.keys.getKeyPairs();

    const Account2 = migration.load(await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH), 'Account2');

    Account2.afterRun = afterRun;

    logger.success(`Owner: ${Account2.address}`);

    logger.log(`Deploying WTON`);

    const RootToken = await locklift.factory.getContract(
        'RootTokenContract',
        TOKEN_CONTRACTS_PATH
    );

    const TokenWallet = await locklift.factory.getContract(
        'TONTokenWallet',
        TOKEN_CONTRACTS_PATH
    );

    const root = await locklift.giver.deployContract({
        contract: RootToken,
        constructorParams: {
            root_public_key_: `0x${keyPairs[0].public}`,
            root_owner_address_: locklift.ton.zero_address
        },
        initParams: {
            name: stringToBytesArray('Wrapped TON'),
            symbol: stringToBytesArray('WTON'),
            decimals: 9,
            wallet_code: TokenWallet.code,
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[0]
    });

    root.afterRun = afterRun;

    logger.success(`WTON root: ${root.address}`);

    logger.log(`Deploying tunnel`);

    const Tunnel = await locklift.factory.getContract('Tunnel', WTON_CONTRACTS_PATH);

    const tunnel = await locklift.giver.deployContract({
        contract: Tunnel,
        constructorParams: {
            sources: [],
            destinations: [],
            owner_: Account2.address,
        },
        initParams: {
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[0]
    }, locklift.utils.convertCrystal(5, 'nano'));

    logger.success(`Tunnel address: ${tunnel.address}`);

    logger.log(`Deploying vault`);

    const WrappedTONVault = await locklift.factory.getContract('WrappedTONVault', WTON_CONTRACTS_PATH);

    const vault = await locklift.giver.deployContract({
        contract: WrappedTONVault,
        constructorParams: {
            owner_: Account2.address,
            root_tunnel: tunnel.address,
            root: root.address,
            receive_safe_fee: locklift.utils.convertCrystal(1, 'nano'),
            settings_deploy_wallet_grams: locklift.utils.convertCrystal(0.05, 'nano'),
            initial_balance: locklift.utils.convertCrystal(1, 'nano')
        },
        initParams: {
            _randomNonce: getRandomNonce(),
        },
        keyPair: keyPairs[0]
    });

    logger.success(`Vault address: ${vault.address}`);

    logger.log(`Transferring root ownership to tunnel`);

    let tx = await root.run({
        method: 'transferOwner',
        params: {
            root_public_key_: 0,
            root_owner_address_: tunnel.address,
        },
        keyPair: keyPairs[0]
    });

    logTx(tx);

    logger.log(`Adding tunnel (vault, root)`);

    tx = await Account2.runTarget({
        contract: tunnel,
        method: '__updateTunnel',
        params: {
            source: vault.address,
            destination: root.address,
        },
        keyPair: keyPairs[1]
    });

    logTx(tx);

    logger.log(`Draining vault`);

    tx = await Account2.runTarget({
        contract: vault,
        method: 'drain',
        params: {
            receiver: Account2.address,
        },
        keyPair: keyPairs[1]
    });

    logTx(tx);

    logger.log(`Wrap ${options.wrap_amount} TON`);

    tx = await Account2.run({
        method: 'sendTransaction',
        params: {
            dest: vault.address,
            value: locklift.utils.convertCrystal(options.wrap_amount, 'nano'),
            bounce: false,
            flags: 1,
            payload: EMPTY_TVM_CELL
        },
        keyPair: keyPairs[1]
    });

    logTx(tx);

    const tokenWalletAddress = await RootToken.call({
        method: 'getWalletAddress', params: {
            wallet_public_key_: 0,
            owner_address_: Account2.address
        }
    });

    TokenWallet.setAddress(tokenWalletAddress);

    const balance = new BigNumber(await TokenWallet.call({method: 'balance'})).shiftedBy(-9).toString();
    logger.log(`Account2 WTON balance: ${balance}`);

    migration.store(TokenWallet, tokenData.symbol + 'Wallet2');
    migration.store(RootToken, `${tokenData.symbol}Root`);
    migration.store(vault, `${tokenData.symbol}Vault`);
    migration.store(tunnel.address, `${tokenData.symbol}Tunnel`);

    logger.log(`Giver balance: ${locklift.utils.convertCrystal(await locklift.ton.getBalance(locklift.networkConfig.giver.address), 'ton')}`);
}


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
