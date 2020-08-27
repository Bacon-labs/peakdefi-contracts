BetokenFund = artifacts.require "BetokenFund"
BetokenProxy = artifacts.require "BetokenProxy"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"
TestTokenFactory = artifacts.require "TestTokenFactory"
CompoundOrder = artifacts.require "CompoundOrder"
TestPriceOracle = artifacts.require "TestPriceOracle"
TestComptroller = artifacts.require "TestComptroller"
TestCERC20 = artifacts.require "TestCERC20"
TestCEther = artifacts.require "TestCEther"
TestCERC20Factory = artifacts.require "TestCERC20Factory"

PeakReward = artifacts.require "PeakReward"
PeakStaking = artifacts.require "PeakStaking"
PEAK_PRECISION = 1e8
PEAK_PRICE = 0.12

BigNumber = require "bignumber.js"

epsilon = 1e-3

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
ETH_ADDR = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
PRECISION = 1e18
SHORT_LEVERAGE = -0.5
LONG_LEVERAGE = 1.5

bnToString = (bn) -> BigNumber(bn).toFixed(0)

PRECISION = 1e18
OMG_PRICE = 10 * PRECISION
ETH_PRICE = 20 * PRECISION
DAI_PRICE = PRECISION
PHASE_LENGTHS = (require "../deployment_configs/testnet.json").phaseLengths
DAY = 86400
INACTIVE_THRESHOLD = 2
NEW_MANAGER_KAIRO = 100 * PRECISION
MAX_NEW_MANAGERS_PER_CYCLE = 25
KAIRO_PRICE = 10 * PRECISION
PEAK_MANAGER_STAKE_REQUIRED = 1e4 * PEAK_PRECISION

# travel `time` seconds forward in time
timeTravel = (time) ->
  return new Promise((resolve, reject) -> 
    web3.currentProvider.send({
      jsonrpc: "2.0"
      method: "evm_increaseTime"
      params: [time]
      id: new Date().getTime()
    }, (err, result) ->
      if err
        return reject(err)
      return resolve(result)
    );
  )

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  curr_cycle = BigNumber(await fund.cycleNumber.call()).toNumber()
  curr_phase = BigNumber(await fund.cyclePhase.call()).toNumber()
  while curr_cycle < cycle || curr_phase < phase
    await timeTravel(PHASE_LENGTHS[curr_phase])
    await fund.nextPhase({from: account})
    curr_cycle = BigNumber(await fund.cycleNumber.call()).toNumber()
    curr_phase = BigNumber(await fund.cyclePhase.call()).toNumber()
  return fund

