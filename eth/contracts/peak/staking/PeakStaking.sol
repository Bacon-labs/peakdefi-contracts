pragma solidity 0.5.13;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

contract PeakStaking {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Mintable;

    ERC20Mintable public peakToken;

    constructor (address _peakToken) public {
        peakToken = ERC20Mintable(_peakToken);
    }

    function stake(uint256 stakeAmount, uint256 stakeTimeInSeconds) public {
        
    }
}