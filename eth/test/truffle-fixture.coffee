BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
LongCERC20Order = artifacts.require "LongCERC20Order"
ShortCERC20Order = artifacts.require "ShortCERC20Order"
LongCEtherOrder = artifacts.require "LongCEtherOrder"
ShortCEtherOrder = artifacts.require "ShortCEtherOrder"
CompoundOrderFactory = artifacts.require "CompoundOrderFactory"
BetokenLogic = artifacts.require "BetokenLogic"
BetokenLogic2 = artifacts.require "BetokenLogic2"
BetokenLogic3 = artifacts.require "BetokenLogic3"
PeakReward = artifacts.require "PeakReward"
PeakStaking = artifacts.require "PeakStaking"
BetokenFactory = artifacts.require "BetokenFactory"
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

  # create TestDAI
  testDAIAddr = (await testTokenFactory.newToken("DAI Stable Coin", "DAI", 18)).logs[0].args.addr
  TestDAI = await TestToken.at(testDAIAddr)
  
  # mint DAI for owner
  await TestDAI.mint(accounts[0], bnToString(1e7 * PRECISION)) # ten million

  # create TestTokens
  tokensInfo = require "../deployment_configs/kn_tokens.json"
  tokenAddrs = []
  for token in tokensInfo
    tokenAddrs.push((await testTokenFactory.newToken(token.name, token.symbol, token.decimals)).logs[0].args.addr)
  tokenAddrs.push(TestDAI.address)
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

  # deploy Kairo and Betoken Shares contracts
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
    TestDAI.address,
    TestKyberNetworkContract.address,
    TestComptrollerContract.address,
    TestPriceOracleContract.address,
    compoundTokens[TestDAI.address],
    TestCEtherContract.address
  )
  CompoundOrderFactory.setAsDeployed(CompoundOrderFactoryContract)

  # deploy BetokenLogic
  BetokenLogicContract = await BetokenLogic.new()
  BetokenLogic.setAsDeployed(BetokenLogicContract)
  BetokenLogic2Contract = await BetokenLogic2.new()
  BetokenLogic2.setAsDeployed(BetokenLogic2Contract)
  BetokenLogic3Contract = await BetokenLogic3.new()
  BetokenLogic3.setAsDeployed(BetokenLogic3Contract)

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
  PeakRewardContract = await PeakReward.new(accounts[0], PeakStakingContract.address, PeakToken.address, testDAIAddr, TestUniswapOracleContract.address)
  PeakReward.setAsDeployed(PeakRewardContract)
  await PeakStakingContract.init(PeakRewardContract.address)
  await PeakRewardContract.addSigner(PeakStakingContract.address)

  # deploy BetokenFund template
  fundTemplate = await BetokenFund.new()

  # deploy BetokenFactory
  betokenFactory = await BetokenFactory.new(
    TestDAI.address,
    TestKyberNetworkContract.address,
    ZERO_ADDR,
    fundTemplate.address,
    BetokenLogicContract.address,
    BetokenLogic2Contract.address,
    BetokenLogic3Contract.address,
    PeakRewardContract.address,
    PeakStakingContract.address,
    minimeFactory.address
  )

  await PeakRewardContract.addSigner(betokenFactory.address)

  # deploy BetokenFund
  compoundTokensArray = (compoundTokens[token] for token in tokenAddrs[0..tokenAddrs.length - 3])
  compoundTokensArray.push(TestCEtherContract.address)
  betokenFundAddr = await betokenFactory.createFund.call()
  await betokenFactory.createFund()
  betokenFund = await BetokenFund.at(betokenFundAddr)
  await betokenFactory.initFund1(betokenFund.address, 'Kairo', 'KRO', 'Betoken Shares', 'BTKS')
  await betokenFactory.initFund2(betokenFund.address, tokenAddrs[0..tokenAddrs.length - 3].concat([ETH_ADDR]), compoundTokensArray)
  await betokenFactory.initFund3(betokenFund.address, bnToString(config.NEW_MANAGER_KAIRO), bnToString(config.MAX_NEW_MANAGERS_PER_CYCLE), bnToString(config.KAIRO_PRICE), bnToString(config.PEAK_MANAGER_STAKE_REQUIRED))
  await betokenFactory.initFund4(betokenFund.address, accounts[0], config.devFundingRate, config.phaseLengths, CompoundOrderFactoryContract.address)
  await betokenFund.nextPhase()

  BetokenFund.setAsDeployed(betokenFund)