DAI = (fund) ->
  daiAddr = await fund.DAI_ADDR.call()
  return TestToken.at(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.KYBER_ADDR.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (symbol) ->
  factory = await TestTokenFactory.deployed()
  addr = await factory.getToken.call(symbol)
  return TestToken.at(addr)

ST = (fund) ->
  shareTokenAddr = await fund.shareTokenAddr.call()
  return MiniMeToken.at(shareTokenAddr)

KRO = (fund) ->
  kroAddr = await fund.controlTokenAddr.call()
  return MiniMeToken.at(kroAddr)

CPD = (underlying) ->
  factory = await TestCERC20Factory.deployed()
  addr = await factory.createdTokens.call(underlying)
  return TestCERC20.at(addr)

CO = (fund, account, id) ->
  orderAddr = await fund.userCompoundOrders.call(account, id)
  return CompoundOrder.at(orderAddr)

epsilon_equal = (curr, prev) ->
  BigNumber(curr).eq(prev) or BigNumber(curr).minus(prev).div(prev).abs().lt(epsilon)

calcRegisterPayAmount = (fund, kroAmount, tokenPrice) ->
  kairoPrice = BigNumber await fund.kairoPrice.call()
  return kroAmount * kairoPrice / tokenPrice

getReceiveKairoRatio = (delta) ->
  if delta >= -0.1
    # no punishment
    return 1 + delta
  else if delta < -0.1 and delta > -0.25
    # punishment
    return 1 + (-(6 * (-delta) - 0.5))
  else
    # burn
    return 0

contract("simulation", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("deposit_dai", () ->
    this.fund = await FUND(1, 0, owner)
    dai = await DAI(this.fund)
    st = await ST(this.fund)
    account2 = accounts[2]

    # give DAI to user
    amount = 1 * PRECISION
    await dai.mint(account2, bnToString(amount), {from: owner})

    # deposit DAI
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account2)
    prevShareBlnce = BigNumber await st.balanceOf.call(account2)
    await dai.approve(this.fund.address, bnToString(amount), {from: account2})
    await this.fund.depositDAI(bnToString(amount), ZERO_ADDR, {from: account2})
    await dai.approve(this.fund.address, 0, {from: account2})

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = BigNumber(await dai.balanceOf.call(account2))
    assert.equal(prevDAIBlnce.minus(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account2))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), amount, "received share amount incorrect")
  )

  it("deposit_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # mint token for user
    amount = 1 * PRECISION
    await token.mint(account, bnToString(amount), {from: owner})

    # deposit token
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    await token.approve(this.fund.address, bnToString(amount), {from: account})
    await this.fund.depositToken(token.address, bnToString(amount), ZERO_ADDR, {from: account})
    await token.approve(this.fund.address, 0, {from: account})

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "received share amount incorrect")

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "fund balance increase incorrect")

    # check token balance
    tokenBlnce = BigNumber(await token.balanceOf.call(account))
    assert.equal(prevTokenBlnce.minus(tokenBlnce).toNumber(), amount, "token balance decrease incorrect")
  )

  it("deposit_ether", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)
    account3 = accounts[3]

    eth_amount = 0.01 * PRECISION
    amount = eth_amount / PRECISION * ETH_PRICE # amount of deposit in DAI

    # deposit ETH
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevETHBlnce = BigNumber await web3.eth.getBalance(account3)
    prevShareBlnce = BigNumber await st.balanceOf.call(account3)
    await this.fund.depositEther(ZERO_ADDR, {from: account3, value: bnToString(eth_amount), gasPrice: 0})

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check user ETH balance
    ethBlnce = BigNumber await web3.eth.getBalance(account3)
    assert.equal(prevETHBlnce.minus(ethBlnce).toNumber(), eth_amount, "ETH balance decrease incorrect")

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account3))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), amount, "received share amount incorrect")
  )

  it("withdraw_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)

    # withdraw dai
    amount = 0.1 * PRECISION
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)
    await this.fund.withdrawDAI(bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert.equal(daiBlnce.minus(prevDAIBlnce).toNumber(), amount, "DAI balance increase incorrect")
  )

  it("withdraw_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # withdraw token
    amount = 1 * PRECISION

    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    await this.fund.withdrawToken(token.address, bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check token balance
    tokenBlnce = BigNumber await token.balanceOf.call(account)
    assert.equal(tokenBlnce.minus(prevTokenBlnce).toNumber(), Math.round(amount * PRECISION / OMG_PRICE), "DAI balance increase incorrect")
  )

  it("withdraw_ether", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)

    # withdraw dai
    amount = 0.1 * PRECISION
    eth_amount = amount / ETH_PRICE * PRECISION
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevETHBlnce = BigNumber await web3.eth.getBalance(account)
    await this.fund.withdrawEther(bnToString(amount), {from: account, gasPrice: 0})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check ether balance
    ethBlnce = BigNumber await web3.eth.getBalance(account)
    assert.equal(ethBlnce.minus(prevETHBlnce).toNumber(), eth_amount, "ETH balance increase incorrect")
  )

  it("register_accounts", () ->
    kro = await KRO(this.fund)
    dai = await DAI(this.fund)
    token = await TK("OMG")
    account2 = accounts[2]
    account3 = accounts[3]

    amount = NEW_MANAGER_KAIRO

    # stake PEAK for accounts
    peakStaking = await PeakStaking.deployed()
    peakToken = await TestToken.at(await peakStaking.peakToken())
    await peakToken.transfer(account, PEAK_MANAGER_STAKE_REQUIRED, {from: owner})
    await peakToken.transfer(account2, PEAK_MANAGER_STAKE_REQUIRED, {from: owner})
    await peakToken.transfer(account3, PEAK_MANAGER_STAKE_REQUIRED, {from: owner})
    await peakToken.approve(peakStaking.address, PEAK_MANAGER_STAKE_REQUIRED, {from: account})
    await peakToken.approve(peakStaking.address, PEAK_MANAGER_STAKE_REQUIRED, {from: account2})
    await peakToken.approve(peakStaking.address, PEAK_MANAGER_STAKE_REQUIRED, {from: account3})
    await peakStaking.stake(PEAK_MANAGER_STAKE_REQUIRED, 100, owner, {from: account})
    await peakStaking.stake(PEAK_MANAGER_STAKE_REQUIRED, 100, owner, {from: account2})
    await peakStaking.stake(PEAK_MANAGER_STAKE_REQUIRED, 100, owner, {from: account3})

    # register account[1] using ETH
    await this.fund.registerWithETH({from: account, value: await calcRegisterPayAmount(this.fund, amount, ETH_PRICE)})

    # mint DAI for account[2]
    daiAmount = bnToString(await calcRegisterPayAmount(this.fund, amount, DAI_PRICE))
    await dai.mint(account2, daiAmount, {from: owner})

    # register account[2]
    await dai.approve(this.fund.address, daiAmount, {from: account2})
    await this.fund.registerWithDAI({from: account2})

    # mint OMG tokens for account[3]
    omgAmount = bnToString(await calcRegisterPayAmount(this.fund, amount, OMG_PRICE))
    await token.mint(account3, omgAmount, {from: owner})

    # register account[3]
    await token.approve(this.fund.address, omgAmount, {from: account3})
    await this.fund.registerWithToken(token.address, omgAmount, {from: account3})

    # check Kairo balances
    assert(epsilon_equal(amount, await kro.balanceOf.call(account)), "account 1 Kairo amount incorrect")
    assert(epsilon_equal(amount, await kro.balanceOf.call(account2)), "account 2 Kairo amount incorrect")
    assert(epsilon_equal(amount, await kro.balanceOf.call(account3)), "account 3 Kairo amount incorrect")
  )

  it("phase_0_to_1", () ->
    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 1, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change")
  )

  it("can't_burn_deadman", () ->
    try
      await this.fund.burnDeadman(account, {from: account})
      assert.fail("burnt KRO of active manager")
  )

  it("create_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)

    # buy token
    amount = NEW_MANAGER_KAIRO
    await this.fund.createInvestment(token.address, bnToString(amount), 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.minus(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    kroTotalSupply = BigNumber await kro.totalSupply.call()
    fundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)
    assert.equal(fundTokenBlnce.minus(prevFundTokenBlnce).toNumber(), Math.floor(fundDAIBlnce.times(PRECISION).div(kroTotalSupply).times(amount).div(OMG_PRICE).toNumber()), "token balance increase incorrect")

    # create investment for account2
    account2 = accounts[2]
    await this.fund.createInvestment(ETH_ADDR, bnToString(amount), 0, bnToString(ETH_PRICE * 2), {from: account2})
  )

  it("sell_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # wait for 1 day to sell investment for accounts[1]
    await timeTravel(1 * DAY)

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf.call(this.fund.address)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()

    # sell investment
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, 0)).tokenAmount)
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount), 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    stake = BigNumber((await this.fund.userInvestments.call(account, 0)).stake)
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "received Kairo amount incorrect")

    # check fund token balance
    fundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)
    assert(epsilon_equal(tokenAmount, prevFundTokenBlnce.minus(fundTokenBlnce)), "fund token balance changed")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(epsilon_equal(prevFundBlnce, fundBlnce), "fund DAI balance changed")

    # wait for 2 more days to sell investment for account2
    account2 = accounts[2]
    await timeTravel(2 * DAY)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account2, 0)).tokenAmount)
    # sell half of the investment, then sell the rest
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount.div(2)), 0, bnToString(ETH_PRICE * 2), {from: account2})
    await this.fund.sellInvestmentAsset(1, bnToString(tokenAmount.div(2)), 0, bnToString(ETH_PRICE * 2), {from: account2})
  )

  it("create_compound_orders", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    dai = await DAI(this.fund)
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    fund = this.fund
    cToken = await CPD(token.address)

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)

    # create short order
    amount = 0.01 * PRECISION
    await this.fund.createCompoundOrder(true, cToken.address, bnToString(amount), 0, MAX_PRICE, {from: account})
    shortOrder = await CO(this.fund, account, 0)

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.minus(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    kroTotalSupply = BigNumber await kro.totalSupply.call()
    assert.equal(prevFundDAIBlnce.minus(fundDAIBlnce).toNumber(), await shortOrder.collateralAmountInDAI.call(), "DAI balance decrease incorrect")

    # create long order for account2
    account2 = accounts[2]
    await this.fund.createCompoundOrder(false, (await TestCEther.deployed()).address, bnToString(amount), 0, bnToString(ETH_PRICE * 2), {from: account2})
  )

  it("sell_compound_orders", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    dai = await DAI(this.fund)
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    account2 = accounts[2]


    # SHORT ORDER SELLING
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()

    # sell short order
    shortOrder = await CO(this.fund, account, 0)
    await this.fund.sellCompoundOrder(0, 0, MAX_PRICE, {from: account})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    stake = BigNumber await shortOrder.stake.call()
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "account received Kairo amount incorrect")

    # check fund DAI balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    assert(epsilon_equal(await shortOrder.collateralAmountInDAI.call(), fundDAIBlnce.minus(prevFundDAIBlnce)), "short order returned incorrect DAI amount")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(epsilon_equal(prevFundBlnce, fundBlnce), "fund DAI balance changed")


    # LONG ORDER SELLING
    prevKROBlnce = BigNumber await kro.balanceOf.call(account2)
    prevFundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()

    # sell account2's long order
    longOrder = await CO(this.fund, account2, 0)
    await this.fund.sellCompoundOrder(0, 0, bnToString(ETH_PRICE * 2), {from: account2})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account2)
    stake = BigNumber await longOrder.stake.call()
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "account2 received Kairo amount incorrect")

    # check fund DAI balance
    fundDAIBlnce = BigNumber await dai.balanceOf.call(this.fund.address)
    assert(epsilon_equal(await longOrder.collateralAmountInDAI.call(), fundDAIBlnce.minus(prevFundDAIBlnce)), "long order returned incorrect DAI amount")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(epsilon_equal(prevFundBlnce, fundBlnce), "fund DAI balance changed")
  )

  it("next_cycle", () ->
    await timeTravel(24 * DAY) # spent 3 days on sell_investment tests
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 2, "cycle number didn't change")
  )

  it("redeem_commission", () ->
    dai = await DAI(this.fund)

    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account)

    # redeem commission
    await this.fund.redeemCommission(false, {from: account})

    # make sure can't redeem again
    try
      await this.fund.redeemCommission(false, {from: account})
      assert.fail()

    # check DAI balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert(epsilon_equal(daiBlnce.minus(prevDAIBlnce), commissionAmount._commission), "didn't receive correct commission")

    # check penalty
    # only invested full kro balance for 3 days out of 9, so penalty / commission = 2
    assert(epsilon_equal(BigNumber(commissionAmount._penalty).div(commissionAmount._commission), 2), "penalty amount incorrect")
  )

  it("redeem_commission_in_shares", () ->
    st = await ST(this.fund)
    account2 = accounts[2]

    prevShareBlnce = BigNumber await st.balanceOf.call(account2)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account2)

    # redeem commission
    await this.fund.redeemCommissionForCycle(true, 1, {from: account2})

    # make sure can't redeem again
    try
      await this.fund.redeemCommissionForCycle(true, 1, {from: account2})
      assert.fail()

    # ensure can't redeem for invalid cycles
    try
      await this.fund.redeemCommissionForCycle(true, 0, {from: account2})
      assert.fail()
    try
      await this.fund.redeemCommissionForCycle(true, 2, {from: account2})
      assert.fail()

    # check Share balance
    shareBlnce = BigNumber await st.balanceOf.call(account2)
    assert(shareBlnce.minus(prevShareBlnce).gt(0), "didn't receive corrent commission")

    # check penalty
    # staked for 9 days, penalty should be 0
    assert(BigNumber(commissionAmount._penalty).eq(0), "penalty amount incorrect")
  )

  it("burn_deadmen", () ->
    # jump to point where all managers are dead
    this.fund = await FUND(2 + INACTIVE_THRESHOLD, 0, account)

    # burn account
    await this.fund.burnDeadman(account, {from: account})

    # check Kairo balance
    kro = await KRO(this.fund)
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(kroBlnce.eq(0), "failed to burn KRO of deadman")
  )
)

