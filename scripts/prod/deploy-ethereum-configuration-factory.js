let tx;
const logTx = (tx) => console.log(`Transaction: ${tx.transaction.id}`);

async function main() {
    const [keyPair] = await locklift.keys.getKeyPairs();
    const _randomNonce = locklift.utils.getRandomNonce();

    const CreditEthereumEventConfigurationFactory = await locklift.factory.getContract('CreditEthereumEventConfigurationFactory');
    const CreditEthereumEventConfiguration = await locklift.factory.getContract('CreditEthereumEventConfiguration');
    const CreditProcessor = await locklift.factory.getContract('CreditProcessor');

    console.log('Deploying Credit Ethereum event configuration factory');
    const factory = await locklift.giver.deployContract({
        contract: CreditEthereumEventConfigurationFactory,
        constructorParams: {},
        initParams: {
            _randomNonce,
        },
        keyPair
    });

    console.log(`CreditEthereumEventConfigurationFactory: ${factory.address}`);

    console.log('CreditEthereumEventConfigurationFactory.setConfigurationCodeOnce');
    tx = await factory.run({
        method: 'setConfigurationCodeOnce',
        params: {_configurationCode: CreditEthereumEventConfiguration.code},
        keyPair
    });
    logTx(tx);


    console.log('CreditEthereumEventConfigurationFactory.setCreditProcessorCodeOnce');
    tx = await factory.run({
        method: 'setCreditProcessorCodeOnce',
        params: {_creditProcessorCode: CreditProcessor.code},
        keyPair
    });
    logTx(tx);
}


main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
