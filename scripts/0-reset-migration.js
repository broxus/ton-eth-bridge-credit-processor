const {Migration} = require(process.cwd()+'/scripts/utils')
const range = n => [...Array(n).keys()];

const migration = new Migration();

async function main() {
  console.log(`0-reset-migration.js`);
  migration.reset();
}

main()
  .then(() => process.exit(0))
  .catch(e => {
    console.log(e);
    process.exit(1);
  });
