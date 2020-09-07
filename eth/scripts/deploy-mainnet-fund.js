const env = require('@nomiclabs/buidler')

async function main () {
  const config = require('../deployment_configs/mainnet-fund.json')

  const PeakDeFiFactory = env.artifacts.require('PeakDeFiFactory')
  const PeakDeFiFund = env.artifacts.require('PeakDeFiFund')
  const peakdefiFactory = await PeakDeFiFactory.at(config.PEAKDEFI_FACTORY_ADDR)

  // deploy PeakDeFiFund
  const peakdefiFundAddr = await peakdefiFactory.createFund.call()
  await peakdefiFactory.createFund()
  const peakdefiFund = await PeakDeFiFund.at(peakdefiFundAddr)
  await peakdefiFactory.initFund1(peakdefiFund.address, config.REPUTATION_TOKEN_NAME, config.REPUTATION_TOKEN_SYMBOL, config.SHARE_TOKEN_NAME, config.SHARE_TOKEN_SYMBOL)
  await peakdefiFactory.initFund2(peakdefiFund.address, config.KYBER_TOKENS, config.COMPOUND_CTOKENS)
  await peakdefiFactory.initFund3(peakdefiFund.address, config.NEW_MANAGER_REPTOKEN, config.MAX_NEW_MANAGERS_PER_CYCLE, config.REPTOKEN_PRICE, config.PEAK_MANAGER_STAKE_REQUIRED, config.IS_PERMISSIONED)
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
