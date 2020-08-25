const env = require('@nomiclabs/buidler')

async function main () {
  const UniswapOracle = env.artifacts.require('UniswapOracle')
  
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })