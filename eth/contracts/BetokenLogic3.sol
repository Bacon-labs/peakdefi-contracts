pragma solidity 0.5.17;

import "./BetokenStorage.sol";

contract BetokenLogic3 is
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
     * Next phase transition handler
     * @notice Moves the fund to the next phase in the investment cycle.
     */
    function nextPhase() public nonReentrant {
        require(
            now >= startTimeOfCyclePhase.add(phaseLengths[uint256(cyclePhase)])
        );

        if (isInitialized == false) {
            // first cycle of this smart contract deployment
            // check whether ready for starting cycle
            isInitialized = true;
            require(proxyAddr != address(0)); // has initialized proxy
            require(proxy.betokenFundAddress() == address(this)); // upgrade complete
            require(hasInitializedTokenListings); // has initialized token listings

            // execute initialization function
            __init();

            require(
                previousVersion == address(0) ||
                    (previousVersion != address(0) &&
                        getBalance(dai, address(this)) > 0)
            ); // has transfered assets from previous version
        } else {
            // normal phase changing
            if (cyclePhase == CyclePhase.Intermission) {
                require(hasFinalizedNextVersion == false); // Shouldn't progress to next phase if upgrading

                // Update total funds at management phase's beginning
                totalFundsAtManagePhaseStart = totalFundsInDAI;

                // reset number of managers onboarded
                managersOnboardedThisCycle = 0;
            } else if (cyclePhase == CyclePhase.Manage) {
                // Burn any Kairo left in BetokenFund's account
                require(
                    cToken.destroyTokens(
                        address(this),
                        cToken.balanceOf(address(this))
                    )
                );

                // Pay out commissions and fees
                uint256 profit = 0;


                    uint256 daiBalanceAtManagePhaseStart
                 = totalFundsAtManagePhaseStart.add(totalCommissionLeft);
                if (
                    getBalance(dai, address(this)) >
                    daiBalanceAtManagePhaseStart
                ) {
                    profit = getBalance(dai, address(this)).sub(
                        daiBalanceAtManagePhaseStart
                    );
                }

                totalFundsInDAI = getBalance(dai, address(this))
                    .sub(totalCommissionLeft)
                    .sub(peakReferralTotalCommissionLeft);

                // Calculate manager commissions
                uint256 commissionThisCycle = COMMISSION_RATE
                    .mul(profit)
                    .add(ASSET_FEE_RATE.mul(totalFundsInDAI))
                    .div(PRECISION);
                _totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle(
                    cycleNumber
                )
                    .add(commissionThisCycle); // account for penalties
                totalCommissionLeft = totalCommissionLeft.add(
                    commissionThisCycle
                );

                // Calculate referrer commissions
                uint256 peakReferralCommissionThisCycle = PEAK_COMMISSION_RATE
                    .mul(profit)
                    .mul(peakReferralToken.totalSupply())
                    .div(sToken.totalSupply())
                    .div(PRECISION);
                _peakReferralTotalCommissionOfCycle[cycleNumber] = peakReferralTotalCommissionOfCycle(
                    cycleNumber
                )
                    .add(peakReferralCommissionThisCycle);
                peakReferralTotalCommissionLeft = peakReferralTotalCommissionLeft
                    .add(peakReferralCommissionThisCycle);

                totalFundsInDAI = getBalance(dai, address(this))
                    .sub(totalCommissionLeft)
                    .sub(peakReferralTotalCommissionLeft);

                // Give the developer Betoken shares inflation funding
                uint256 devFunding = devFundingRate
                    .mul(sToken.totalSupply())
                    .div(PRECISION);
                require(sToken.generateTokens(devFundingAccount, devFunding));

                // Emit event
                emit TotalCommissionPaid(
                    cycleNumber,
                    totalCommissionOfCycle(cycleNumber)
                );
                emit PeakReferralTotalCommissionPaid(
                    cycleNumber,
                    peakReferralTotalCommissionOfCycle(cycleNumber)
                );

                _managePhaseEndBlock[cycleNumber] = block.number;

                // Clear/update upgrade related data
                if (nextVersion == address(this)) {
                    // The developer proposed a candidate, but the managers decide to not upgrade at all
                    // Reset upgrade process
                    delete nextVersion;
                    delete hasFinalizedNextVersion;
                }
                if (nextVersion != address(0)) {
                    hasFinalizedNextVersion = true;
                    emit FinalizedNextVersion(cycleNumber, nextVersion);
                }

                // Start new cycle
                cycleNumber = cycleNumber.add(1);
            }

            cyclePhase = CyclePhase(addmod(uint256(cyclePhase), 1, 2));
        }

        startTimeOfCyclePhase = now;

        // Reward caller if they're a manager
        if (cToken.balanceOf(msg.sender) > 0) {
            require(cToken.generateTokens(msg.sender, NEXT_PHASE_REWARD));
        }

        emit ChangedPhase(
            cycleNumber,
            uint256(cyclePhase),
            now,
            totalFundsInDAI
        );
    }

    /**
     * @notice Initializes several important variables after smart contract upgrade
     */
    function __init() internal {
        _managePhaseEndBlock[cycleNumber.sub(1)] = block.number;

        // load values from previous version
        totalCommissionLeft = previousVersion == address(0)
            ? 0
            : BetokenStorage(previousVersion).totalCommissionLeft();
        totalFundsInDAI = getBalance(dai, address(this)).sub(
            totalCommissionLeft
        );
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
        onlyOwner
        notReadyForUpgrade
        during(CyclePhase.Intermission)
        nonReentrant
        returns (bool _success)
    {
        if (_candidate == address(0) || _candidate == address(this)) {
            return false;
        }
        nextVersion = _candidate;
        emit DeveloperInitiatedUpgrade(cycleNumber, _candidate);
        return true;
    }

    /**
    PeakDeFi
   */

    /**
     * @notice Returns the commission balance of `_referrer`
     * @return the commission balance, denoted in DAI
     */
    function peakReferralCommissionBalanceOf(address _referrer)
        public
        view
        returns (uint256 _commission)
    {
        if (peakReferralLastCommissionRedemption(_referrer) >= cycleNumber) {
            return (0);
        }
        uint256 cycle = peakReferralLastCommissionRedemption(_referrer) > 0
            ? peakReferralLastCommissionRedemption(_referrer)
            : 1;
        uint256 cycleCommission;
        for (; cycle < cycleNumber; cycle = cycle.add(1)) {
            (cycleCommission) = peakReferralCommissionOfAt(_referrer, cycle);
            _commission = _commission.add(cycleCommission);
        }
    }

    /**
     * @notice Returns the commission amount received by `_referrer` in the `_cycle`th cycle
     * @return the commission amount, denoted in DAI
     */
    function peakReferralCommissionOfAt(address _referrer, uint256 _cycle)
        public
        view
        returns (uint256 _commission)
    {
        _commission = peakReferralTotalCommissionOfCycle(_cycle)
            .mul(
            peakReferralToken.balanceOfAt(
                _referrer,
                managePhaseEndBlock(_cycle)
            )
        )
            .div(peakReferralToken.totalSupplyAt(managePhaseEndBlock(_cycle)));
    }

    /**
     * @notice Redeems commission.
     */
    function peakReferralRedeemCommission()
        public
        during(CyclePhase.Intermission)
        nonReentrant
    {
        uint256 commission = __peakReferralRedeemCommission();

        // Transfer the commission in DAI
        dai.safeApprove(address(peakReward), commission);
        peakReward.payCommission(msg.sender, address(dai), commission, false);
    }

    /**
     * @notice Redeems commission for a particular cycle.
     * @param _cycle the cycle for which the commission will be redeemed.
     *        Commissions for a cycle will be redeemed during the Intermission phase of the next cycle, so _cycle must < cycleNumber.
     */
    function peakReferralRedeemCommissionForCycle(uint256 _cycle)
        public
        during(CyclePhase.Intermission)
        nonReentrant
    {
        require(_cycle < cycleNumber);

        uint256 commission = __peakReferralRedeemCommissionForCycle(_cycle);

        // Transfer the commission in DAI
        dai.safeApprove(address(peakReward), commission);
        peakReward.payCommission(msg.sender, address(dai), commission, false);
    }

    /**
     * @notice Redeems the commission for all previous cycles. Updates the related variables.
     * @return the amount of commission to be redeemed
     */
    function __peakReferralRedeemCommission()
        internal
        returns (uint256 _commission)
    {
        require(peakReferralLastCommissionRedemption(msg.sender) < cycleNumber);

        _commission = peakReferralCommissionBalanceOf(msg.sender);

        // record the redemption to prevent double-redemption
        for (
            uint256 i = peakReferralLastCommissionRedemption(msg.sender);
            i < cycleNumber;
            i = i.add(1)
        ) {
            _peakReferralHasRedeemedCommissionForCycle[msg.sender][i] = true;
        }
        _peakReferralLastCommissionRedemption[msg.sender] = cycleNumber;

        // record the decrease in commission pool
        peakReferralTotalCommissionLeft = peakReferralTotalCommissionLeft.sub(
            _commission
        );

        emit PeakReferralCommissionPaid(cycleNumber, msg.sender, _commission);
    }

    /**
     * @notice Redeems commission for a particular cycle. Updates the related variables.
     * @param _cycle the cycle for which the commission will be redeemed
     * @return the amount of commission to be redeemed
     */
    function __peakReferralRedeemCommissionForCycle(uint256 _cycle)
        internal
        returns (uint256 _commission)
    {
        require(!peakReferralHasRedeemedCommissionForCycle(msg.sender, _cycle));

        _commission = peakReferralCommissionOfAt(msg.sender, _cycle);

        _peakReferralHasRedeemedCommissionForCycle[msg.sender][_cycle] = true;

        // record the decrease in commission pool
        peakReferralTotalCommissionLeft = peakReferralTotalCommissionLeft.sub(
            _commission
        );

        emit PeakReferralCommissionPaid(_cycle, msg.sender, _commission);
    }
}
