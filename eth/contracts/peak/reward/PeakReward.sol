pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/roles/SignerRole.sol";
import "../staking/PeakStaking.sol";


contract PeakReward is SignerRole {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Register(address user, address referrer);
    event RankChange(address user, uint256 oldRank, uint256 newRank);
    event PayCommission(address referrer, address receipient, address token, uint256 amount, uint8 level);
    event ChangedCareerValue(address user, uint256 changeAmount, bool positive);

    modifier regUser(address user) {
        if (!isUser[user]) {
            isUser[user] = true;
            numUsersWithRank[0] = numUsersWithRank[0].add(1);
            emit Register(user, address(0));
        }
        _;
    }

    modifier checkRankChange(address user) {
        uint256 beforeRank = rankOf(user);
        _;
        uint256 afterRank = rankOf(user);
        if (beforeRank != afterRank) {
            numUsersWithRank[beforeRank] = numUsersWithRank[beforeRank].sub(1);
            numUsersWithRank[afterRank] = numUsersWithRank[afterRank].add(1);
            emit RankChange(user, beforeRank, afterRank);
        }
    }

    uint256 internal constant COMMISSION_RATE = 20 * (10**16); // 20%
    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant PEAK_PRECISION = 10**8;
    uint8 internal constant COMMISSION_LEVELS = 8;

    mapping(address => address) public referrerOf;
    mapping(address => bool) public isUser;
    mapping(address => uint256) public careerValue;
    mapping(uint256 => uint256) public numUsersWithRank;

    uint256[] public commissionPercentages;
    uint256[] public commissionStakeRequirements;
    uint256[] public rankRewardPercentages;

    address public marketPeakWallet;
    PeakStaking public peakStaking;

    constructor(address _marketPeakWallet, address _peakStaking) public {
        // initialize commission percentages for each level
        commissionPercentages.push(10 * (10**16)); // 10%
        commissionPercentages.push(4 * (10**16)); // 4%
        commissionPercentages.push(2 * (10**16)); // 2%
        commissionPercentages.push(1 * (10**16)); // 1%
        commissionPercentages.push(1 * (10**16)); // 1%
        commissionPercentages.push(1 * (10**16)); // 1%
        commissionPercentages.push(5 * (10**15)); // 0.5%
        commissionPercentages.push(5 * (10**15)); // 0.5%

        // initialize commission stake requirements for each level
        commissionStakeRequirements.push(0);
        commissionStakeRequirements.push(PEAK_PRECISION.mul(2000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(4000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(6000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(7000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(8000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(9000));
        commissionStakeRequirements.push(PEAK_PRECISION.mul(10000));

        // initialize rank reward percentages for each rank
        rankRewardPercentages.push(0); // 0%
        rankRewardPercentages.push(1 * (10**16)); // 1%
        rankRewardPercentages.push(2 * (10**16)); // 2%
        rankRewardPercentages.push(3 * (10**16)); // 3%
        rankRewardPercentages.push(4 * (10**16)); // 4%
        rankRewardPercentages.push(5 * (10**16)); // 5%
        rankRewardPercentages.push(6 * (10**16)); // 6%
        rankRewardPercentages.push(7 * (10**16)); // 7%
        rankRewardPercentages.push(12 * (10**16)); // 12%
        rankRewardPercentages.push(20 * (10**16)); // 20%
        rankRewardPercentages.push(40 * (10**16)); // 40%

        marketPeakWallet = _marketPeakWallet;
        peakStaking = PeakStaking(_peakStaking);
    }

    /**
        @notice Registers a referral relationship
        @param user The user who is being referred
        @param referrer The referrer of `user`
     */
    function refer(address user, address referrer) public onlySigner {
        require(!isUser[user], "PeakReward: referred is already a user");
        require(user != referrer, "PeakReward: can't refer self");
        require(
            user != address(0) && referrer != address(0),
            "PeakReward: 0 address"
        );

        isUser[user] = true;
        isUser[referrer] = true;

        referrerOf[user] = referrer;

        numUsersWithRank[0] = numUsersWithRank[0].add(1);

        emit Register(user, referrer);
    }

    function canRefer(address user, address referrer) public view returns (bool) {
        return
            !isUser[user] &&
            user != referrer &&
            user != address(0) &&
            referrer != address(0);
    }

    /**
        @notice Distributes commissions to a referrer and their referrers
        @param referrer The referrer who will receive commission
        @param commissionToken The ERC20 token that the commission is paid in
        @param rawCommission The raw commission that will be distributed amongst referrers
        @param returnLeftovers If true, leftover commission is returned to the sender. If false, leftovers will be paid to MarketPeak.
     */
    function payCommission(
        address referrer,
        address commissionToken,
        uint256 rawCommission,
        bool returnLeftovers
    ) public regUser(referrer) onlySigner returns (uint256 leftoverAmount) {
        // transfer the raw commission from `msg.sender`
        IERC20 token = IERC20(commissionToken);
        token.safeTransferFrom(msg.sender, address(this), rawCommission);

        // payout commissions to referrers of different levels
        address ptr = referrer;
        uint256 commissionLeft = rawCommission;
        uint8 i = 0;
        while (ptr != address(0) && i < COMMISSION_LEVELS) {
            if (_peakStakeOf(ptr) >= commissionStakeRequirements[i]) {
                // referrer has enough stake, give commission
                uint256 com = rawCommission.mul(commissionPercentages[i]).div(
                    COMMISSION_RATE
                );
                if (com > commissionLeft) {
                    com = commissionLeft;
                }
                token.safeTransfer(ptr, com);
                commissionLeft = commissionLeft.sub(com);
                emit PayCommission(referrer, ptr, commissionToken, com, i);
            }

            ptr = referrerOf[ptr];
            i += 1;
        }

        // handle leftovers
        if (returnLeftovers) {
            // return leftovers to `msg.sender`
            token.safeTransfer(msg.sender, commissionLeft);
            return commissionLeft;
        } else {
            // give leftovers to MarketPeak wallet
            token.safeTransfer(marketPeakWallet, commissionLeft);
            return 0;
        }
    }

    /**
        @notice Increments a user's career value
        @param user The user
        @param incCV The CV increase amount, in Dai
     */
    function incrementCareerValueInDai(address user, uint256 incCV)
        public
        regUser(user)
        onlySigner
    {
        careerValue[user] = careerValue[user].add(incCV);
        emit ChangedCareerValue(user, incCV, true);
    }

    /**
        @notice Decrements a user's career value
        @param user The user
        @param decCV The CV decrease amount, in Dai
     */
    function decrementCareerValueInDai(address user, uint256 decCV)
        public
        regUser(user)
        onlySigner
    {
        if (careerValue[user] >= decCV) {
            careerValue[user] = careerValue[user].sub(decCV);
            emit ChangedCareerValue(user, decCV, false);
        } else {
            emit ChangedCareerValue(user, careerValue[user], false);
            careerValue[user] = 0;
        }
    }

    /**
        @notice Increments a user's career value
        @param user The user
        @param incCVInPeak The CV increase amount, in PEAK tokens
     */
    function incrementCareerValueInPeak(address user, uint256 incCVInPeak)
        public
        regUser(user)
        onlySigner
    {
        uint256 peakPriceInDai = _getPeakPriceInDai();
        uint256 incCVInDai = incCVInPeak.mul(peakPriceInDai).div(
            PEAK_PRECISION
        );
        careerValue[user] = careerValue[user].add(incCVInDai);
        emit ChangedCareerValue(user, incCVInDai, true);
    }

    /**
        @notice Returns a user's rank in the PeakDeFi system
        @param user The user whose rank will be queried
     */
    function rankOf(address user) public view returns (uint256) {
        uint256 cv = careerValue[user];
        if (cv < PRECISION.mul(5000)) {
            return 0;
        } else if (cv < PRECISION.mul(10000)) {
            return 1;
        } else if (cv < PRECISION.mul(25000)) {
            return 2;
        } else if (cv < PRECISION.mul(50000)) {
            return 3;
        } else if (cv < PRECISION.mul(100000)) {
            return 4;
        } else if (cv < PRECISION.mul(250000)) {
            return 5;
        } else if (cv < PRECISION.mul(500000)) {
            return 6;
        } else if (cv < PRECISION.mul(1000000)) {
            return 7;
        } else if (cv < PRECISION.mul(3000000)) {
            return 8;
        } else if (cv < PRECISION.mul(10000000)) {
            return 9;
        } else {
            return 10;
        }
    }

    /**
        @notice Returns a user's current staked PEAK amount, scaled by `PEAK_PRECISION`.
        @param user The user whose stake will be queried
     */
    function _peakStakeOf(address user) internal view returns (uint256) {
        return peakStaking.userStakeAmount(user);
    }

    /**
        @notice Returns the price of PEAK token in Dai, scaled by `PRECISION`.
     */
    function _getPeakPriceInDai() internal view returns (uint256) {
        // TODO: connect with Uniswap PEAK market
        return PRECISION.mul(12).div(100);
    }
}
