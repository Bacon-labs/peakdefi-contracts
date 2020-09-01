const env = require('@nomiclabs/buidler')
const BigNumber = require('bignumber.js')

async function main () {
  const config = require('../deployment_configs/mainnet-factory.json')
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000'
  const accounts = await env.web3.eth.getAccounts()
  const bnToString = (bn) => BigNumber(bn).toFixed(0)

  const BetokenFactory = env.artifacts.require('BetokenFactory')
  const BetokenFund = env.artifacts.require('BetokenFund')
  const BetokenLogic = env.artifacts.require('BetokenLogic')
  const BetokenLogic2 = env.artifacts.require('BetokenLogic2')
  const BetokenLogic3 = env.artifacts.require('BetokenLogic3')
  const MiniMeTokenFactory = env.artifacts.require('MiniMeTokenFactory')

  const CompoundOrderFactory = env.artifacts.require('CompoundOrderFactory')
  const LongCERC20Order = env.artifacts.require('LongCERC20Order')
  const ShortCERC20Order = env.artifacts.require('ShortCERC20Order')
  const LongCEtherOrder = env.artifacts.require('LongCEtherOrder')
  const ShortCEtherOrder = env.artifacts.require('ShortCEtherOrder')

  const PeakStaking = env.artifacts.require('PeakStaking')
  const PeakReward = env.artifacts.require('PeakReward')

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
  const peakReward = await PeakReward.new(config.MARKETPEAK_WALLET_ADDR, peakStaking.address, config.PEAK_ADDR, config.DAI_ADDR, config.PEAK_UNISWAP_ORACLE_ADDR)
  await peakStaking.init(peakReward.address)
  await peakReward.addSigner(peakStaking.address)
  console.log(`Deployed PeakStaking at ${peakStaking.address}`)
  console.log(`Deployed PeakReward at ${peakReward.address}`)

  // TODO: give PEAK minter rights to PeakStaking and PeakReward

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
    peakStaking.address,
    miniMeTokenFactory.address
  )

  await peakReward.addSigner(betokenFactory.address)
  await peakReward.renounceSigner(accounts[0])

  console.log(`Deployed BetokenFactory at ${betokenFactory.address}`)

  // deploy Compound order templates
  // deploy ShortCERC20Order
  const ShortCERC20OrderContract = await ShortCERC20Order.new()
  await ShortCERC20OrderContract.renounceOwnership()

  // deploy ShortCEtherOrder
  const ShortCEtherOrderContract = await ShortCEtherOrder.new()
  await ShortCEtherOrderContract.renounceOwnership()

  // deploy LongCERC20Order
  const LongCERC20OrderContract = await LongCERC20Order.new()
  await LongCERC20OrderContract.renounceOwnership()

  // deploy LongCEtherOrder
  const LongCEtherOrderContract = await LongCEtherOrder.new()
  await LongCEtherOrderContract.renounceOwnership()

  // deploy CompoundOrderFactory
  const CompoundOrderFactoryContract = await CompoundOrderFactory.new(
    ShortCERC20OrderContract.address,
    ShortCEtherOrderContract.address,
    LongCERC20OrderContract.address,
    LongCEtherOrderContract.address,
    config.DAI_ADDR,
    config.KYBER_ADDR,
    config.COMPOUND_COMPTROLLER_ADDR,
    config.COMPOUND_ORACLE_ADDR,
    config.COMPOUND_CDAI_ADDR,
    config.COMPOUND_CETH_ADDR
  )

  console.log(`Deployed CompoundOrderFactory at ${CompoundOrderFactoryContract.address}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
