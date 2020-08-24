pragma solidity 0.5.17;

import "./lib/CloneFactory.sol";
import "./tokens/minime/MiniMeToken.sol";
import "./BetokenFund.sol";
import "./BetokenProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract BetokenFactory is CloneFactory {
    using Address for address;

    event CreateFund(address fund);
    event InitFund(address fund, address proxy);

    address public daiAddr;
    address payable public kyberAddr;
    address payable public oneInchAddr;
    address payable public betokenFund;
    address public betokenLogic;
    address public betokenLogic2;
    address public betokenLogic3;
    address public peakRewardAddr;
    address public peakStakingAddr;
    MiniMeTokenFactory public minimeFactory;

    constructor(
        address _daiAddr,
        address payable _kyberAddr,
        address payable _oneInchAddr,
        address payable _betokenFund,
        address _betokenLogic,
        address _betokenLogic2,
        address _betokenLogic3,
        address _peakRewardAddr,
        address _peakStakingAddr,
        address _minimeFactoryAddr
    ) public {
        daiAddr = _daiAddr;
        kyberAddr = _kyberAddr;
        oneInchAddr = _oneInchAddr;
        betokenFund = _betokenFund;
        betokenLogic = _betokenLogic;
        betokenLogic2 = _betokenLogic2;
        betokenLogic3 = _betokenLogic3;
        peakRewardAddr = _peakRewardAddr;
        peakStakingAddr = _peakStakingAddr;
        minimeFactory = MiniMeTokenFactory(_minimeFactoryAddr);
    }

    function createFund() external returns (BetokenFund) {
        // create fund
        BetokenFund fund = BetokenFund(createClone(betokenFund).toPayable());
        fund.initOwner();

        // give PeakReward signer rights to fund
        PeakReward peakReward = PeakReward(peakRewardAddr);
        peakReward.addSigner(address(fund));

        emit CreateFund(address(fund));

        return fund;
    }

    function initFund1(
        BetokenFund fund,
        string calldata kairoName,
        string calldata kairoSymbol,
        string calldata sharesName,
        string calldata sharesSymbol
    ) external {
        // create tokens
        MiniMeToken kairo = minimeFactory.createCloneToken(
            address(0),
            0,
            kairoName,
            18,
            kairoSymbol,
            false
        );
        MiniMeToken shares = minimeFactory.createCloneToken(
            address(0),
            0,
            sharesName,
            18,
            sharesSymbol,
            true
        );
        MiniMeToken peakReferralToken = minimeFactory.createCloneToken(
            address(0),
            0,
            "Peak Referral Token",
            18,
            "PRT",
            false
        );

        // transfer token ownerships to fund
        kairo.transferOwnership(address(fund));
        shares.transferOwnership(address(fund));
        peakReferralToken.transferOwnership(address(fund));

        fund.initInternalTokens(
            address(kairo),
            address(shares),
            address(peakReferralToken)
        );
    }

    function initFund2(
        BetokenFund fund,
        address[] calldata _kyberTokens,
        address[] calldata _compoundTokens
    ) external {
        fund.initTokenListings(_kyberTokens, _compoundTokens);
    }

    function initFund3(
        BetokenFund fund,
        uint256 _newManagerKairo,
        uint256 _maxNewManagersPerCycle,
        uint256 _kairoPrice,
        uint256 _peakManagerStakeRequired
    ) external {
        fund.initRegistration(
            _newManagerKairo,
            _maxNewManagersPerCycle,
            _kairoPrice,
            _peakManagerStakeRequired
        );
    }

    function initFund4(
        BetokenFund fund,
        address payable _devFundingAccount,
        uint256 _devFundingRate,
        uint256[2] calldata _phaseLengths,
        address _compoundFactoryAddr
    ) external {
        fund.initParams(
            _devFundingAccount,
            _phaseLengths,
            _devFundingRate,
            address(0),
            daiAddr,
            kyberAddr,
            _compoundFactoryAddr,
            betokenLogic,
            betokenLogic2,
            betokenLogic3,
            1,
            oneInchAddr,
            peakRewardAddr,
            peakStakingAddr
        );

        // deploy and set BetokenProxy
        BetokenProxy proxy = new BetokenProxy(address(fund));
        fund.setProxy(address(proxy).toPayable());

        // transfer fund ownership to msg.sender
        fund.transferOwnership(msg.sender);

        emit InitFund(address(fund), address(proxy));
    }
}
