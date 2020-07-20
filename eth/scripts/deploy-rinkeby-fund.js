const env = require('@nomiclabs/buidler')

async function main () {
  const config = require('../deployment_configs/rinkeby.json')

  const BetokenFactory = env.artifacts.require('BetokenFactory')
  const BetokenFund = env.artifacts.require('BetokenFund')
  const BetokenLogic = env.artifacts.require('BetokenLogic')
  const BetokenLogic2 = env.artifacts.require('BetokenLogic2')
  const BetokenLogic3 = env.artifacts.require('BetokenLogic3')
  const MiniMeTokenFactory = env.artifacts.require('MiniMeTokenFactory')

  const PeakStaking = env.artifacts.require('PeakStaking')
  const PeakReward = env.artifacts.require('PeakReward')
  const PeakToken = env.artifacts.require('PeakToken')

  const betokenFactory = await BetokenFactory.at(config.BETOKEN_FACTORY_ADDR)

  // deploy BetokenFund
  const betokenFundAddr = await betokenFactory.createFund.call()
  await betokenFactory.createFund()
  const betokenFund = await BetokenFund.at(betokenFundAddr)
  await betokenFactory.initFund1(betokenFund.address, 'Kairo', 'KRO', 'Betoken Shares', 'BTKS')
  await betokenFactory.initFund2(betokenFund.address, config.KYBER_TOKENS, config.COMPOUND_CTOKENS)
  await betokenFactory.initFund3(betokenFund.address, config.DEVELOPER_ACCOUNT, config.devFundingRate, config.phaseLengths, config.COMPOUND_FACTORY_ADDR)

  console.log(`Deployed BetokenFund at ${betokenFundAddr}`)
  console.log(`Deployed BetokenProxy at ${await betokenFund.proxyAddr()}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
