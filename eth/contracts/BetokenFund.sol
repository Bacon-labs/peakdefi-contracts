pragma solidity 0.5.17;

import "./BetokenStorage.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title The main smart contract of the Betoken hedge fund.
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenFund is
    BetokenStorage,
    Utils(address(0), address(0), address(0)),
    TokenController
{
    /**
     * @notice Passes if the fund is ready for migrating to the next version
     */
    modifier readyForUpgradeMigration {
        require(hasFinalizedNextVersion == true);
        require(
            now >
                startTimeOfCyclePhase.add(
                    phaseLengths[uint256(CyclePhase.Intermission)]
                )
        );
        _;
    }

    /**
     * Meta functions
     */

    function initParams(
        address payable _devFundingAccount,
        uint256[2] calldata _phaseLengths,
        uint256 _devFundingRate,
        address payable _previousVersion,
        address _daiAddr,
        address payable _kyberAddr,
        address _compoundFactoryAddr,
        address _betokenLogic,
        address _betokenLogic2,
        address _betokenLogic3,
        uint256 _startCycleNumber,
        address payable _oneInchAddr,
        address _peakRewardAddr,
        address _peakStakingAddr
    ) external {
        require(proxyAddr == address(0));
        devFundingAccount = _devFundingAccount;
        phaseLengths = _phaseLengths;
        devFundingRate = _devFundingRate;
        cyclePhase = CyclePhase.Intermission;
        compoundFactoryAddr = _compoundFactoryAddr;
        betokenLogic = _betokenLogic;
        betokenLogic2 = _betokenLogic2;
        betokenLogic3 = _betokenLogic3;
        previousVersion = _previousVersion;
        cycleNumber = _startCycleNumber;

        peakReward = PeakReward(_peakRewardAddr);
        peakStaking = PeakStaking(_peakStakingAddr);

        DAI_ADDR = _daiAddr;
        KYBER_ADDR = _kyberAddr;
        ONEINCH_ADDR = _oneInchAddr;

        dai = ERC20Detailed(_daiAddr);
        kyber = KyberNetwork(_kyberAddr);

        __initReentrancyGuard();
    }

    function initOwner() external {
        require(proxyAddr == address(0));
        _transferOwnership(msg.sender);
    }

    function initInternalTokens(
        address payable _kroAddr,
        address payable _sTokenAddr,
        address payable _peakReferralTokenAddr
    ) external onlyOwner {
        require(controlTokenAddr == address(0));
        require(_kroAddr != address(0));
        controlTokenAddr = _kroAddr;
        shareTokenAddr = _sTokenAddr;
        cToken = IMiniMeToken(_kroAddr);
        sToken = IMiniMeToken(_sTokenAddr);
        peakReferralToken = IMiniMeToken(_peakReferralTokenAddr);
    }

    function initRegistration(
        uint256 _newManagerKairo,
        uint256 _maxNewManagersPerCycle,
        uint256 _kairoPrice,
        uint256 _peakManagerStakeRequired,
        bool _isPermissioned
    ) external onlyOwner {
        require(_newManagerKairo > 0 && newManagerKairo == 0);
        newManagerKairo = _newManagerKairo;
        maxNewManagersPerCycle = _maxNewManagersPerCycle;
        kairoPrice = _kairoPrice;
        peakManagerStakeRequired = _peakManagerStakeRequired;
        isPermissioned = _isPermissioned;
    }

    function initTokenListings(
        address[] calldata _kyberTokens,
        address[] calldata _compoundTokens
    ) external onlyOwner {
        // May only initialize once
        require(!hasInitializedTokenListings);
        hasInitializedTokenListings = true;

        uint256 i;
        for (i = 0; i < _kyberTokens.length; i = i.add(1)) {
            isKyberToken[_kyberTokens[i]] = true;
        }

        for (i = 0; i < _compoundTokens.length; i = i.add(1)) {
            isCompoundToken[_compoundTokens[i]] = true;
        }
    }

    /**
     * @notice Used during deployment to set the BetokenProxy contract address.
     * @param _proxyAddr the proxy's address
     */
    function setProxy(address payable _proxyAddr) external onlyOwner {
        require(_proxyAddr != address(0));
        require(proxyAddr == address(0));
        proxyAddr = _proxyAddr;
        proxy = BetokenProxyInterface(_proxyAddr);
    }

    /**
     * Upgrading functions
     */

    /**
     * @notice Allows the developer to propose a candidate smart contract for the fund to upgrade to.
     *          The developer may change the candidate during the Intermission phase.
     * @param _candidate the address of the candidate smart contract
     * @return True if successfully changed candidate, false otherwise.
     */
    function developerInitiateUpgrade(address payable _candidate)
        public
        returns (bool _success)
    {
        (bool success, bytes memory result) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(
                this.developerInitiateUpgrade.selector,
                _candidate
            )
        );
        if (!success) {
            return false;
        }
        return abi.decode(result, (bool));
    }

    /**
     * @notice Transfers ownership of Kairo & Share token contracts to the next version. Also updates BetokenFund's
     *         address in BetokenProxy.
     */
    function migrateOwnedContractsToNextVersion()
        public
        nonReentrant
        readyForUpgradeMigration
    {
        cToken.transferOwnership(nextVersion);
        sToken.transferOwnership(nextVersion);
        proxy.updateBetokenFundAddress();
    }

    /**
     * @notice Transfers assets to the next version.
     * @param _assetAddress the address of the asset to be transferred. Use ETH_TOKEN_ADDRESS to transfer Ether.
     */
    function transferAssetToNextVersion(address _assetAddress)
        public
        nonReentrant
        readyForUpgradeMigration
        isValidToken(_assetAddress)
    {
        if (_assetAddress == address(ETH_TOKEN_ADDRESS)) {
            nextVersion.transfer(address(this).balance);
        } else {
            ERC20Detailed token = ERC20Detailed(_assetAddress);
            token.safeTransfer(nextVersion, token.balanceOf(address(this)));
        }
    }

    /**
     * Getters
     */

    /**
     * @notice Returns the length of the user's investments array.
     * @return length of the user's investments array
     */
    function investmentsCount(address _userAddr)
        public
        view
        returns (uint256 _count)
    {
        return userInvestments[_userAddr].length;
    }

    /**
     * @notice Returns the length of the user's compound orders array.
     * @return length of the user's compound orders array
     */
    function compoundOrdersCount(address _userAddr)
        public
        view
        returns (uint256 _count)
    {
        return userCompoundOrders[_userAddr].length;
    }

    /**
     * @notice Returns the phaseLengths array.
     * @return the phaseLengths array
     */
    function getPhaseLengths()
        public
        view
        returns (uint256[2] memory _phaseLengths)
    {
        return phaseLengths;
    }

    /**
     * @notice Returns the commission balance of `_manager`
     * @return the commission balance and the received penalty, denoted in DAI
     */
    function commissionBalanceOf(address _manager)
        public
        returns (uint256 _commission, uint256 _penalty)
    {
        (bool success, bytes memory result) = betokenLogic.delegatecall(
            abi.encodeWithSelector(this.commissionBalanceOf.selector, _manager)
        );
        if (!success) {
            return (0, 0);
        }
        return abi.decode(result, (uint256, uint256));
    }

    /**
     * @notice Returns the commission amount received by `_manager` in the `_cycle`th cycle
     * @return the commission amount and the received penalty, denoted in DAI
     */
    function commissionOfAt(address _manager, uint256 _cycle)
        public
        returns (uint256 _commission, uint256 _penalty)
    {
        (bool success, bytes memory result) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.commissionOfAt.selector,
                _manager,
                _cycle
            )
        );
        if (!success) {
            return (0, 0);
        }
        return abi.decode(result, (uint256, uint256));
    }

    /**
     * Parameter setters
     */

    /**
     * @notice Changes the address to which the developer fees will be sent. Only callable by owner.
     * @param _newAddr the new developer fee address
     */
    function changeDeveloperFeeAccount(address payable _newAddr)
        public
        onlyOwner
    {
        require(_newAddr != address(0) && _newAddr != address(this));
        devFundingAccount = _newAddr;
    }

    /**
     * @notice Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
     * @param _newProp the new proportion, fixed point decimal
     */
    function changeDeveloperFeeRate(uint256 _newProp) public onlyOwner {
        require(_newProp < PRECISION);
        require(_newProp < devFundingRate);
        devFundingRate = _newProp;
    }

    /**
     * @notice Allows managers to invest in a token. Only callable by owner.
     * @param _token address of the token to be listed
     */
    function listKyberToken(address _token) public onlyOwner {
        isKyberToken[_token] = true;
    }

    /**
     * @notice Allows managers to invest in a Compound token. Only callable by owner.
     * @param _token address of the Compound token to be listed
     */
    function listCompoundToken(address _token) public onlyOwner {
        CompoundOrderFactory factory = CompoundOrderFactory(
            compoundFactoryAddr
        );
        require(factory.tokenIsListed(_token));
        isCompoundToken[_token] = true;
    }

    /**
     * @notice Moves the fund to the next phase in the investment cycle.
     */
    function nextPhase() public {
        (bool success, ) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(this.nextPhase.selector)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * Manager registration
     */

    /**
     * @notice Registers `msg.sender` as a manager, using DAI as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     */
    function registerWithDAI() public {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(this.registerWithDAI.selector)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Registers `msg.sender` as a manager, using ETH as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     */
    function registerWithETH() public payable {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(this.registerWithETH.selector)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Registers `msg.sender` as a manager, using tokens as payment. The more one pays, the more Kairo one gets.
     *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
     * @param _token the token to be used for payment
     * @param _donationInTokens the amount of tokens to be used for registration, should use the token's native decimals
     */
    function registerWithToken(address _token, uint256 _donationInTokens)
        public
    {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.registerWithToken.selector,
                _token,
                _donationInTokens
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * Intermission phase functions
     */

    /**
     * @notice Deposit Ether into the fund. Ether will be converted into DAI.
     */
    function depositEther(address _referrer) public payable {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(this.depositEther.selector, _referrer)
        );
        if (!success) {
            revert();
        }
    }

    function depositEtherAdvanced(
        bool _useKyber,
        bytes calldata _calldata,
        address _referrer
    ) external payable {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.depositEtherAdvanced.selector,
                _useKyber,
                _calldata,
                _referrer
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Deposit DAI Stablecoin into the fund.
     * @param _daiAmount The amount of DAI to be deposited. May be different from actual deposited amount.
     */
    function depositDAI(uint256 _daiAmount, address _referrer) public {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.depositDAI.selector,
                _daiAmount,
                _referrer
            )
        );
        if (!success) {
            revert();
        }
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
    ) public {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.depositToken.selector,
                _tokenAddr,
                _tokenAmount,
                _referrer
            )
        );
        if (!success) {
            revert();
        }
    }

    function depositTokenAdvanced(
        address _tokenAddr,
        uint256 _tokenAmount,
        bool _useKyber,
        bytes calldata _calldata,
        address _referrer
    ) external {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.depositTokenAdvanced.selector,
                _tokenAddr,
                _tokenAmount,
                _useKyber,
                _calldata,
                _referrer
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Withdraws Ether by burning Shares.
     * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawEther(uint256 _amountInDAI) external {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(this.withdrawEther.selector, _amountInDAI)
        );
        if (!success) {
            revert();
        }
    }

    function withdrawEtherAdvanced(
        uint256 _amountInDAI,
        bool _useKyber,
        bytes calldata _calldata
    ) external {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.withdrawEtherAdvanced.selector,
                _amountInDAI,
                _useKyber,
                _calldata
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Withdraws Ether by burning Shares.
     * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawDAI(uint256 _amountInDAI) public {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(this.withdrawDAI.selector, _amountInDAI)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
     * @param _tokenAddr the address of the token to be withdrawn into the caller's account
     * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
     */
    function withdrawToken(address _tokenAddr, uint256 _amountInDAI) external {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.withdrawToken.selector,
                _tokenAddr,
                _amountInDAI
            )
        );
        if (!success) {
            revert();
        }
    }

    function withdrawTokenAdvanced(
        address _tokenAddr,
        uint256 _amountInDAI,
        bool _useKyber,
        bytes calldata _calldata
    ) external {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.withdrawTokenAdvanced.selector,
                _tokenAddr,
                _amountInDAI,
                _useKyber,
                _calldata
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Redeems commission.
     */
    function redeemCommission(bool _inShares) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(this.redeemCommission.selector, _inShares)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Redeems commission for a particular cycle.
     * @param _inShares true to redeem in Betoken Shares, false to redeem in DAI
     * @param _cycle the cycle for which the commission will be redeemed.
     *        Commissions for a cycle will be redeemed during the Intermission phase of the next cycle, so _cycle must < cycleNumber.
     */
    function redeemCommissionForCycle(bool _inShares, uint256 _cycle) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.redeemCommissionForCycle.selector,
                _inShares,
                _cycle
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
     * @param _tokenAddr address of the token to be sold
     * @param _calldata the 1inch trade call data
     */
    function sellLeftoverToken(address _tokenAddr, bytes calldata _calldata)
        external
    {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.sellLeftoverToken.selector,
                _tokenAddr,
                _calldata
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Sells CompoundOrder left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
     * @param _orderAddress address of the CompoundOrder to be sold
     */
    function sellLeftoverCompoundOrder(address payable _orderAddress) public {
        (bool success, ) = betokenLogic2.delegatecall(
            abi.encodeWithSelector(
                this.sellLeftoverCompoundOrder.selector,
                _orderAddress
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Burns the Kairo balance of a manager who has been inactive for a certain number of cycles
     * @param _deadman the manager whose Kairo balance will be burned
     */
    function burnDeadman(address _deadman) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(this.burnDeadman.selector, _deadman)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * Manage phase functions
     */

    /**
     * @notice Creates a new investment for an ERC20 token.
     * @param _tokenAddress address of the ERC20 token contract
     * @param _stake amount of Kairos to be staked in support of the investment
     * @param _minPrice the minimum price for the trade
     * @param _maxPrice the maximum price for the trade
     */
    function createInvestment(
        address _tokenAddress,
        uint256 _stake,
        uint256 _minPrice,
        uint256 _maxPrice
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.createInvestment.selector,
                _tokenAddress,
                _stake,
                _minPrice,
                _maxPrice
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Creates a new investment for an ERC20 token.
     * @param _tokenAddress address of the ERC20 token contract
     * @param _stake amount of Kairos to be staked in support of the investment
     * @param _minPrice the minimum price for the trade
     * @param _maxPrice the maximum price for the trade
     * @param _calldata calldata for 1inch trading
     * @param _useKyber true for Kyber Network, false for 1inch
     */
    function createInvestmentV2(
        address _tokenAddress,
        uint256 _stake,
        uint256 _minPrice,
        uint256 _maxPrice,
        bytes memory _calldata,
        bool _useKyber
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.createInvestmentV2.selector,
                _tokenAddress,
                _stake,
                _minPrice,
                _maxPrice,
                _calldata,
                _useKyber
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties to the user.
     *         The user can sell only part of the investment by changing _tokenAmount.
     * @dev When selling only part of an investment, the old investment would be "fully" sold and a new investment would be created with
     *   the original buy price and however much tokens that are not sold.
     * @param _investmentId the ID of the investment
     * @param _tokenAmount the amount of tokens to be sold.
     * @param _minPrice the minimum price for the trade
     * @param _maxPrice the maximum price for the trade
     */
    function sellInvestmentAsset(
        uint256 _investmentId,
        uint256 _tokenAmount,
        uint256 _minPrice,
        uint256 _maxPrice
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.sellInvestmentAsset.selector,
                _investmentId,
                _tokenAmount,
                _minPrice,
                _maxPrice
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties to the user.
     *         The user can sell only part of the investment by changing _tokenAmount.
     * @dev When selling only part of an investment, the old investment would be "fully" sold and a new investment would be created with
     *   the original buy price and however much tokens that are not sold.
     * @param _investmentId the ID of the investment
     * @param _tokenAmount the amount of tokens to be sold.
     * @param _minPrice the minimum price for the trade
     * @param _maxPrice the maximum price for the trade
     */
    function sellInvestmentAssetV2(
        uint256 _investmentId,
        uint256 _tokenAmount,
        uint256 _minPrice,
        uint256 _maxPrice,
        bytes memory _calldata,
        bool _useKyber
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.sellInvestmentAssetV2.selector,
                _investmentId,
                _tokenAmount,
                _minPrice,
                _maxPrice,
                _calldata,
                _useKyber
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Creates a new Compound order to either short or leverage long a token.
     * @param _orderType true for a short order, false for a levarage long order
     * @param _tokenAddress address of the Compound token to be traded
     * @param _stake amount of Kairos to be staked
     * @param _minPrice the minimum token price for the trade
     * @param _maxPrice the maximum token price for the trade
     */
    function createCompoundOrder(
        bool _orderType,
        address _tokenAddress,
        uint256 _stake,
        uint256 _minPrice,
        uint256 _maxPrice
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.createCompoundOrder.selector,
                _orderType,
                _tokenAddress,
                _stake,
                _minPrice,
                _maxPrice
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Sells a compound order
     * @param _orderId the ID of the order to be sold (index in userCompoundOrders[msg.sender])
     * @param _minPrice the minimum token price for the trade
     * @param _maxPrice the maximum token price for the trade
     */
    function sellCompoundOrder(
        uint256 _orderId,
        uint256 _minPrice,
        uint256 _maxPrice
    ) public {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.sellCompoundOrder.selector,
                _orderId,
                _minPrice,
                _maxPrice
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Repys debt for a Compound order to prevent the collateral ratio from dropping below threshold.
     * @param _orderId the ID of the Compound order
     * @param _repayAmountInDAI amount of DAI to use for repaying debt
     */
    function repayCompoundOrder(uint256 _orderId, uint256 _repayAmountInDAI)
        public
    {
        (bool success, ) = betokenLogic.delegatecall(
            abi.encodeWithSelector(
                this.repayCompoundOrder.selector,
                _orderId,
                _repayAmountInDAI
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * Internal use functions
     */

    // MiniMe TokenController functions, not used right now
    /**
     * @notice Called when `_owner` sends ether to the MiniMe Token contract
     * @return True if the ether is accepted, false if it throws
     */
    function proxyPayment(
        address /*_owner*/
    ) public payable returns (bool) {
        return false;
    }

    /**
     * @notice Notifies the controller about a token transfer allowing the
     *  controller to react if desired
     * @return False if the controller does not authorize the transfer
     */
    function onTransfer(
        address, /*_from*/
        address, /*_to*/
        uint256 /*_amount*/
    ) public returns (bool) {
        return true;
    }

    /**
     * @notice Notifies the controller about an approval allowing the
     *  controller to react if desired
     * @return False if the controller does not authorize the approval
     */
    function onApprove(
        address, /*_owner*/
        address, /*_spender*/
        uint256 /*_amount*/
    ) public returns (bool) {
        return true;
    }

    function() external payable {}

    /**
    PeakDeFi
   */

    /**
     * @notice Returns the commission balance of `_referrer`
     * @return the commission balance and the received penalty, denoted in DAI
     */
    function peakReferralCommissionBalanceOf(address _referrer)
        public
        returns (uint256 _commission)
    {
        (bool success, bytes memory result) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(
                this.peakReferralCommissionBalanceOf.selector,
                _referrer
            )
        );
        if (!success) {
            return 0;
        }
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Returns the commission amount received by `_referrer` in the `_cycle`th cycle
     * @return the commission amount and the received penalty, denoted in DAI
     */
    function peakReferralCommissionOfAt(address _referrer, uint256 _cycle)
        public
        returns (uint256 _commission)
    {
        (bool success, bytes memory result) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(
                this.peakReferralCommissionOfAt.selector,
                _referrer,
                _cycle
            )
        );
        if (!success) {
            return 0;
        }
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Redeems commission.
     */
    function peakReferralRedeemCommission() public {
        (bool success, ) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(this.peakReferralRedeemCommission.selector)
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Redeems commission for a particular cycle.
     * @param _cycle the cycle for which the commission will be redeemed.
     *        Commissions for a cycle will be redeemed during the Intermission phase of the next cycle, so _cycle must < cycleNumber.
     */
    function peakReferralRedeemCommissionForCycle(uint256 _cycle) public {
        (bool success, ) = betokenLogic3.delegatecall(
            abi.encodeWithSelector(
                this.peakReferralRedeemCommissionForCycle.selector,
                _cycle
            )
        );
        if (!success) {
            revert();
        }
    }

    /**
     * @notice Changes the required PEAK stake of a new manager. Only callable by owner.
     * @param _newValue the new value
     */
    function peakChangeManagerStakeRequired(uint256 _newValue)
        public
        onlyOwner
    {
        peakManagerStakeRequired = _newValue;
    }
}
