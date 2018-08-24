pragma solidity ^0.4.24;

import "./BetokenFund.sol";

contract BetokenFundProxy is Ownable {
    address public betokenFundAddress;
    BetokenFund internal betokenFund;

    constructor(address _fundAddr) public {
        betokenFundAddress = _fundAddr;
        betokenFund = BetokenFund(_fundAddr);
    }

    function updateBetokenFundAddress() public onlyOwner {
        address nextVersion = betokenFund.nextVersion();
        require(nextVersion != address(0));
        betokenFundAddress = nextVersion;
        betokenFund = BetokenFund(nextVersion);
        owner = nextVersion;
    }
}