const {expect} = require('chai');
const {Migration, afterRun, Constants, DEX_CONTRACTS_PATH, EMPTY_TVM_CELL, sleep, TOKEN_CONTRACTS_PATH, getRandomNonce} = require(process.cwd() + '/scripts/utils');
const BigNumber = require('bignumber.js');
const { Command } = require('commander');
const updatedDiff = require('deep-object-diff').updatedDiff;

const program = new Command();
BigNumber.config({EXPONENTIAL_AT: 257});
const logger = require('mocha-logger');

const migration = new Migration();

program
    .allowUnknownOption()
    .option('-t, --token_id <token_id>', 'token_id')
    .option('-a, --amount <amount>', 'amount')
    .option('-st, --swap_type <swap_type>', 'swap type')
    .option('-tka, --token_amount <token_amount>', 'token amount')
    .option('-tna, --ton_amount <ton_amount>', 'ton amount')
    .option('-cb, --credit_body <credit_body>', 'credit body > 5 ton')
    .option('-l3, --layer3 <layer3>', 'layer3')
    .option('-n, --account_number <account_number>', 'layer3');

program.parse(process.argv);

const options = program.opts();

options.token_id = options.token_id || 'tst';
options.amount = options.amount || '1000';
options.swap_type = options.swap_type ? +options.swap_type : 0;
options.token_amount = options.token_amount || '0';
options.credit_body = options.credit_body || '5';
options.ton_amount = options.ton_amount || '3';
options.account_number = options.account_number || 1;


const token = Constants.tokens[options.token_id];

let keyPairs;
let User;
let CreditFactory;
let CreditProcessor;
let TestEthereumEventConfiguration;
let TokenRoot;
let CreditProcessorTokenWallet;
let UserTokenWallet;
let HiddenBridgeStrategyFactory;
let HiddenBridgeStrategy;
let ProxyTokenTransfer;
let TestEthereumEvent;
let DexPair;

let userBalancesStart;

let LAYER_3;
let EVENT_VOTE_DATA;

const LOG_FULL_GAS=true;

const states = [
    'Created',
    'EventNotDeployed', 'EventDeployInProgress', 'EventConfirmed', 'EventRejected',
    'CheckingAmount', 'CalculateSwap', 'SwapInProgress', 'SwapFailed', 'SwapUnknown',
    'UnwrapInProgress', 'UnwrapFailed',
    'DebtUnpaid',
    'Processed', 'Cancelled'
];

const eventStates = [
    'Initializing', 'Pending', 'Confirmed', 'Rejected'
];

const logTx = (tx) => logger.success(`Transaction: ${tx.transaction.id}`);

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

let lastDetails;
function showCreditProcessorDetails(details) {
    logger.log(`CreditProcessor(${CreditProcessor.address}).getDetails() result:`);

    logger.log(`{
      eventVoteData: {
        eventTransaction: ${details.eventVoteData.eventTransaction.toString()},
        eventIndex:  ${details.eventVoteData.eventIndex.toString()},
        eventData: '${details.eventVoteData.eventData}',
        eventBlockNumber: ${details.eventVoteData.eventBlockNumber.toString()},
        eventBlock: ${details.eventVoteData.eventBlock.toString()}
      },
      configuration: ${details.configuration},
      dexRoot: ${details.dexRoot},
      wtonVault: ${details.wtonVault},
      wtonRoot: ${details.wtonRoot},
      state: ${states[details.state.toNumber()]},
      eventState: ${eventStates[details.eventState.toNumber()]},
      deployer: ${details.deployer},
      debt: ${details.debt.shiftedBy(-9).toString()} TON,
      fee: ${details.fee.shiftedBy(-9).toString()} TON,
      slippage: ${details.slippage.numerator.div(details.slippage.denominator).times(100).toString()}%,
      eventAddress: ${details.eventAddress},
      tokenRoot: ${details.tokenRoot},
      tokenWallet: ${details.tokenWallet},
      wtonWallet: ${details.wtonWallet},
      dexPair: ${details.dexPair},
      dexVault: ${details.dexVault},
      swapAttempt: ${details.swapAttempt.toString()},
      swapAmount: ${details.swapAmount.shiftedBy(-token.decimals).toString()} ${token.symbol},
      unwrapAmount: ${details.unwrapAmount.shiftedBy(-9).toString()} WTON
    }`);

    lastDetails = details;
    return details;
}