contract("price_changes", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
    dai = await DAI(this.fund)

    amount = 10 * PRECISION
    await dai.mint(account, bnToString(amount), {from: owner}) # Mint DAI
    await dai.approve(this.fund.address, bnToString(amount), {from: account}) # Approve transfer
    await this.fund.depositDAI(bnToString(amount), ZERO_ADDR, {from: account}) # Deposit for account

    # stake PEAK for accounts
    peakStaking = await PeakStaking.deployed()
    peakToken = await TestToken.at(await peakStaking.peakToken())
    await peakToken.transfer(account, PEAK_MANAGER_STAKE_REQUIRED, {from: owner})
    await peakToken.approve(peakStaking.address, PEAK_MANAGER_STAKE_REQUIRED, {from: account})
    await peakStaking.stake(PEAK_MANAGER_STAKE_REQUIRED, 100, owner, {from: account})

    kroAmount = KAIRO_PRICE
    await this.fund.registerWithETH({from: account, value: await calcRegisterPayAmount(this.fund, kroAmount, ETH_PRICE)})

    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner}) # Go to Manage phase
  )

  it("raise_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cOMG = await CPD(omg.address)
    oracle = await TestPriceOracle.deployed()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await oracle.setTokenPrice(cOMG.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 0
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # create short order
    shortId = 0
    await this.fund.createCompoundOrder(true, cOMG.address, bnToString(stake), 0, MAX_PRICE, {from: account})
    # create long order
    longId = 1
    await this.fund.createCompoundOrder(false, cOMG.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # raise asset price by 20%
    delta = 0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await oracle.setTokenPrice(cOMG.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "investment KRO reward incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).gt(0), "fund DAI increase incorrect")

    # sell short order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    await this.fund.sellCompoundOrder(shortId, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta * SHORT_LEVERAGE)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "short KRO penalty incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).lt(0), "fund DAI decrease incorrect")

    # sell long order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    await this.fund.sellCompoundOrder(longId, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta * LONG_LEVERAGE)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "long KRO reward incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).gt(0), "fund DAI increase incorrect")
  )

  it("lower_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cOMG = await CPD(omg.address)
    oracle = await TestPriceOracle.deployed()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await oracle.setTokenPrice(cOMG.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 1
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # create short order
    shortId = 2
    await this.fund.createCompoundOrder(true, cOMG.address, bnToString(stake), 0, MAX_PRICE, {from: account})
    # create long order
    longId = 3
    await this.fund.createCompoundOrder(false, cOMG.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price by 20%
    delta = -0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await oracle.setTokenPrice(cOMG.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "investment KRO penalty incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).lt(0), "fund DAI decrease incorrect")

    # sell short order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    await this.fund.sellCompoundOrder(shortId, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta * SHORT_LEVERAGE)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "short KRO reward incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).gt(0), "fund DAI increase incorrect")

    # sell long order
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    await this.fund.sellCompoundOrder(longId, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = getReceiveKairoRatio(delta * LONG_LEVERAGE)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "long KRO penalty incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert(fundBlnce.minus(prevFundBlnce).lt(0), "fund DAI decrease incorrect")
  )

  it("lower_asset_price_to_0", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    cOMG = await CPD(omg.address)
    oracle = await TestPriceOracle.deployed()
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})
    await oracle.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    stake = 0.1 * PRECISION
    investmentId = 2
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price by 99.99%
    delta = -0.9999
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})
    await oracle.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    expectedReceiveKairoRatio = 0
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), expectedReceiveKairoRatio), "investment KRO penalty incorrect")
  )
)

