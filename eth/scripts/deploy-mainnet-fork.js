const env = require('@nomiclabs/buidler')

async function main () {
  const config = require('../deployment_configs/mainnet-fork.json')

  const BetokenFactory = env.artifacts.require('BetokenFactory')
  const BetokenFund = env.artifacts.require('BetokenFund')
  const BetokenLogic = env.artifacts.require('BetokenLogic')
  const BetokenLogic2 = env.artifacts.require('BetokenLogic2')
  const BetokenLogic3 = env.artifacts.require('BetokenLogic3')
  const MiniMeTokenFactory = env.artifacts.require('MiniMeTokenFactory')

  const PeakStaking = env.artifacts.require('PeakStaking')
  const PeakReward = env.artifacts.require('PeakReward')
  const PeakToken = env.artifacts.require('PeakToken')

  // deploy template BetokenFund
  const betokenFundTemplate = await BetokenFund.new()

  // deploy BetokenLogic
  const betokenLogic = await BetokenLogic.new()
  const betokenLogic2 = await BetokenLogic2.new()
  const betokenLogic3 = await BetokenLogic3.new()

  // deploy MiniMeTokenFactory
  const miniMeTokenFactory = await MiniMeTokenFactory.new()

  // deploy PeakStaking, PeakReward
  const peakStaking = await PeakStaking.new(config.PEAK_ADDR)
  const peakReward = await PeakReward.new(config.MARKETPEAK_WALLET_ADDR, peakStaking.address)
  await peakStaking.init(peakReward.address)
  await peakReward.addSigner(peakStaking.address)

  // give PEAK minter rights to PeakStaking
  const minterAddr = '0xbD0e2a92771383FC95ddDd49cC3892a4dc4f5DE3'
  const peakToken = await PeakToken.at(config.PEAK_ADDR)
  await peakToken.addMinter(peakStaking.address, { from: minterAddr })

  // deploy BetokenFactory
  const betokenFactory = await BetokenFactory.new(
    config.DAI_ADDR,
    config.KYBER_ADDR,
    config.ONEINCH_ADDR,
    betokenFundTemplate.address,
    betokenLogic.address,
    betokenLogic2.address,
    betokenLogic3.address,
    peakReward.address,
    miniMeTokenFactory.address
  )

  await peakReward.addSigner(betokenFactory.address)

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
