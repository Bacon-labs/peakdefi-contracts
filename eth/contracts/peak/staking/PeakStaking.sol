pragma solidity 0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "../reward/PeakReward.sol";
import "../PeakToken.sol";


contract PeakStaking {
    using SafeMath for uint256;
    using SafeERC20 for PeakToken;

    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant PEAK_PRECISION = 10**8;
    uint256 internal constant INTEREST_SLOPE = 2 * (10**8); // Interest rate factor drops to 0 at 5B mintedPeakTokens
    uint256 internal constant BIGGER_BONUS_DIVISOR = 10**15; // biggerBonus = stakeAmount / (10 million peak)
    uint256 internal constant MAX_BIGGER_BONUS = 10**17; // biggerBonus <= 10%
    uint256 internal constant YEAR_IN_DAYS = 365;
    uint256 internal constant DAY_IN_SECONDS = 86400;
    uint256 internal constant COMMISSION_RATE = 20 * (10**16); // 20%
    uint256 internal constant REFERRAL_STAKER_BONUS = 3 * (10**16); // 3%

    struct Stake {
        address staker;
        uint256 stakeAmount;
        uint256 interestAmount;
        uint256 withdrawnInterestAmount;
        uint256 stakeTimestamp;
        uint256 stakeTimeInDays;
        bool active;
    }
    Stake[] public stakeList;
    mapping(address => uint256) public userStakeAmount;
    uint256 public mintedPeakTokens;
    bool public initialized;

    PeakToken public peakToken;
    PeakReward public peakReward;

    constructor(address _peakToken) public {
        peakToken = PeakToken(_peakToken);
    }

    function init(address _peakReward) public {
        require(!initialized, "PeakStaking: Already initialized");
        initialized = true;

        peakReward = PeakReward(_peakReward);
    }

    function stake(
        uint256 stakeAmount,
        uint256 stakeTimeInDays,
        address referrer
    ) public returns (uint256 stakeIdx) {
        // record stake
        uint256 interestAmount = getInterestAmount(
            stakeAmount,
            stakeTimeInDays
        );
        stakeIdx = stakeList.length;
        stakeList.push(
            Stake({
                staker: msg.sender,
                stakeAmount: stakeAmount,
                interestAmount: interestAmount,
                withdrawnInterestAmount: 0,
                stakeTimestamp: now,
                stakeTimeInDays: stakeTimeInDays,
                active: true
            })
        );
        mintedPeakTokens = mintedPeakTokens.add(interestAmount);
        userStakeAmount[msg.sender] = userStakeAmount[msg.sender].add(
            stakeAmount
        );

        // transfer PEAK from msg.sender
        peakToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // mint PEAK interest
        peakToken.mint(address(this), interestAmount);

        // handle referral
        if (peakReward.canRefer(msg.sender, referrer)) {
            peakReward.refer(msg.sender, referrer);
        }
        address actualReferrer = peakReward.referrerOf(msg.sender);
        if (actualReferrer != address(0)) {
            // pay referral bonus to referrer
            uint256 rawCommission = stakeAmount.mul(COMMISSION_RATE).div(
                PRECISION
            );
            peakToken.mint(address(this), rawCommission);
            peakToken.safeApprove(address(peakReward), rawCommission);
            uint256 leftoverAmount = peakReward.payCommission(
                actualReferrer,
                address(peakToken),
                rawCommission,
                true
            );
            peakToken.burn(leftoverAmount);

            // pay referral bonus to staker
            uint256 referralStakerBonus = rawCommission
                .sub(leftoverAmount)
                .mul(REFERRAL_STAKER_BONUS)
                .div(PRECISION);
            peakToken.mint(msg.sender, referralStakerBonus);

            // increment referrer CV
            peakReward.incrementCareerValueInPeak(actualReferrer, stakeAmount);
        }
    }

    function withdraw(uint256 stakeIdx) public {
        Stake storage stakeObj = stakeList[stakeIdx];
        require(stakeObj.staker == msg.sender, "PeakStaking: Sender not staker");
        require(stakeObj.active, "PeakStaking: Not active");

        // calculate amount that can be withdrawn
        uint256 stakeTimeInSeconds = stakeObj.stakeTimeInDays.mul(DAY_IN_SECONDS);
        uint256 withdrawAmount;
        if (now >= stakeObj.stakeTimestamp.add(stakeTimeInSeconds)) {
            // matured, withdraw all
            withdrawAmount = stakeObj.stakeAmount.add(stakeObj.interestAmount).sub(stakeObj.withdrawnInterestAmount);
            stakeObj.active = false;
            stakeObj.withdrawnInterestAmount = stakeObj.interestAmount;
        } else {
            // not mature, partial withdraw
            withdrawAmount = stakeObj
                .interestAmount
                .mul(uint256(now).sub(stakeObj.stakeTimestamp))
                .div(stakeTimeInSeconds)
                .sub(stakeObj.withdrawnInterestAmount);

            // record withdrawal
            stakeObj.withdrawnInterestAmount = stakeObj.withdrawnInterestAmount.add(
                withdrawAmount
            );
        }

        // withdraw interest to sender
        peakToken.safeTransfer(msg.sender, withdrawAmount);
    }

    function getInterestAmount(uint256 stakeAmount, uint256 stakeTimeInDays)
        public
        view
        returns (uint256)
    {
        uint256 irFactor = _interestRateFactor(mintedPeakTokens);
        uint256 biggerBonus = stakeAmount.mul(PRECISION).div(
            BIGGER_BONUS_DIVISOR
        );
        if (biggerBonus > MAX_BIGGER_BONUS) {
            biggerBonus = MAX_BIGGER_BONUS;
        }
        uint256 longerBonus = _longerBonus(stakeTimeInDays);
        uint256 interestRate = biggerBonus.add(longerBonus).mul(irFactor).div(
            PRECISION
        );
        uint256 interestAmount = stakeAmount
            .mul(interestRate)
            .mul(stakeTimeInDays)
            .div(YEAR_IN_DAYS.mul(PRECISION));
        return interestAmount;
    }

    function _longerBonus(uint256 stakeTimeInDays)
        internal
        pure
        returns (uint256)
    {
        if (stakeTimeInDays < 10) {
            return 0;
        } else if (stakeTimeInDays < 100) {
            return PRECISION.mul(9).div(100);
        } else if (stakeTimeInDays < 150) {
            uint256 minBonus = PRECISION.mul(20).div(100);
            uint256 maxBonus = PRECISION.mul(30).div(100);
            uint256 minDay = 100;
            uint256 maxDay = 150;
            return
                minBonus.add(
                    maxBonus.sub(minBonus).mul(stakeTimeInDays.sub(minDay)).div(
                        maxDay.sub(minDay)
                    )
                );
        } else if (stakeTimeInDays < 250) {
            uint256 minBonus = PRECISION.mul(30).div(100);
            uint256 maxBonus = PRECISION.mul(40).div(100);
            uint256 minDay = 150;
            uint256 maxDay = 250;
            return
                minBonus.add(
                    maxBonus.sub(minBonus).mul(stakeTimeInDays.sub(minDay)).div(
                        maxDay.sub(minDay)
                    )
                );
        } else if (stakeTimeInDays < 500) {
            uint256 minBonus = PRECISION.mul(40).div(100);
            uint256 maxBonus = PRECISION.mul(50).div(100);
            uint256 minDay = 250;
            uint256 maxDay = 500;
            return
                minBonus.add(
                    maxBonus.sub(minBonus).mul(stakeTimeInDays.sub(minDay)).div(
                        maxDay.sub(minDay)
                    )
                );
        } else if (stakeTimeInDays < 1000) {
            uint256 minBonus = PRECISION.mul(50).div(100);
            uint256 maxBonus = PRECISION.mul(70).div(100);
            uint256 minDay = 500;
            uint256 maxDay = 1000;
            return
                minBonus.add(
                    maxBonus.sub(minBonus).mul(stakeTimeInDays.sub(minDay)).div(
                        maxDay.sub(minDay)
                    )
                );
        } else {
            return PRECISION.mul(90).div(100);
        }
    }

    function _interestRateFactor(uint256 _mintedPeakTokens)
        internal
        pure
        returns (uint256)
    {
        return
            PRECISION.sub(
                INTEREST_SLOPE.mul(_mintedPeakTokens).div(PEAK_PRECISION)
            );
    }
}