contract("param_setters", (accounts) ->
  owner = accounts[0]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Intermission phase
  )

  it("decrease_only_proportion_setters", () ->
    # changeDeveloperFeeRate()
    devFeeRate = BigNumber await this.fund.devFundingRate.call()
    # valid
    await this.fund.changeDeveloperFeeRate(devFeeRate.idiv(2), {from: owner})
    assert.equal(BigNumber(await this.fund.devFundingRate.call()).toNumber(), devFeeRate.idiv(2).toNumber(), "changeDeveloperFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeDeveloperFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeDeveloperFeeRate(devFeeRate, {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >= current rate")
  )

  it("address_setters", () ->
    newAddr = "0xdd974D5C2e2928deA5F71b9825b8b646686BD200"

    # changeDeveloperFeeAccount()
    # valid address
    await this.fund.changeDeveloperFeeAccount(newAddr, {from: owner})
    assert.equal(await this.fund.devFundingAccount.call(), newAddr, "changeDeveloperFeeAccount() faulty")
    # invalid address
    try
      await this.fund.changeDeveloperFeeAccount(ZERO_ADDR, {from: owner})
      assert.fail("changeDeveloperFeeAccount() accepted zero address")
  )
)

contract("peak_staking", (accounts) ->
  stakeAmount = 1e1 * PEAK_PRECISION
  stakeTimeInDays = 100
  peakStaking = null
  peakToken = null

  it("stake()", () ->
    peakStaking = await PeakStaking.deployed()
    peakToken = await TestToken.at(await peakStaking.peakToken())

    # stake without referrer
    await peakToken.approve(peakStaking.address, bnToString(stakeAmount))
    await peakStaking.stake(bnToString(stakeAmount), stakeTimeInDays, ZERO_ADDR)

    # stake with referrer
    beforeBalance0 = await peakToken.balanceOf(accounts[0])
    beforeBalance1 = await peakToken.balanceOf(accounts[1])
    await peakToken.approve(peakStaking.address, bnToString(stakeAmount))
    await peakStaking.stake(bnToString(stakeAmount), stakeTimeInDays, accounts[1])
    balanceChange0 = BigNumber(await peakToken.balanceOf(accounts[0])).minus(beforeBalance0)
    balanceChange1 = BigNumber(await peakToken.balanceOf(accounts[1])).minus(beforeBalance1)
    expectedInterest = BigNumber(await peakStaking.getInterestAmount(bnToString(stakeAmount), stakeTimeInDays))
    expectedReward0 = BigNumber(expectedInterest).times(0.03)
    expectedReward1 = BigNumber(expectedInterest).times(0.1)
    actualReward0 = BigNumber(balanceChange0).plus(stakeAmount)
    assert(epsilon_equal(expectedReward0, actualReward0), "staker reward incorrect")
    assert(epsilon_equal(expectedReward1, balanceChange1), "referrer reward incorrect")
  )

  it("withdraw()", () ->
    # time travel to stake maturation
    await timeTravel(100 * DAY)

    # withdraw stake #0
    beforeBalance = await peakToken.balanceOf(accounts[0])
    await peakStaking.withdraw(0)
    balanceChange = BigNumber(await peakToken.balanceOf(accounts[0])).minus(beforeBalance)
    expectedInterest = BigNumber(await peakStaking.getInterestAmount(bnToString(stakeAmount), stakeTimeInDays))
    actualInterest = balanceChange.minus(stakeAmount)
    assert(epsilon_equal(actualInterest, expectedInterest), "Interest amount incorrect for stake #0")

    # withdraw stake #1
    beforeBalance = await peakToken.balanceOf(accounts[0])
    await peakStaking.withdraw(1)
    balanceChange = BigNumber(await peakToken.balanceOf(accounts[0])).minus(beforeBalance)
    expectedInterest = BigNumber(await peakStaking.getInterestAmount(bnToString(stakeAmount), stakeTimeInDays))
    actualInterest = balanceChange.minus(stakeAmount)
    assert(epsilon_equal(actualInterest, expectedInterest), "Interest amount incorrect for stake #1")
  )
)

