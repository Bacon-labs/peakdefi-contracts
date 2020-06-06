pragma solidity 0.5.17;

import "./CompoundOrder.sol";

contract ShortCEtherOrder is CompoundOrder {
  modifier isValidPrice(uint256 _minPrice, uint256 _maxPrice) {
    // Ensure token's price is between _minPrice and _maxPrice
    uint256 tokenPrice = PRECISION; // The price of ETH in ETH is just 1
    tokenPrice = __tokenToDAI(CETH_ADDR, tokenPrice); // Convert token price to be in DAI
    require(tokenPrice >= _minPrice && tokenPrice <= _maxPrice); // Ensure price is within range
    _;
  }

  function executeOrder(uint256 _minPrice, uint256 _maxPrice)
    public
    onlyOwner
    isValidToken(compoundTokenAddr)
    isValidPrice(_minPrice, _maxPrice)
  {
    buyTime = now;

    // Get funds in DAI from BetokenFund
    dai.safeTransferFrom(owner(), address(this), collateralAmountInDAI); // Transfer DAI from BetokenFund
    
    // Enter Compound markets
    CEther market = CEther(compoundTokenAddr);
    address[] memory markets = new address[](2);
    markets[0] = compoundTokenAddr;
    markets[1] = address(CDAI);
    uint[] memory errors = COMPTROLLER.enterMarkets(markets);
    require(errors[0] == 0 && errors[1] == 0);

    // Get loan from Compound in tokenAddr
    uint256 loanAmountInToken = __daiToToken(compoundTokenAddr, loanAmountInDAI);
    dai.safeApprove(address(CDAI), 0); // Clear DAI allowance of Compound DAI market
    dai.safeApprove(address(CDAI), collateralAmountInDAI); // Approve DAI transfer to Compound DAI market
    require(CDAI.mint(collateralAmountInDAI) == 0); // Transfer DAI into Compound as supply
    dai.safeApprove(address(CDAI), 0);
    require(market.borrow(loanAmountInToken) == 0);// Take out loan
    (bool negLiquidity, ) = getCurrentLiquidityInDAI();
    require(!negLiquidity); // Ensure account liquidity is positive

    // Convert loaned tokens to DAI
    (uint256 actualDAIAmount,) = __sellTokenForDAI(loanAmountInToken);
    loanAmountInDAI = actualDAIAmount; // Change loan amount to actual DAI received

    // Repay leftover tokens to avoid complications
    if (address(this).balance > 0) {
      uint256 repayAmount = address(this).balance;
      market.repayBorrow.value(repayAmount)();
    }
  }

  function sellOrder(uint256 _minPrice, uint256 _maxPrice)
    public
    onlyOwner
    isValidPrice(_minPrice, _maxPrice)
    returns (uint256 _inputAmount, uint256 _outputAmount)
  {
    require(buyTime > 0); // Ensure the order has been executed
    require(isSold == false);
    isSold = true;

    // Siphon remaining collateral by repaying x DAI and getting back 1.5x DAI collateral
    // Repeat to ensure debt is exhausted
    for (uint256 i = 0; i < MAX_REPAY_STEPS; i = i.add(1)) {
      uint256 currentDebt = getCurrentBorrowInDAI();
      if (currentDebt > NEGLIGIBLE_DEBT) {
        // Determine amount to be repaid this step
        uint256 currentBalance = getCurrentCashInDAI();
        uint256 repayAmount = 0; // amount to be repaid in DAI
        if (currentDebt <= currentBalance) {
          // Has enough money, repay all debt
          repayAmount = currentDebt;
        } else {
          // Doesn't have enough money, repay whatever we can repay
          repayAmount = currentBalance;
        }

        // Repay debt
        repayLoan(repayAmount);
      }

      // Withdraw all available liquidity
      (bool isNeg, uint256 liquidity) = getCurrentLiquidityInDAI();
      if (!isNeg) {
        uint256 errorCode = CDAI.redeemUnderlying(liquidity.mul(PRECISION.sub(DEFAULT_LIQUIDITY_SLIPPAGE)).div(PRECISION));
        if (errorCode != 0) {
          // error
          // try again with fallback slippage
          errorCode = CDAI.redeemUnderlying(liquidity.mul(PRECISION.sub(FALLBACK_LIQUIDITY_SLIPPAGE)).div(PRECISION));
          if (errorCode != 0) {
            // error
            // try again with max slippage
            CDAI.redeemUnderlying(liquidity.mul(PRECISION.sub(MAX_LIQUIDITY_SLIPPAGE)).div(PRECISION));
          }
        }
      }

      if (currentDebt <= NEGLIGIBLE_DEBT) {
        break;
      }
    }

    // Send DAI back to BetokenFund and return
    _inputAmount = collateralAmountInDAI;
    _outputAmount = dai.balanceOf(address(this));
    outputAmount = _outputAmount;
    dai.safeTransfer(owner(), dai.balanceOf(address(this)));
  }

  // Allows manager to repay loan to avoid liquidation
  function repayLoan(uint256 _repayAmountInDAI) public onlyOwner {
    require(buyTime > 0); // Ensure the order has been executed

    // Convert DAI to shorting token
    (,uint256 actualTokenAmount) = __sellDAIForToken(_repayAmountInDAI);

    // Check if amount is greater than borrow balance
    CEther market = CEther(compoundTokenAddr);
    uint256 currentDebt = market.borrowBalanceCurrent(address(this));
    if (actualTokenAmount > currentDebt) {
      actualTokenAmount = currentDebt;
    }

    // Repay loan to Compound
    market.repayBorrow.value(actualTokenAmount)();
  }

  function getMarketCollateralFactor() public view returns (uint256) {
    (, uint256 ratio) = COMPTROLLER.markets(address(CDAI));
    return ratio;
  }

  function getCurrentCollateralInDAI() public returns (uint256 _amount) {
    uint256 supply = CDAI.balanceOf(address(this)).mul(CDAI.exchangeRateCurrent()).div(PRECISION);
    return supply;
  }

  function getCurrentBorrowInDAI() public returns (uint256 _amount) {
    CEther market = CEther(compoundTokenAddr);
    uint256 borrow = __tokenToDAI(compoundTokenAddr, market.borrowBalanceCurrent(address(this)));
    return borrow;
  }

  function getCurrentCashInDAI() public view returns (uint256 _amount) {
    uint256 cash = getBalance(dai, address(this));
    return cash;
  }
}