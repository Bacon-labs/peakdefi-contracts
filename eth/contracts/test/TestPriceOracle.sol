pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract TestPriceOracle is PriceOracle, Ownable {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;
  address public CETH_ADDR;

  mapping(address => uint256) public priceInUSDC;

  constructor(address[] memory _tokens, uint256[] memory _pricesInUSDC, address _cETH) public {
    for (uint256 i = 0; i < _tokens.length; i = i.add(1)) {
      priceInUSDC[_tokens[i]] = _pricesInUSDC[i];
    }
    CETH_ADDR = _cETH;
  }

  function setTokenPrice(address _token, uint256 _priceInUSDC) public onlyOwner {
    priceInUSDC[_token] = _priceInUSDC;
  }

  function getUnderlyingPrice(address cToken) external view returns (uint) {
    return priceInUSDC[cToken].mul(PRECISION).div(priceInUSDC[CETH_ADDR]);
  }
}