contract("peak_reward", (accounts) ->
  stakeAmount = 1e6 * PEAK_PRECISION
  stakeTimeInDays = 100

  peakReward = null
  peakStaking = null
  peakToken = null
  fund = null
  dai = null

  it("prep_work", () ->
    peakReward = await PeakReward.deployed()
    peakStaking = await PeakStaking.deployed()
    peakToken = await TestToken.at(await peakStaking.peakToken())
    fund = await FUND(1, 0, accounts[0])
    dai = await DAI(fund)
  )

  it("refer()", () ->
    # set accounts[1] as the referrer of accounts[2]
    await peakReward.refer(accounts[2], accounts[1])

    # verify
    actualReferrer = await peakReward.referrerOf(accounts[2])
    assert.equal(accounts[1], actualReferrer, "referrer not set correctly")
  )

  it("canRefer()", () ->
    assert.equal(true, await peakReward.canRefer(accounts[3], accounts[2]), "cannot refer when should be able to")

    # set accounts[2] as the referrer of accounts[3]
    await peakReward.refer(accounts[3], accounts[2])

    assert.equal(false, await peakReward.canRefer(accounts[3], accounts[2]), "can refer after referral")
  )

  it("payCommission()", () ->
    # pay commission to accounts[3], with no stakes
    rawCommissionAmount = PRECISION
    beforeBalance3 = BigNumber(await dai.balanceOf(accounts[3]))
    await dai.approve(peakReward.address, bnToString(rawCommissionAmount))
    await peakReward.payCommission(accounts[3], dai.address, bnToString(rawCommissionAmount), false)
    balanceChange3 = BigNumber(await dai.balanceOf(accounts[3])).minus(beforeBalance3)
    expectedReward3 = rawCommissionAmount * 0.1 / 0.2
    assert(epsilon_equal(balanceChange3, expectedReward3), "account[3] commission incorrect (no stakes)")

    # pay commission to accounts[3], with stakes
    await peakToken.transfer(accounts[1], bnToString(stakeAmount))
    await peakToken.approve(peakStaking.address, bnToString(stakeAmount), {from: accounts[1]})
    await peakStaking.stake(bnToString(stakeAmount), stakeTimeInDays, ZERO_ADDR, {from: accounts[1]})

    await peakToken.transfer(accounts[2], bnToString(stakeAmount))
    await peakToken.approve(peakStaking.address, bnToString(stakeAmount), {from: accounts[2]})
    await peakStaking.stake(bnToString(stakeAmount), stakeTimeInDays, ZERO_ADDR, {from: accounts[2]})
    
    beforeBalance1 = BigNumber(await dai.balanceOf(accounts[1]))
    beforeBalance2 = BigNumber(await dai.balanceOf(accounts[2]))
    beforeBalance3 = BigNumber(await dai.balanceOf(accounts[3]))
    await dai.approve(peakReward.address, bnToString(rawCommissionAmount))
    await peakReward.payCommission(accounts[3], dai.address, bnToString(rawCommissionAmount), false)
    balanceChange1 = BigNumber(await dai.balanceOf(accounts[1])).minus(beforeBalance1)
    balanceChange2 = BigNumber(await dai.balanceOf(accounts[2])).minus(beforeBalance2)
    balanceChange3 = BigNumber(await dai.balanceOf(accounts[3])).minus(beforeBalance3)
    expectedReward1 = rawCommissionAmount * 0.02 / 0.2
    expectedReward2 = rawCommissionAmount * 0.04 / 0.2
    expectedReward3 = rawCommissionAmount * 0.1 / 0.2
    assert(epsilon_equal(balanceChange1, expectedReward1), "accounts[1] commission incorrect")
    assert(epsilon_equal(balanceChange2, expectedReward2), "accounts[2] commission incorrect")
    assert(epsilon_equal(balanceChange3, expectedReward3), "accounts[3] commission incorrect")
  )

  it("rankUp()", () ->
    # acc4 goes from rank 0 => rank 2, acc5 and acc6 go from rank 0 => rank 1
    await peakReward.refer(accounts[5], accounts[4])
    await peakReward.refer(accounts[6], accounts[4])
    await peakReward.incrementCareerValueInDai(accounts[4], bnToString(100 * PRECISION))
    await peakReward.incrementCareerValueInDai(accounts[5], bnToString(50 * PRECISION))
    await peakReward.incrementCareerValueInDai(accounts[6], bnToString(50 * PRECISION))
    acc4BeforeBalance = BigNumber(await peakToken.balanceOf(accounts[4]))
    acc5BeforeBalance = BigNumber(await peakToken.balanceOf(accounts[5]))
    acc6BeforeBalance = BigNumber(await peakToken.balanceOf(accounts[6]))
    await peakReward.rankUp(accounts[5])
    await peakReward.rankUp(accounts[6])
    await peakReward.rankUp(accounts[4])

    # check ranks
    rank4 = (await peakReward.rankOf(accounts[4])).toNumber()
    rank5 = (await peakReward.rankOf(accounts[5])).toNumber()
    rank6 = (await peakReward.rankOf(accounts[6])).toNumber()
    assert.equal(2, rank4, "accounts[4] wrong rank")
    assert.equal(1, rank5, "accounts[5] wrong rank")
    assert.equal(1, rank6, "accounts[6] wrong rank")

    # check rewards
    acc4BalanceChange = BigNumber(await peakToken.balanceOf(accounts[4])).minus(acc4BeforeBalance).div(PEAK_PRECISION)
    acc5BalanceChange = BigNumber(await peakToken.balanceOf(accounts[5])).minus(acc5BeforeBalance).div(PEAK_PRECISION)
    acc6BalanceChange = BigNumber(await peakToken.balanceOf(accounts[6])).minus(acc6BeforeBalance).div(PEAK_PRECISION)
    assert(epsilon_equal(300 / PEAK_PRICE, acc4BalanceChange), "accounts[4] wrong reward")
    assert(epsilon_equal(100 / PEAK_PRICE, acc5BalanceChange), "accounts[5] wrong reward")
    assert(epsilon_equal(100 / PEAK_PRICE, acc6BalanceChange), "accounts[6] wrong reward")
  )
)