async function getCreditProcessorBalances() {

    let result = {};

    await CreditProcessorTokenWallet.call({method: 'balance', params: {}}).then(n => {
        result[options.token_id] = new BigNumber(n).shiftedBy(-token.decimals).toString();
    }).catch(e => {/*ignored*/});

    result[options.token_id] = result[options.token_id];

    result.ton = (await locklift.ton.getBalance(CreditProcessor.address)).shiftedBy(-9).toString();

    return result;

}

async function getUserBalances() {

    let result = {};

    await UserTokenWallet.call({method: 'balance', params: {}}).then(n => {
        result[options.token_id] = new BigNumber(n).shiftedBy(-token.decimals).toString();
    }).catch(e => {/*ignored*/});

    try {
        result.ton = (await locklift.ton.getBalance(User.address)).shiftedBy(-9).toString();
    } catch(e) {
        /*ignored*/
    }

    return result;

}

async function logCreditProcessorBalance() {
    const balances = await getCreditProcessorBalances();

    logger.log(`CreditProcessor balance: ` +
        `${balances[options.token_id] !== undefined ? 
            balances[options.token_id] + ' ' + token.symbol : 
            '0 ' + token.symbol + ' (not deployed)'}, ` +
        `${balances.ton !== undefined ? balances.ton + ' TON' : '0 TON (not deployed)'}`);

    return balances;
}

async function logUserBalance() {
    const balances = await getUserBalances();

    logger.log(`Account${options.account_number} balance: ` +
        `${balances[options.token_id] !== undefined ? 
            balances[options.token_id] + ' ' + token.symbol :
            '0 ' + token.symbol + ' (not deployed)'}, ` +
        `${balances.ton !== undefined ? balances.ton + ' TON' : '0 TON (not deployed)'}`);

    return balances;
}

console.log(`80-hidden-bridge.js`);
console.log(`OPTIONS: `, options);

describe('Credit ETH-TON', async function () {

    this.timeout(Constants.TESTS_TIMEOUT);
    before('Load contracts', async function () {
        keyPairs = await locklift.keys.getKeyPairs();
        User = await locklift.factory.getAccount('Wallet', DEX_CONTRACTS_PATH);
        migration.load(User, 'Account' + options.account_number);
        User.afterRun = afterRun;

        CreditProcessor = await locklift.factory.getContract('CreditProcessor');
        TestEthereumEvent = await locklift.factory.getContract('TestEthereumEvent');
        DexPair = await locklift.factory.getContract('DexPair', DEX_CONTRACTS_PATH);
        TokenRoot = await locklift.factory.getContract('TokenRootUpgradeable', TOKEN_CONTRACTS_PATH);
        migration.load(TokenRoot, token.symbol + 'Root');

        CreditProcessorTokenWallet = await locklift.factory.getContract('TokenWalletUpgradeable', TOKEN_CONTRACTS_PATH);
        UserTokenWallet = await locklift.factory.getContract('TokenWalletUpgradeable', TOKEN_CONTRACTS_PATH);

        CreditFactory = await locklift.factory.getContract('CreditFactory');
        migration.load(CreditFactory, 'CreditFactory');
        CreditFactory.afterRun = afterRun;
        TestEthereumEventConfiguration = await locklift.factory.getContract('TestEthereumEventConfiguration');
        migration.load(TestEthereumEventConfiguration, token.symbol + 'TestEthereumEventConfiguration');

        HiddenBridgeStrategyFactory = await locklift.factory.getContract('HiddenBridgeStrategyFactory');
        migration.load(HiddenBridgeStrategyFactory, 'HiddenBridgeStrategyFactory');
        HiddenBridgeStrategy = await locklift.factory.getContract('HiddenBridgeStrategy');
        migration.load(HiddenBridgeStrategy, token.symbol + 'HiddenBridgeStrategy');

        ProxyTokenTransfer = await locklift.factory.getContract('TestProxyTokenTransfer');
        migration.load(ProxyTokenTransfer, token.symbol + 'ProxyTokenTransfer');

        await migration.balancesCheckpoint();

        logger.log(`Account${options.account_number}: ${User.address}`);
        logger.log(`CreditFactory: ${CreditFactory.address}`);
        logger.log(`HiddenBridgeStrategy: ${HiddenBridgeStrategy.address}`);
        logger.log(`HiddenBridgeStrategyFactory: ${HiddenBridgeStrategyFactory.address}`);
        logger.log(`ProxyTokenTransfer: ${ProxyTokenTransfer.address}`);
        logger.log(`${token.symbol}TestEthereumEventConfiguration: ${TestEthereumEventConfiguration.address}`);
        userBalancesStart = await logUserBalance();
        userBalancesStart[token.id] = userBalancesStart[token.id] || '0';
    });

    describe('Derive addresses', async function () {
        it(`Call HiddenBridgeStrategyFactory.buildLayer3`, async function () {
            logger.log('#################################################');
            logger.log(``);
            logger.log(`HiddenBridgeStrategyFactory(${HiddenBridgeStrategyFactory.address}).buildLayer3`);
            logger.log(``);

            const params = {
               id: getRandomNonce(),
               proxy: ProxyTokenTransfer.address,
               evmAddress: '1',
               chainId: '1'
            };

            logger.log(`params = ${JSON.stringify(params)}`);

            LAYER_3 = await HiddenBridgeStrategyFactory.call({
                method: 'buildLayer3',
                params
            });
            logger.log(`LAYER_3 = ${LAYER_3}`);
        });

        it(`Call TestEthereumEventConfiguration.encodeEventData`, async function () {
            logger.log('#################################################');
            logger.log(``);
            logger.log(`TestEthereumEventConfiguration(${TestEthereumEventConfiguration.address}).encodeEventData`);
            logger.log(``);

            const params = {
                eventData: {
                    amount: new BigNumber(options.amount).shiftedBy(token.decimals).toString(),
                    user: User.address,
                    creditor: CreditFactory.address,
                    recipient: HiddenBridgeStrategy.address,
                    tokenAmount: new BigNumber(options.token_amount).shiftedBy(token.decimals).toString(),
                    tonAmount: new BigNumber(options.ton_amount).shiftedBy(9).toString(),
                    swapType: options.swap_type,
                    slippage: {
                        numerator: 5,
                        denominator: 1000
                    },
                    layer3: LAYER_3
                }
            };

            console.log('EventData: ', params);

            const eventData = await TestEthereumEventConfiguration.call({
                method: 'encodeEventData',
                params
            });

            EVENT_VOTE_DATA = {
                eventTransaction: 0,
                eventIndex: getRandomNonce(),
                eventData,
                eventBlockNumber: 0,
                eventBlock: 0
            }

            logger.log(`eventVoteData = ${JSON.stringify(EVENT_VOTE_DATA)}`);
        });

        it(`Call TestEthereumEventConfiguration.deriveEventAddress`, async function () {

            logger.log('#################################################');
            logger.log(``);
            logger.log(`TestEthereumEventConfiguration(${TestEthereumEventConfiguration.address})`);
            logger.log(`.deriveEventAddress(eventVoteData);`);
            logger.log(``);

            const eventAddress = await TestEthereumEventConfiguration.call({
                method: 'deriveEventAddress',
                params: {
                    eventVoteData: EVENT_VOTE_DATA
                }
            });
            TestEthereumEvent.setAddress(eventAddress);
            migration.store(TestEthereumEvent, 'TestEthereumEvent');

            logger.log(`TestEthereumEvent: ${TestEthereumEvent.address}`);
        });

        it(`Call CreditFactory.getCreditProcessorAddress`, async function () {
            logger.log('#################################################');
            logger.log(``);
            logger.log(`CreditFactory(${CreditFactory.address})`);
            logger.log(`.getCreditProcessorAddress(eventVoteData, ${TestEthereumEventConfiguration.address})`);
            logger.log(``);

            const creditProcessorAddress = await CreditFactory.call({
                method: 'getCreditProcessorAddress',
                params: {
                    eventVoteData: EVENT_VOTE_DATA,
                    configuration: TestEthereumEventConfiguration.address
                }
            });
            CreditProcessor.setAddress(creditProcessorAddress);
            migration.store(CreditProcessor, 'CreditProcessor');

            logger.log(`CreditProcessor: ${CreditProcessor.address}`);
        });


        it(`Call TokenRootUpgradeable.walletOf for User`, async function () {
            logger.log('#################################################');

            logger.log(``);
            logger.log(`TokenRootUpgradeable(${TokenRoot.address}).walletOf(`);
            logger.log(`    walletOwner: ${User.address} (User)`);
            logger.log(`)`);
            logger.log(``);
            const expectedUserTokenWallet = await TokenRoot.call({
                method: 'walletOf', params: {
                    walletOwner: User.address
                }
            });
            UserTokenWallet.setAddress(expectedUserTokenWallet);
            const alias = token.symbol + 'Wallet' + options.account_number;
            migration.store(UserTokenWallet, alias);
            logger.log(`${alias}: ${UserTokenWallet.address}`);
            await logUserBalance();
        });

        it(`Call TokenRootUpgradeable.walletOf for CreditProcessor`, async function () {
            logger.log('#################################################');

            logger.log(``);
            logger.log(`TokenRootUpgradeable(${TokenRoot.address}).walletOf(`);
            logger.log(`    walletOwner: ${CreditProcessor.address} (CreditProcessor)`);
            logger.log(`)`);
            logger.log(``);
            const expectedProcessorTokenWallet = await TokenRoot.call({
                method: 'walletOf', params: {
                    walletOwner: CreditProcessor.address
                }
            });
            CreditProcessorTokenWallet.setAddress(expectedProcessorTokenWallet);
            migration.store(CreditProcessorTokenWallet, `CreditProcessorTokenWallet`);
            logger.log(`CreditProcessorTokenWallet: ${CreditProcessorTokenWallet.address}`);
        });

    });

    describe('Deploy processor', async function () {

        it(`Run CreditFactory.deployProcessor`, async function () {
            logger.log('#################################################');
            logger.log(``);
            logger.log(`CreditFactory(${CreditFactory.address})`);
            logger.log(`.deployProcessor(eventVoteData, ${TestEthereumEventConfiguration.address}, ${options.credit_body} ton)`);
            logger.log(``);
            if(!LOG_FULL_GAS) { await migration.balancesCheckpoint(); }

            const tx = await CreditFactory.run({
                method: 'deployProcessor',
                params: {
                    eventVoteData: EVENT_VOTE_DATA,
                    configuration: TestEthereumEventConfiguration.address,
                    grams: locklift.utils.convertCrystal(options.credit_body, 'nano')
                },
                keyPair: keyPairs[4]
            });
            logTx(tx);
            if(!LOG_FULL_GAS) { await logGas(); }


            const details = await CreditProcessor.call({
                method: 'getDetails',
                params: {}
            });
            showCreditProcessorDetails(details);

            // TODO: validate and show decodedEventData

            expect(states[details.state.toNumber()]).to.equal('EventDeployInProgress', `Wrong state: ${states[details.state.toNumber()]}`);

        });

        it(`Emulate event confirmed`, async function () {
            logger.log('#################################################');
            logger.log(``);
            logger.log(`TestEthereumEvent(${TestEthereumEvent.address})`);
            logger.log(`.testConfirm()`);
            logger.log(``);

            if(!LOG_FULL_GAS) { await migration.balancesCheckpoint(); }

            const tx = await TestEthereumEvent.run({
                method: 'testConfirm',
                params: {},
                keyPair: keyPairs[4]
            });

            await afterRun();

            logTx(tx);
            if(!LOG_FULL_GAS) { await logGas(); }

            // const details = await CreditProcessor.call({
            //    method: 'getDetails',
            //    params: {}
            // });
            //
            // if (states[details.state.toNumber()] === 'EventConfirmed') {
            //     logger.log(`(!) Not processed automatically  - state is EventConfirmed`);
            //     showCreditProcessorDetails(details);
            //     const balances = await logCreditProcessorBalance();
            //     expect(balances[options.token_id]).to.equal(new BigNumber(options.amount).toString(), `Wrong CreditProcessor ${token.symbol} balance`);
            //     expect(states[details.state.toNumber()]).to.equal('EventConfirmed', `Wrong state: ${states[details.state.toNumber()]}`);
            //
            //     if(!LOG_FULL_GAS) { await migration.balancesCheckpoint(); }
            //
            //     logger.log(``);
            //     logger.log(`CreditFactory(${CreditFactory.address})`);
            //     logger.log(`.runProcess(${CreditProcessor.address})`);
            //     logger.log(``);
            //
            //     const tx = await CreditFactory.run({
            //         method: 'runProcess',
            //         params: {
            //             creditProcessor: CreditProcessor.address
            //         },
            //         keyPair: keyPairs[4]
            //     });
            //
            //     logTx(tx);
            //     if(!LOG_FULL_GAS) { await logGas(); }
            //
            //     await afterRun();
            // }

        });

        it(`Check Processed`, async function () {

            logger.log('#################################################')

            logger.log(`Account${options.account_number} balance START: ` +
                `${userBalancesStart[options.token_id] !== undefined ?
                    userBalancesStart[options.token_id] + ' ' + token.symbol :
                    '0 ' + token.symbol + ' (not deployed)'}, ` +
                `${userBalancesStart.ton !== undefined ? userBalancesStart.ton + ' TON' : '0 TON (not deployed)'}`);

            logger.log('#################################################')

            const details = await CreditProcessor.call({
                method: 'getDetails',
                params: {}
            });
            showCreditProcessorDetails(details);
            const cpBalancesEnd = await logCreditProcessorBalance();
            const userBalancesEnd = await logUserBalance();
            userBalancesEnd[options.token_id] = userBalancesEnd[options.token_id] || '0';

            expect(states[details.state.toNumber()]).to
                .equal('Processed', `Wrong state: ${states[details.state.toNumber()]}`);

        });

        it(`Show all CreditProcessor events`, async function () {
            logger.log('#################################################');
            logger.log('#######   CreditProcessor EVENTS   ##############');
            logger.log('#################################################');
            logger.log('* - diff with previous state\n');
            const events = await loadCreditProcessorEvents(50);

            let d;

            events.forEach(event => {
                console.log('');
                if(event.name === 'CreditProcessorStateChanged') {
                    if (d === undefined) {
                        d = event.value.details;
                        console.log(`CreditProcessorStateChanged(\n` +
                        `from = ${states[event.value.from]}, \n` +
                        `to = ${states[event.value.to]}, \n` +
                        `details = ${JSON.stringify(d, null, 2)})`);
                    } else {
                        let diff = updatedDiff(d, event.value.details);
                        console.log(`CreditProcessorStateChanged(\n` +
                        `from = ${states[event.value.from]}, \n` +
                        `to = ${states[event.value.to]}, \n` +
                        `details* = ${JSON.stringify(diff, null, 2)})`);
                        d = event.value.details;
                    }
                } else if(event.name === 'CreditProcessorDeployed') {
                    d = event.value.details;
                    console.log(`${event.name}(\n` +
                        `details: ${JSON.stringify(d, null, 2)}})`);
                } else if(event.value.sender) {
                    console.log(`${event.name}(sender = ${event.value.sender})`);
                } else {
                    console.log(`${event.name}(...)`);
                }
            });
        });

        it(`Show all Proxy events`, async function () {
            logger.log('#######################################');
            logger.log('#######   Proxy EVENTS   ##############');
            logger.log('#######################################');
            logger.log('* - diff with previous state\n');
            const events = await loadProxyEvents(50);

            let d;

            events.forEach(event => {
                console.log(`${event.name}: ${JSON.stringify(event.value)}`);
            });
        });

        if(LOG_FULL_GAS) {
            it(`Log gas`, async function () {
                await logGas();
            });
        }

    });
});

