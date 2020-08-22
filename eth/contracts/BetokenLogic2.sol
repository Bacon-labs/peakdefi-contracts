pragma solidity 0.5.17;

import "./BetokenStorage.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title Part of the functions for BetokenFund
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenLogic2 is
    BetokenStorage,
    Utils(address(0), address(0), address(0))
{
    /**
     * @notice Passes if the fund has not finalized the next smart contract to upgrade to
     */
    modifier notReadyForUpgrade {
        require(hasFinalizedNextVersion == false);
        _;
    }

    /**
     * @notice Executes function only during the given cycle phase.
     * @param phase the cycle phase during which the function may be called
     */
    modifier during(CyclePhase phase) {
        require(cyclePhase == phase);
        if (cyclePhase == CyclePhase.Intermission) {
            require(isInitialized);
        }
        _;
    }

    /**
     * Deposit & Withdraw
     */

    /**
     * @notice Deposit Ether into the fund. Ether will be converted into DAI.
     */
    function depositEther(address _referrer)
        public
        payable
        nonReentrant
        notReadyForUpgrade
    {
        // Buy DAI with ETH
        uint256 actualDAIDeposited;
        uint256 actualETHDeposited;
        (, , actualDAIDeposited, actualETHDeposited) = __kyberTrade(
            ETH_TOKEN_ADDRESS,
            msg.value,
            dai
        );

        // Send back leftover ETH
        uint256 leftOverETH = msg.value.sub(actualETHDeposited);
        if (leftOverETH > 0) {
            msg.sender.transfer(leftOverETH);
        }

        // Register investment
        __deposit(actualDAIDeposited, _referrer);

        // Emit event
        emit Deposit(
            cycleNumber,
            msg.sender,
            address(ETH_TOKEN_ADDRESS),
            actualETHDeposited,
            actualDAIDeposited,
            now
        );
    }

    /**
     * @notice Deposit DAI Stablecoin into the fund.
     * @param _daiAmount The amount of DAI to be deposited. May be different from actual deposited amount.
     */
    function depositDAI(uint256 _daiAmount, address _referrer)
        public
        nonReentrant
        notReadyForUpgrade
    {
        dai.safeTransferFrom(msg.sender, address(this), _daiAmount);

        // Register investment
        __deposit(_daiAmount, _referrer);

        // Emit event
        emit Deposit(
            cycleNumber,
            msg.sender,
            DAI_ADDR,
            _daiAmount,
            _daiAmount,
            now
        );
    }

    /**
     * @notice Deposit ERC20 tokens into the fund. Tokens will be converted into DAI.
     * @param _tokenAddr the address of the token to be deposited
     * @param _tokenAmount The amount of tokens to be deposited. May be different from actual deposited amount.
     */
    function depositToken(
        address _tokenAddr,
        uint256 _tokenAmount,
        address _referrer
    ) public nonReentrant notReadyForUpgrade isValidToken(_tokenAddr) {
        require(
            _tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS)
        );

        ERC20Detailed token = ERC20Detailed(_tokenAddr);

        token.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        // Convert token into DAI
        uint256 actualDAIDeposited;
        uint256 actualTokenDeposited;
        (, , actualDAIDeposited, actualTokenDeposited) = __kyberTrade(
            token,
            _tokenAmount,
            dai
        );

        // Give back leftover tokens
        uint256 leftOverTokens = _tokenAmount.sub(actualTokenDeposited);
        if (leftOverTokens > 0) {
            token.safeTransfer(msg.sender, leftOverTokens);
        }

        // Register investment
        __deposit(actualDAIDeposited, _referrer);

        // Emit event
        emit Deposit(
            cycleNumber,
            msg.sender,
            _tokenAddr,
            actualTokenDeposited,
            actualDAIDeposited,
            now
        );
    }

    /**
     * @notice Withdraws Ether by burning Shares.
     * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawEther(uint256 _amountInDAI)
        public
        nonReentrant
        during(CyclePhase.Intermission)
    {
        // Buy ETH
        uint256 actualETHWithdrawn;
        uint256 actualDAIWithdrawn;
        (, , actualETHWithdrawn, actualDAIWithdrawn) = __kyberTrade(
            dai,
            _amountInDAI,
            ETH_TOKEN_ADDRESS
        );

        __withdraw(actualDAIWithdrawn);

        // Transfer Ether to user
        msg.sender.transfer(actualETHWithdrawn);

        // Emit event
        emit Withdraw(
            cycleNumber,
            msg.sender,
            address(ETH_TOKEN_ADDRESS),
            actualETHWithdrawn,
            actualDAIWithdrawn,
            now
        );
    }

    /**
     * @notice Withdraws Ether by burning Shares.
     * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawDAI(uint256 _amountInDAI)
        public
        nonReentrant
        during(CyclePhase.Intermission)
    {
        __withdraw(_amountInDAI);

        // Transfer DAI to user
        dai.safeTransfer(msg.sender, _amountInDAI);

        // Emit event
        emit Withdraw(
            cycleNumber,
            msg.sender,
            DAI_ADDR,
            _amountInDAI,
            _amountInDAI,
            now
        );
    }

    /**
     * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
     * @param _tokenAddr the address of the token to be withdrawn into the caller's account
     * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawToken(address _tokenAddr, uint256 _amountInDAI)
        public
        during(CyclePhase.Intermission)
        nonReentrant
        isValidToken(_tokenAddr)
    {
        require(
            _tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS)
        );

        ERC20Detailed token = ERC20Detailed(_tokenAddr);

        // Convert DAI into desired tokens
        uint256 actualTokenWithdrawn;
        uint256 actualDAIWithdrawn;
        (, , actualTokenWithdrawn, actualDAIWithdrawn) = __kyberTrade(
            dai,
            _amountInDAI,
            token
        );

        __withdraw(actualDAIWithdrawn);

        // Transfer tokens to user
        token.safeTransfer(msg.sender, actualTokenWithdrawn);

        // Emit event
        emit Withdraw(
            cycleNumber,
            msg.sender,
            _tokenAddr,
            actualTokenWithdrawn,
            actualDAIWithdrawn,
            now
        );
    }

    /**
     * Manager registration
     */

    /**
     * @notice Registers `msg.sender` as a manager, using DAI as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     */
    function registerWithDAI()
        public
        during(CyclePhase.Intermission)
        nonReentrant
    {
        require(managersOnboardedThisCycle < maxNewManagersPerCycle);
        managersOnboardedThisCycle = managersOnboardedThisCycle.add(1);

        uint256 donationInDAI = newManagerKairo.mul(kairoPrice).div(PRECISION);
        dai.safeTransferFrom(msg.sender, address(this), donationInDAI);
        __register(donationInDAI);
    }

    /**
     * @notice Registers `msg.sender` as a manager, using ETH as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     */
    function registerWithETH()
        public
        payable
        during(CyclePhase.Intermission)
        nonReentrant
    {
        require(managersOnboardedThisCycle < maxNewManagersPerCycle);
        managersOnboardedThisCycle = managersOnboardedThisCycle.add(1);

        uint256 receivedDAI;

        // trade ETH for DAI
        (, , receivedDAI, ) = __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);

        // if DAI value is greater than the amount required, return excess DAI to msg.sender
        uint256 donationInDAI = newManagerKairo.mul(kairoPrice).div(PRECISION);
        if (receivedDAI > donationInDAI) {
            dai.safeTransfer(msg.sender, receivedDAI.sub(donationInDAI));
            receivedDAI = donationInDAI;
        }

        // register new manager
        __register(receivedDAI);
    }

    /**
     * @notice Registers `msg.sender` as a manager, using tokens as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     * @param _token the token to be used for payment
     * @param _donationInTokens the amount of tokens to be used for registration, should use the token's native decimals
     */
    function registerWithToken(address _token, uint256 _donationInTokens)
        public
        during(CyclePhase.Intermission)
        nonReentrant
    {
        require(managersOnboardedThisCycle < maxNewManagersPerCycle);
        managersOnboardedThisCycle = managersOnboardedThisCycle.add(1);
        require(
            _token != address(0) &&
                _token != address(ETH_TOKEN_ADDRESS) &&
                _token != DAI_ADDR
        );
        ERC20Detailed token = ERC20Detailed(_token);
        require(token.totalSupply() > 0);

        token.safeTransferFrom(msg.sender, address(this), _donationInTokens);

        uint256 receivedDAI;

        (, , receivedDAI, ) = __kyberTrade(token, _donationInTokens, dai);

        // if DAI value is greater than the amount required, return excess DAI to msg.sender
        uint256 donationInDAI = newManagerKairo.mul(kairoPrice).div(PRECISION);
        if (receivedDAI > donationInDAI) {
            dai.safeTransfer(msg.sender, receivedDAI.sub(donationInDAI));
            receivedDAI = donationInDAI;
        }

        // register new manager
        __register(receivedDAI);
    }

    /**
     * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
     * @param _tokenAddr address of the token to be sold
     */
    function sellLeftoverToken(address _tokenAddr)
        public
        during(CyclePhase.Intermission)
        nonReentrant
        isValidToken(_tokenAddr)
    {
        ERC20Detailed token = ERC20Detailed(_tokenAddr);
        (, , uint256 actualDAIReceived, ) = __kyberTrade(
            token,
            getBalance(token, address(this)),
            dai
        );
        totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
    }

    /**
     * @notice Sells CompoundOrder left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
     * @param _orderAddress address of the CompoundOrder to be sold
     */
    function sellLeftoverCompoundOrder(address payable _orderAddress)
        public
        during(CyclePhase.Intermission)
        nonReentrant
    {
        // Load order info
        require(_orderAddress != address(0));
        CompoundOrder order = CompoundOrder(_orderAddress);
        require(order.isSold() == false && order.cycleNumber() < cycleNumber);

        // Sell short order
        // Not using outputAmount returned by order.sellOrder() because _orderAddress could point to a malicious contract
        uint256 beforeDAIBalance = dai.balanceOf(address(this));
        order.sellOrder(0, MAX_QTY);
        uint256 actualDAIReceived = dai.balanceOf(address(this)).sub(
            beforeDAIBalance
        );

        totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
    }

    /**
     * @notice Registers `msg.sender` as a manager.
     * @param _donationInDAI the amount of DAI to be used for registration
     */
    function __register(uint256 _donationInDAI) internal {
        require(
            cToken.balanceOf(msg.sender) == 0 &&
                userInvestments[msg.sender].length == 0 &&
                userCompoundOrders[msg.sender].length == 0
        ); // each address can only join once

        // mint KRO for msg.sender
        uint256 kroAmount = _donationInDAI.mul(PRECISION).div(kairoPrice);
        require(cToken.generateTokens(msg.sender, kroAmount));

        // Set risk fallback base stake
        _baseRiskStakeFallback[msg.sender] = kroAmount;

        // Set last active cycle for msg.sender to be the current cycle
        _lastActiveCycle[msg.sender] = cycleNumber;

        // keep DAI in the fund
        totalFundsInDAI = totalFundsInDAI.add(_donationInDAI);

        // emit events
        emit Register(msg.sender, _donationInDAI, kroAmount);
    }

    /**
     * @notice Handles deposits by minting Betoken Shares & updating total funds.
     * @param _depositDAIAmount The amount of the deposit in DAI
     * @param _referrer The deposit referrer
     */
    function __deposit(uint256 _depositDAIAmount, address _referrer) internal {
        // Register investment and give shares
        uint256 shareAmount;
        if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
            shareAmount = _depositDAIAmount;
        } else {
            shareAmount = _depositDAIAmount.mul(sToken.totalSupply()).div(
                totalFundsInDAI
            );
        }
        require(sToken.generateTokens(msg.sender, shareAmount));
        totalFundsInDAI = totalFundsInDAI.add(_depositDAIAmount);
        totalFundsAtManagePhaseStart = totalFundsAtManagePhaseStart.add(
            _depositDAIAmount
        );

        // Handle peakReferralToken
        if (peakReward.canRefer(msg.sender, _referrer)) {
            peakReward.refer(msg.sender, _referrer);
        }
        address actualReferrer = peakReward.referrerOf(msg.sender);
        if (actualReferrer != address(0)) {
            require(
                peakReferralToken.generateTokens(actualReferrer, shareAmount)
            );
        }
    }

    /**
     * @notice Handles deposits by burning Betoken Shares & updating total funds.
     * @param _withdrawDAIAmount The amount of the withdrawal in DAI
     */
    function __withdraw(uint256 _withdrawDAIAmount) internal {
        // Burn Shares
        uint256 shareAmount = _withdrawDAIAmount.mul(sToken.totalSupply()).div(
            totalFundsInDAI
        );
        require(sToken.destroyTokens(msg.sender, shareAmount));
        totalFundsInDAI = totalFundsInDAI.sub(_withdrawDAIAmount);

        // Handle peakReferralToken
        address actualReferrer = peakReward.referrerOf(msg.sender);
        if (actualReferrer != address(0)) {
            uint256 balance = peakReferralToken.balanceOf(actualReferrer);
            uint256 burnReferralTokenAmount = shareAmount > balance
                ? balance
                : shareAmount;
            require(
                peakReferralToken.destroyTokens(
                    actualReferrer,
                    burnReferralTokenAmount
                )
            );
        }
    }
}
