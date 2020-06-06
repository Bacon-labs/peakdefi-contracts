pragma solidity 0.5.17;

// Compound finance's price oracle
interface PriceOracle {
  function getUnderlyingPrice(address cToken) external view returns (uint);
}