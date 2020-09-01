const env = require('@nomiclabs/buidler')

async function main () {
  const config = require('../deployment_configs/mainnet-oracle.json')
  const UniswapOracle = env.artifacts.require('UniswapOracle')
  const oracle = await UniswapOracle.new(config.UNISWAP_FACTORY, config.PEAK_ADDR, config.USDC_ADDR)
  console.log(`Deployed UniswapOracle for PEAK-USDC pair at ${oracle.address}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
