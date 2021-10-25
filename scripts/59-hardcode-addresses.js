const fs = require('fs');
const {Migration, DEX_CONTRACTS_PATH, stringToBytesArray, BRIDGE_CONTRACTS_PATH, EMPTY_TVM_CELL,
    getRandomNonce, ZERO_ADDRESS, TOKEN_CONTRACTS_PATH, WTON_CONTRACTS_PATH, Constants} = require(process.cwd()+'/scripts/utils');
const BigNumber = require('bignumber.js');
BigNumber.config({EXPONENTIAL_AT: 257});
const migration = new Migration();


async function main() {
    console.log(`59-show-hardcode.js`);

    const DexRoot = await locklift.factory.getContract('DexRoot', DEX_CONTRACTS_PATH);
    migration.load(DexRoot, 'DexRoot');
    const WrappedTONVault = await locklift.factory.getContract('WrappedTONVault', WTON_CONTRACTS_PATH);
    migration.load(WrappedTONVault, 'WTONVault');
    const WTONRoot = await locklift.factory.getContract('RootTokenContract', TOKEN_CONTRACTS_PATH);
    migration.load(WTONRoot, 'WTONRoot');

    const content = '' +
`pragma ton-solidity >= 0.39.0;

abstract contract Addresses {
    address constant DEX_ROOT = address.makeAddrStd(0, ${new BigNumber(DexRoot.address.substr(2).toLowerCase(), 16).toString()});
    address constant WTON_VAULT = address.makeAddrStd(0, ${new BigNumber(WrappedTONVault.address.substr(2).toLowerCase(), 16).toString()});
    address constant WTON_ROOT = address.makeAddrStd(0, ${new BigNumber(WTONRoot.address.substr(2).toLowerCase(), 16).toString()});
}`

    console.log('Replace Addresses.sol with');
    console.log(content);
    fs.writeFileSync('./contracts/Addresses.sol', content);
}

main()
    .then(() => process.exit(0))
    .catch(e => {
        console.log(e);
        process.exit(1);
    });
