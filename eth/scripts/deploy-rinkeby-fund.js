const env = require('@nomiclabs/buidler')
const BigNumber = require('bignumber.js')

async function main () {
  const config = require('../deployment_configs/rinkeby.json')

  const PeakDeFiFactory = env.artifacts.require('PeakDeFiFactory')
  const PeakDeFiFund = env.artifacts.require('PeakDeFiFund')
  const peakdefiFactory = await PeakDeFiFactory.at(config.PEAKDEFI_FACTORY_ADDR)

  // deploy PeakDeFiFund
  const peakdefiFundAddr = await peakdefiFactory.createFund.call()
  await peakdefiFactory.createFund()
  const peakdefiFund = await PeakDeFiFund.at(peakdefiFundAddr)
  await peakdefiFactory.initFund1(peakdefiFund.address, 'RepToken', 'REP', 'PeakDeFi Shares', 'BTKS')
  await peakdefiFactory.initFund2(peakdefiFund.address, config.KYBER_TOKENS, config.COMPOUND_CTOKENS)
  await peakdefiFactory.initFund3(peakdefiFund.address, BigNumber(config.NEW_MANAGER_REPTOKEN).toFixed(), config.MAX_NEW_MANAGERS_PER_CYCLE, BigNumber(config.REPTOKEN_PRICE).toFixed(), BigNumber(config.PEAK_MANAGER_STAKE_REQUIRED).toFixed(), config.IS_PERMISSIONED)
  await peakdefiFactory.initFund4(peakdefiFund.address, config.DEVELOPER_ACCOUNT, config.devFundingRate, config.phaseLengths, config.COMPOUND_FACTORY_ADDR)
  await peakdefiFund.nextPhase()

  console.log(`Deployed PeakDeFiFund at ${peakdefiFundAddr}`)
  console.log(`Deployed PeakDeFiProxy at ${await peakdefiFund.proxyAddr()}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
