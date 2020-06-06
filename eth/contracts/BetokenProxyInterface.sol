pragma solidity 0.5.17;

interface BetokenProxyInterface {
  function betokenFundAddress() external view returns (address payable);
  function updateBetokenFundAddress() external;
}