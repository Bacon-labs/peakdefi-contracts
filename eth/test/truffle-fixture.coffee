PeakDeFiFund = artifacts.require "PeakDeFiFund"
PeakDeFiProxy = artifacts.require "PeakDeFiProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
LongCERC20Order = artifacts.require "LongCERC20Order"
ShortCERC20Order = artifacts.require "ShortCERC20Order"
LongCEtherOrder = artifacts.require "LongCEtherOrder"
ShortCEtherOrder = artifacts.require "ShortCEtherOrder"
CompoundOrderFactory = artifacts.require "CompoundOrderFactory"
PeakDeFiLogic = artifacts.require "PeakDeFiLogic"
PeakDeFiLogic2 = artifacts.require "PeakDeFiLogic2"
PeakDeFiLogic3 = artifacts.require "PeakDeFiLogic3"
PeakReward = artifacts.require "PeakReward"
PeakStaking = artifacts.require "PeakStaking"
PeakDeFiFactory = artifacts.require "PeakDeFiFactory"
TestUniswapOracle = artifacts.require "TestUniswapOracle"

BigNumber = require "bignumber.js"

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
ETH_ADDR = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
PRECISION = 1e18

bnToString = (bn) -> BigNumber(bn).toFixed(0)

module.exports = () ->
  accounts = await web3.eth.getAccounts();

  # Local testnet migration
  config = require "../deployment_configs/testnet.json"

  TestToken = artifacts.require "TestToken"
  TestKyberNetwork = artifacts.require "TestKyberNetwork"
  TestTokenFactory = artifacts.require "TestTokenFactory"
  TestPriceOracle = artifacts.require "TestPriceOracle"
  TestComptroller = artifacts.require "TestComptroller"
  TestCERC20 = artifacts.require "TestCERC20"
  TestCEther = artifacts.require "TestCEther"
  TestCERC20Factory = artifacts.require "TestCERC20Factory"

  # deploy TestToken factory
  TestTokenFactory.setAsDeployed(await TestTokenFactory.new())
  testTokenFactory = await TestTokenFactory.deployed()

  # create TestUSDC
  testUSDCAddr = (await testTokenFactory.newToken("USDC Stable Coin", "USDC", 18)).logs[0].args.addr
  TestUSDC = await TestToken.at(testUSDCAddr)
  
  # mint USDC for owner
  await TestUSDC.mint(accounts[0], bnToString(1e7 * PRECISION)) # ten million

  # create TestTokens
  tokensInfo = require "../deployment_configs/kn_tokens.json"
  tokenAddrs = []
  for token in tokensInfo
    tokenAddrs.push((await testTokenFactory.newToken(token.name, token.symbol, token.decimals)).logs[0].args.addr)
  tokenAddrs.push(TestUSDC.address)
  tokenAddrs.push(ETH_ADDR)
  tokenPrices = (bnToString(10 * PRECISION) for i in [1..tokensInfo.length]).concat([bnToString(PRECISION), bnToString(20 * PRECISION)])

  # deploy TestKyberNetwork
  TestKyberNetworkContract = await TestKyberNetwork.new(tokenAddrs, tokenPrices)
  TestKyberNetwork.setAsDeployed(TestKyberNetworkContract)

  # send ETH to TestKyberNetwork
  await web3.eth.sendTransaction({from: accounts[0], to: TestKyberNetworkContract.address, value: 1 * PRECISION})

  # deploy Test Compound suite of contracts

  # deploy TestComptroller
  TestComptrollerContract = await TestComptroller.new()
  TestComptroller.setAsDeployed(TestComptrollerContract)

  # deploy TestCERC20Factory
  TestCERC20Factory.setAsDeployed(await TestCERC20Factory.new())
  testCERC20Factory = await TestCERC20Factory.deployed()

  # deploy TestCEther
  TestCEtherContract = await TestCEther.new(TestComptrollerContract.address)
  TestCEther.setAsDeployed(TestCEtherContract)

  # send ETH to TestCEther
  await web3.eth.sendTransaction({from: accounts[0], to: TestCEtherContract.address, value: 1 * PRECISION})

  # deploy TestCERC20 contracts
  compoundTokens = {}
  for token in tokenAddrs[0..tokenAddrs.length - 2]
    compoundTokens[token] = (await testCERC20Factory.newToken(token, TestComptrollerContract.address)).logs[0].args.cToken
  compoundTokens[ETH_ADDR] = TestCEtherContract.address

  # deploy TestPriceOracle
  compoundTokenAddrs = tokenAddrs.map((x) -> compoundTokens[x])
  TestPriceOracleContract =  await TestPriceOracle.new(compoundTokenAddrs, tokenPrices, TestCEtherContract.address)
  TestPriceOracle.setAsDeployed(TestPriceOracleContract)

  # mint tokens for KN
  for token in tokenAddrs[0..tokenAddrs.length - 2]
    tokenObj = await TestToken.at(token)
    await tokenObj.mint(TestKyberNetworkContract.address, bnToString(1e12 * PRECISION)) # one trillion tokens

  # mint tokens for Compound markets
  for token in tokenAddrs[0..tokenAddrs.length - 2]
    tokenObj = await TestToken.at(token)
    await tokenObj.mint(compoundTokens[token], bnToString(1e12 * PRECISION)) # one trillion tokens        

  # deploy RepToken and PeakDeFi Shares contracts
  MiniMeTokenFactory.setAsDeployed(await MiniMeTokenFactory.new())
  minimeFactory = await MiniMeTokenFactory.deployed()
  
  # deploy ShortCERC20Order
  ShortCERC20OrderContract = await ShortCERC20Order.new()
  ShortCERC20Order.setAsDeployed(ShortCERC20OrderContract)
  await ShortCERC20OrderContract.renounceOwnership()

  # deploy ShortCEtherOrder
  ShortCEtherOrderContract = await ShortCEtherOrder.new()
  ShortCEtherOrder.setAsDeployed(ShortCEtherOrderContract)
  await ShortCEtherOrderContract.renounceOwnership()

  # deploy LongCERC20Order
  LongCERC20OrderContract = await LongCERC20Order.new()
  LongCERC20Order.setAsDeployed(LongCERC20OrderContract)
  await LongCERC20OrderContract.renounceOwnership()

  # deploy LongCEtherOrder
  LongCEtherOrderContract = await LongCEtherOrder.new()
  LongCEtherOrder.setAsDeployed(LongCEtherOrderContract)
  await LongCEtherOrderContract.renounceOwnership()

  # deploy CompoundOrderFactory
  CompoundOrderFactoryContract = await CompoundOrderFactory.new(
    ShortCERC20OrderContract.address,
    ShortCEtherOrderContract.address,
    LongCERC20OrderContract.address,
    LongCEtherOrderContract.address,
    TestUSDC.address,
    TestKyberNetworkContract.address,
    TestComptrollerContract.address,
    TestPriceOracleContract.address,
    compoundTokens[TestUSDC.address],
    TestCEtherContract.address
  )
  CompoundOrderFactory.setAsDeployed(CompoundOrderFactoryContract)

  # deploy PeakDeFiLogic
  PeakDeFiLogicContract = await PeakDeFiLogic.new()
  PeakDeFiLogic.setAsDeployed(PeakDeFiLogicContract)
  PeakDeFiLogic2Contract = await PeakDeFiLogic2.new()
  PeakDeFiLogic2.setAsDeployed(PeakDeFiLogic2Contract)
  PeakDeFiLogic3Contract = await PeakDeFiLogic3.new()
  PeakDeFiLogic3.setAsDeployed(PeakDeFiLogic3Contract)

  # deploy PeakDeFi contracts
  TestUniswapOracleContract = await TestUniswapOracle.new()
  TestUniswapOracle.setAsDeployed(TestUniswapOracleContract)
  peakReferralTokenAddr = (await minimeFactory.createCloneToken(
      ZERO_ADDR, 0, "Peak Referral Token", 18, "PRT", true)).logs[0].args.addr
  PeakReferralToken = await MiniMeToken.at(peakReferralTokenAddr)
  peakTokenAddr = (await testTokenFactory.newToken("MarketPeak", "PEAK", 8)).logs[0].args.addr
  PeakToken = await TestToken.at(peakTokenAddr)
  await PeakToken.mint(accounts[0], bnToString(1e9 * 1e8)) # 1 billion PEAK
  PeakStakingContract = await PeakStaking.new(PeakToken.address)
  PeakStaking.setAsDeployed(PeakStakingContract)
  await PeakToken.addMinter(PeakStakingContract.address)
  PeakRewardContract = await PeakReward.new(accounts[0], PeakStakingContract.address, PeakToken.address, testUSDCAddr, TestUniswapOracleContract.address)
  PeakReward.setAsDeployed(PeakRewardContract)
  await PeakToken.addMinter(PeakRewardContract.address)
  await PeakStakingContract.init(PeakRewardContract.address)
  await PeakRewardContract.addSigner(PeakStakingContract.address)

  # deploy PeakDeFiFund template
  fundTemplate = await PeakDeFiFund.new()

  # deploy PeakDeFiFactory
  peakdefiFactory = await PeakDeFiFactory.new(
    TestUSDC.address,
    TestKyberNetworkContract.address,
    ZERO_ADDR,
    fundTemplate.address,
    PeakDeFiLogicContract.address,
    PeakDeFiLogic2Contract.address,
    PeakDeFiLogic3Contract.address,
    PeakRewardContract.address,
    PeakStakingContract.address,
    minimeFactory.address
  )

  await PeakRewardContract.addSigner(peakdefiFactory.address)

  # deploy PeakDeFiFund
  compoundTokensArray = (compoundTokens[token] for token in tokenAddrs[0..tokenAddrs.length - 3])
  compoundTokensArray.push(TestCEtherContract.address)
  peakdefiFundAddr = await peakdefiFactory.createFund.call()
  await peakdefiFactory.createFund()
  peakdefiFund = await PeakDeFiFund.at(peakdefiFundAddr)
  await peakdefiFactory.initFund1(peakdefiFund.address, 'RepToken', 'REP', 'PeakDeFi Shares', 'BTKS')
  await peakdefiFactory.initFund2(peakdefiFund.address, tokenAddrs[0..tokenAddrs.length - 3].concat([ETH_ADDR]), compoundTokensArray)
  await peakdefiFactory.initFund3(peakdefiFund.address, bnToString(config.NEW_MANAGER_REPTOKEN), bnToString(config.MAX_NEW_MANAGERS_PER_CYCLE), bnToString(config.REPTOKEN_PRICE), bnToString(config.PEAK_MANAGER_STAKE_REQUIRED), false)
  await peakdefiFactory.initFund4(peakdefiFund.address, accounts[0], config.devFundingRate, config.phaseLengths, CompoundOrderFactoryContract.address)
  await peakdefiFund.nextPhase()

  PeakDeFiFund.setAsDeployed(peakdefiFund)