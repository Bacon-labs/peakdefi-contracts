const env = require('@nomiclabs/buidler')
const BigNumber = require('bignumber.js')

async function main () {
  const config = require('../deployment_configs/mainnet-factory.json')
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000'
  const accounts = await env.web3.eth.getAccounts()
  const bnToString = (bn) => BigNumber(bn).toFixed(0)

  const PeakDeFiFactory = env.artifacts.require('PeakDeFiFactory')
  const PeakDeFiFund = env.artifacts.require('PeakDeFiFund')
  const PeakDeFiLogic = env.artifacts.require('PeakDeFiLogic')
  const PeakDeFiLogic2 = env.artifacts.require('PeakDeFiLogic2')
  const PeakDeFiLogic3 = env.artifacts.require('PeakDeFiLogic3')
  const MiniMeTokenFactory = env.artifacts.require('MiniMeTokenFactory')

  const CompoundOrderFactory = env.artifacts.require('CompoundOrderFactory')
  const LongCERC20Order = env.artifacts.require('LongCERC20Order')
  const ShortCERC20Order = env.artifacts.require('ShortCERC20Order')
  const LongCEtherOrder = env.artifacts.require('LongCEtherOrder')
  const ShortCEtherOrder = env.artifacts.require('ShortCEtherOrder')

  const PeakStaking = env.artifacts.require('PeakStaking')
  const PeakReward = env.artifacts.require('PeakReward')

  // deploy template PeakDeFiFund
  const peakdefiFundTemplate = await PeakDeFiFund.new()

  // deploy PeakDeFiLogic
  const peakdefiLogic = await PeakDeFiLogic.new()
  const peakdefiLogic2 = await PeakDeFiLogic2.new()
  const peakdefiLogic3 = await PeakDeFiLogic3.new()

  // deploy MiniMeTokenFactory
  const miniMeTokenFactory = await MiniMeTokenFactory.new()

  // deploy PeakStaking, PeakReward
  const peakStaking = await PeakStaking.new(config.PEAK_ADDR)
  const peakReward = await PeakReward.new(config.MARKETPEAK_WALLET_ADDR, peakStaking.address, config.PEAK_ADDR, config.USDC_ADDR, config.PEAK_UNISWAP_ORACLE_ADDR)
  await peakStaking.init(peakReward.address)
  await peakReward.addSigner(peakStaking.address)
  console.log(`Deployed PeakStaking at ${peakStaking.address}`)
  console.log(`Deployed PeakReward at ${peakReward.address}`)

  // TODO: give PEAK minter rights to PeakStaking and PeakReward

  // deploy PeakDeFiFactory
  const peakdefiFactory = await PeakDeFiFactory.new(
    config.USDC_ADDR,
    config.KYBER_ADDR,
    config.ONEINCH_ADDR,
    peakdefiFundTemplate.address,
    peakdefiLogic.address,
    peakdefiLogic2.address,
    peakdefiLogic3.address,
    peakReward.address,
    peakStaking.address,
    miniMeTokenFactory.address
  )

  await peakReward.addSigner(peakdefiFactory.address)

  console.log(`Deployed PeakDeFiFactory at ${peakdefiFactory.address}`)

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
    config.USDC_ADDR,
    config.KYBER_ADDR,
    config.COMPOUND_COMPTROLLER_ADDR,
    config.COMPOUND_ORACLE_ADDR,
    config.COMPOUND_CUSDC_ADDR,
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