async function loadProxyEvents(limit) {
    const {
        result
    } = await this.locklift.ton.client.net.query_collection({
        collection: 'messages',
        filter: {
            src: {eq: ProxyTokenTransfer.address},
            msg_type: {eq: 2}
        },
        order: [{path: 'created_at', direction: "ASC"}, {path: 'created_lt', direction: "ASC"}],
        limit,
        result: 'body id src created_at created_lt'
    });

    const decodedMessages = [];

    for (let message of result) {
        const decodedMessage = await this.locklift.ton.client.abi.decode_message_body({
            abi: {
                type: 'Contract',
                value: ProxyTokenTransfer.abi
            },
            body: message.body,
            is_internal: false
        });

        decodedMessages.push({
            ...decodedMessage,
            messageId: message.id,
            src: message.src,
            created_at: message.created_at,
            created_lt: message.created_lt
        });
    }

    return decodedMessages;
}

async function loadCreditProcessorEvents(limit) {
    const {
        result
    } = await this.locklift.ton.client.net.query_collection({
        collection: 'messages',
        filter: {
            src: {eq: CreditProcessor.address},
            msg_type: {eq: 2}
        },
        order: [{path: 'created_at', direction: "ASC"}, {path: 'created_lt', direction: "ASC"}],
        limit,
        result: 'body id src created_at created_lt'
    });

    const decodedMessages = [];

    for (let message of result) {
      const decodedMessage = await this.locklift.ton.client.abi.decode_message_body({
        abi: {
          type: 'Contract',
          value: CreditProcessor.abi
        },
        body: message.body,
        is_internal: false
      });

      decodedMessages.push({
        ...decodedMessage,
        messageId: message.id,
        src: message.src,
        created_at: message.created_at,
        created_lt: message.created_lt
      });
    }

    return decodedMessages;
}
