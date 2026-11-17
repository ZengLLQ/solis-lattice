// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title MockPriceFeed
/// @notice Programmable mock price feed for unit testing and stress simulation.
contract MockPriceFeed {
    int256 private _price;
    uint8 public immutable decimals;
    uint256 private _updatedAt;

    constructor(int256 initialPrice, uint8 _decimals) {
        _price = initialPrice;
        decimals = _decimals;
        _updatedAt = block.timestamp;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _updatedAt = block.timestamp;
    }

    function setPriceAndTimestamp(int256 newPrice, uint256 timestamp) external {
        _price = newPrice;
        _updatedAt = timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }
}
