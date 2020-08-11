pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMiniMeToken.sol";
import "./tokens/minime/TokenController.sol";
import "./Utils.sol";
import "./BetokenProxyInterface.sol";
import "./peak/reward/PeakReward.sol";

/**
 * @title The storage layout of BetokenFund
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenStorage is Ownable, ReentrancyGuard {
  using SafeMath for uint256;

  enum CyclePhase { Intermission, Manage }
  enum VoteDirection { Empty, For, Against }
  enum Subchunk { Propose, Vote }

  struct Investment {
    address tokenAddress;
    uint256 cycleNumber;
    uint256 stake;
    uint256 tokenAmount;
    uint256 buyPrice; // token buy price in 18 decimals in DAI
    uint256 sellPrice; // token sell price in 18 decimals in DAI
    uint256 buyTime;
    uint256 buyCostInDAI;
    bool isSold;
  }

  // Fund parameters
  uint256 public constant COMMISSION_RATE = 15 * (10 ** 16); // The proportion of profits that gets distributed to Kairo holders every cycle.
  uint256 public constant PEAK_COMMISSION_RATE = 20 * (10 ** 16); // The proportion of profits that gets distributed to PeakDeFi referrers every cycle.
  uint256 public constant ASSET_FEE_RATE = 1 * (10 ** 15); // The proportion of fund balance that gets distributed to Kairo holders every cycle.
  uint256 public constant NEXT_PHASE_REWARD = 1 * (10 ** 18); // Amount of Kairo rewarded to the user who calls nextPhase().
  uint256 public constant MAX_BUY_KRO_PROP = 1 * (10 ** 16); // max Kairo you can buy is 1% of total supply
  uint256 public constant FALLBACK_MAX_DONATION = 100 * (10 ** 18); // If payment cap for registration is below 100 DAI, use 100 DAI instead
  uint256 public constant MIN_KRO_PRICE = 25 * (10 ** 17); // 1 KRO >= 2.5 DAI
  uint256 public constant COLLATERAL_RATIO_MODIFIER = 75 * (10 ** 16); // Modifies Compound's collateral ratio, gets 2:1 from 1.5:1 ratio
  uint256 public constant MIN_RISK_TIME = 3 days; // Mininum risk taken to get full commissions is 9 days * kairoBalance
  uint256 public constant INACTIVE_THRESHOLD = 2; // Number of inactive cycles after which a manager's Kairo balance can be burned
  uint256 public constant ROI_PUNISH_THRESHOLD = 1 * (10 ** 17); // ROI worse than 10% will see punishment in stake
  uint256 public constant ROI_BURN_THRESHOLD = 25 * (10 ** 16); // ROI worse than 25% will see their stake all burned
  uint256 public constant ROI_PUNISH_SLOPE = 6; // kroROI = -(6 * absROI - 0.5)
  uint256 public constant ROI_PUNISH_NEG_BIAS = 5 * (10 ** 17); // kroROI = -(6 * absROI - 0.5)
  uint256 public constant NEW_MANAGER_KAIRO = 100 * (10 ** 18);
  uint256 public constant MAX_NEW_MANAGERS = 25;
  // Upgrade constants
  uint256 public constant CHUNK_SIZE = 3 days;
  uint256 public constant PROPOSE_SUBCHUNK_SIZE = 1 days;
  uint256 public constant CYCLES_TILL_MATURITY = 3;
  uint256 public constant QUORUM = 10 * (10 ** 16); // 10% quorum
  uint256 public constant VOTE_SUCCESS_THRESHOLD = 75 * (10 ** 16); // Votes on upgrade candidates need >75% voting weight to pass

  // Instance variables

  // Checks if the token listing initialization has been completed.
  bool public hasInitializedTokenListings;

  // Checks if the fund has been initialized
  bool public isInitialized;

  // Address of the Kairo token contract.
  address public controlTokenAddr;

  // Address of the share token contract.
  address public shareTokenAddr;

  // Address of the BetokenProxy contract.
  address payable public proxyAddr;

  // Address of the CompoundOrderFactory contract.
  address public compoundFactoryAddr;

  // Address of the BetokenLogic contract.
  address public betokenLogic;
  address public betokenLogic2;
  address public betokenLogic3;

  // Address to which the development team funding will be sent.
  address payable public devFundingAccount;

  // Address of the previous version of BetokenFund.
  address payable public previousVersion;

  // The number of the current investment cycle.
  uint256 public cycleNumber;

  // The amount of funds held by the fund.
  uint256 public totalFundsInDAI;

  // The total funds at the beginning of the current management phase
  uint256 public totalFundsAtManagePhaseStart;

  // The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  // The proportion of Betoken Shares total supply to mint and use for funding the development team. Fixed point decimal.
  uint256 public devFundingRate;

  // Total amount of commission unclaimed by managers
  uint256 public totalCommissionLeft;

  // Stores the lengths of each cycle phase in seconds.
  uint256[2] public phaseLengths;

  uint256 public managersOnboardedThisCycle;

  // The last cycle where a user redeemed all of their remaining commission.
  mapping(address => uint256) internal _lastCommissionRedemption;

  // Marks whether a manager has redeemed their commission for a certain cycle
  mapping(address => mapping(uint256 => bool)) internal _hasRedeemedCommissionForCycle;

  // The stake-time measured risk that a manager has taken in a cycle
  mapping(address => mapping(uint256 => uint256)) internal _riskTakenInCycle;

  // In case a manager joined the fund during the current cycle, set the fallback base stake for risk threshold calculation
  mapping(address => uint256) internal _baseRiskStakeFallback;

  // List of investments of a manager in the current cycle.
  mapping(address => Investment[]) public userInvestments;

  // List of short/long orders of a manager in the current cycle.
  mapping(address => address payable[]) public userCompoundOrders;

  // Total commission to be paid for work done in a certain cycle (will be redeemed in the next cycle's Intermission)
  mapping(uint256 => uint256) internal _totalCommissionOfCycle;

  // The block number at which the Manage phase ended for a given cycle
  mapping(uint256 => uint256) internal _managePhaseEndBlock;

  // The last cycle where a manager made an investment
  mapping(address => uint256) internal _lastActiveCycle;

  // Checks if an address points to a whitelisted Kyber token.
  mapping(address => bool) public isKyberToken;

  // Checks if an address points to a whitelisted Compound token. Returns false for cDAI and other stablecoin CompoundTokens.
  mapping(address => bool) public isCompoundToken;

  // The current cycle phase.
  CyclePhase public cyclePhase;

  // Upgrade governance related variables
  bool public hasFinalizedNextVersion; // Denotes if the address of the next smart contract version has been finalized
  bool public upgradeVotingActive; // Denotes if the vote for which contract to upgrade to is active
  address payable public nextVersion; // Address of the next version of BetokenFund.
  address[5] public proposers; // Manager who proposed the upgrade candidate in a chunk
  address payable[5] public candidates; // Candidates for a chunk
  uint256[5] public forVotes; // For votes for a chunk
  uint256[5] public againstVotes; // Against votes for a chunk
  uint256 public proposersVotingWeight; // Total voting weight of previous and current proposers. This is used for excluding the voting weight of proposers.
  mapping(uint256 => mapping(address => VoteDirection[5])) public managerVotes; // Records each manager's vote
  mapping(uint256 => uint256) public upgradeSignalStrength; // Denotes the amount of Kairo that's signalling in support of beginning the upgrade process during a cycle
  mapping(uint256 => mapping(address => bool)) public upgradeSignal; // Maps manager address to whether they support initiating an upgrade

  // Contract instances
  IMiniMeToken internal cToken;
  IMiniMeToken internal sToken;
  BetokenProxyInterface internal proxy;

  // PeakDeFi
  uint256 public peakReferralTotalCommissionLeft;
  mapping(uint256 => uint256) internal _peakReferralTotalCommissionOfCycle;
  mapping(address => uint256) internal _peakReferralLastCommissionRedemption;
  mapping(address => mapping(uint256 => bool)) internal _peakReferralHasRedeemedCommissionForCycle;
  IMiniMeToken public peakReferralToken;
  PeakReward public peakReward;

  // Events

  event ChangedPhase(uint256 indexed _cycleNumber, uint256 indexed _newPhase, uint256 _timestamp, uint256 _totalFundsInDAI);

  event Deposit(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 _daiAmount, uint256 _timestamp);
  event Withdraw(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 _daiAmount, uint256 _timestamp);

  event CreatedInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _stakeInWeis, uint256 _buyPrice, uint256 _costDAIAmount, uint256 _tokenAmount);
  event SoldInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _receivedKairo, uint256 _sellPrice, uint256 _earnedDAIAmount);

  event CreatedCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _order, bool _orderType, address _tokenAddress, uint256 _stakeInWeis, uint256 _costDAIAmount);
  event SoldCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _order,  bool _orderType, address _tokenAddress, uint256 _receivedKairo, uint256 _earnedDAIAmount);
  event RepaidCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _order, uint256 _repaidDAIAmount);

  event CommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event TotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInDAI);

  event Register(address indexed _manager, uint256 _donationInDAI, uint256 _kairoReceived);
  event BurnDeadman(address indexed _manager, uint256 _kairoBurned);

  event SignaledUpgrade(uint256 indexed _cycleNumber, address indexed _sender, bool indexed _inSupport);
  event DeveloperInitiatedUpgrade(uint256 indexed _cycleNumber, address _candidate);
  event InitiatedUpgrade(uint256 indexed _cycleNumber);
  event ProposedCandidate(uint256 indexed _cycleNumber, uint256 indexed _voteID, address indexed _sender, address _candidate);
  event Voted(uint256 indexed _cycleNumber, uint256 indexed _voteID, address indexed _sender, bool _inSupport, uint256 _weight);
  event FinalizedNextVersion(uint256 indexed _cycleNumber, address _nextVersion);

  event PeakReferralCommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event PeakReferralTotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInDAI);

  /*
  Helper functions shared by both BetokenLogic & BetokenFund
  */

  /**
   * @notice The manage phase is divided into 9 3-day chunks. Determines which chunk the fund's in right now.
   * @return The index of the current chunk (starts from 0). Returns 0 if not in Manage phase.
   */
  function currentChunk() public view returns (uint) {
    if (cyclePhase != CyclePhase.Manage) {
      return 0;
    }
    return (now - startTimeOfCyclePhase) / CHUNK_SIZE;
  }

  /**
   * @notice There are two subchunks in each chunk: propose (1 day) and vote (2 days).
   *         Determines which subchunk the fund is in right now.
   * @return The Subchunk the fund is in right now
   */
  function currentSubchunk() public view returns (Subchunk _subchunk) {
    if (cyclePhase != CyclePhase.Manage) {
      return Subchunk.Vote;
    }
    uint256 timeIntoCurrChunk = (now - startTimeOfCyclePhase) % CHUNK_SIZE;
    return timeIntoCurrChunk < PROPOSE_SUBCHUNK_SIZE ? Subchunk.Propose : Subchunk.Vote;
  }

  /**
   * @notice Calculates an account's voting weight based on their Kairo balance
   *         3 cycles ago
   * @param _of the account to be queried
   * @return The account's voting weight
   */
  function getVotingWeight(address _of) public view returns (uint256 _weight) {
    if (cycleNumber <= CYCLES_TILL_MATURITY || _of == address(0)) {
      return 0;
    }
    return cToken.balanceOfAt(_of, managePhaseEndBlock(cycleNumber.sub(CYCLES_TILL_MATURITY)));
  }

  /**
   * @notice Calculates the total voting weight based on the total Kairo supply
   *         3 cycles ago. The weights of proposers are deducted.
   * @return The total voting weight right now
   */
  function getTotalVotingWeight() public view returns (uint256 _weight) {
    if (cycleNumber <= CYCLES_TILL_MATURITY) {
      return 0;
    }
    return cToken.totalSupplyAt(managePhaseEndBlock(cycleNumber.sub(CYCLES_TILL_MATURITY))).sub(proposersVotingWeight);
  }

  /**
   * @notice Calculates the current price of Kairo. The price is equal to the amount of DAI each Kairo
   *         can control, and it's kept above MIN_KRO_PRICE.
   * @return Kairo's current price
   */
  function kairoPrice() public view returns (uint256 _kairoPrice) {
    if (cToken.totalSupply() == 0) { return MIN_KRO_PRICE; }
    uint256 controlPerKairo = totalFundsInDAI.mul(10 ** 18).div(cToken.totalSupply());
    if (controlPerKairo < MIN_KRO_PRICE) {
      // keep price above minimum price
      return MIN_KRO_PRICE;
    }
    return controlPerKairo;
  }

  function lastCommissionRedemption(address _manager) public view returns (uint256) {
    if (_lastCommissionRedemption[_manager] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).lastCommissionRedemption(_manager);
    }
    return _lastCommissionRedemption[_manager];
  }

  function hasRedeemedCommissionForCycle(address _manager, uint256 _cycle) public view returns (bool) {
    if (_hasRedeemedCommissionForCycle[_manager][_cycle] == false) {
      return previousVersion == address(0) ? false : BetokenStorage(previousVersion).hasRedeemedCommissionForCycle(_manager, _cycle);
    }
    return _hasRedeemedCommissionForCycle[_manager][_cycle];
  }

  function riskTakenInCycle(address _manager, uint256 _cycle) public view returns (uint256) {
    if (_riskTakenInCycle[_manager][_cycle] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).riskTakenInCycle(_manager, _cycle);
    }
    return _riskTakenInCycle[_manager][_cycle];
  }

  function baseRiskStakeFallback(address _manager) public view returns (uint256) {
    if (_baseRiskStakeFallback[_manager] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).baseRiskStakeFallback(_manager);
    }
    return _baseRiskStakeFallback[_manager];
  }

  function totalCommissionOfCycle(uint256 _cycle) public view returns (uint256) {
    if (_totalCommissionOfCycle[_cycle] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).totalCommissionOfCycle(_cycle);
    }
    return _totalCommissionOfCycle[_cycle];
  }

  function managePhaseEndBlock(uint256 _cycle) public view returns (uint256) {
    if (_managePhaseEndBlock[_cycle] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).managePhaseEndBlock(_cycle);
    }
    return _managePhaseEndBlock[_cycle];
  }

  function lastActiveCycle(address _manager) public view returns (uint256) {
    if (_lastActiveCycle[_manager] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).lastActiveCycle(_manager);
    }
    return _lastActiveCycle[_manager];
  }

  /**
    PeakDeFi
   */
  function peakReferralLastCommissionRedemption(address _manager) public view returns (uint256) {
    if (_peakReferralLastCommissionRedemption[_manager] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).peakReferralLastCommissionRedemption(_manager);
    }
    return _peakReferralLastCommissionRedemption[_manager];
  }

  function peakReferralHasRedeemedCommissionForCycle(address _manager, uint256 _cycle) public view returns (bool) {
    if (_peakReferralHasRedeemedCommissionForCycle[_manager][_cycle] == false) {
      return previousVersion == address(0) ? false : BetokenStorage(previousVersion).peakReferralHasRedeemedCommissionForCycle(_manager, _cycle);
    }
    return _peakReferralHasRedeemedCommissionForCycle[_manager][_cycle];
  }

  function peakReferralTotalCommissionOfCycle(uint256 _cycle) public view returns (uint256) {
    if (_peakReferralTotalCommissionOfCycle[_cycle] == 0) {
      return previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).peakReferralTotalCommissionOfCycle(_cycle);
    }
    return _peakReferralTotalCommissionOfCycle[_cycle];
  }
}