const env = require('@nomiclabs/buidler')

async function main () {
  const config = require('../deployment_configs/mainnet-fund.json')

  const BetokenFactory = env.artifacts.require('BetokenFactory')
  const BetokenFund = env.artifacts.require('BetokenFund')
  const betokenFactory = await BetokenFactory.at(config.BETOKEN_FACTORY_ADDR)

  // deploy BetokenFund
  const betokenFundAddr = await betokenFactory.createFund.call()
  await betokenFactory.createFund()
  const betokenFund = await BetokenFund.at(betokenFundAddr)
  await betokenFactory.initFund1(betokenFund.address, config.REPUTATION_TOKEN_NAME, config.REPUTATION_TOKEN_SYMBOL, config.SHARE_TOKEN_NAME, config.SHARE_TOKEN_SYMBOL)
  await betokenFactory.initFund2(betokenFund.address, config.KYBER_TOKENS, config.COMPOUND_CTOKENS)
  await betokenFactory.initFund3(betokenFund.address, config.NEW_MANAGER_KAIRO, config.MAX_NEW_MANAGERS_PER_CYCLE, config.KAIRO_PRICE, config.PEAK_MANAGER_STAKE_REQUIRED, config.IS_PERMISSIONED)
  await betokenFactory.initFund4(betokenFund.address, config.DEVELOPER_ACCOUNT, config.devFundingRate, config.phaseLengths, config.COMPOUND_FACTORY_ADDR)
  await betokenFund.nextPhase()

  console.log(`Deployed BetokenFund at ${betokenFundAddr}`)
  console.log(`Deployed BetokenProxy at ${await betokenFund.proxyAddr()}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
