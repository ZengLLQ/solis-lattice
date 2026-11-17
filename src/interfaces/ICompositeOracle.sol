// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ICompositeOracle
/// @notice Interface for institutional multi-source oracle aggregator with volatility circuit breakers.
interface ICompositeOracle {
    struct OracleSource {
        address feedAddress;
        uint8 feedDecimals;
        uint32 heartbeatSeconds;
        uint256 maxDeviationBps; // Max allowable deviation from median in basis points
        bool isActive;
    }

    event PriceUpdated(address indexed asset, uint256 priceUsdWad, uint256 confidenceWad, uint256 timestamp);
    event CircuitBreakerTriggered(
        address indexed asset, uint256 primaryPriceWad, uint256 secondaryPriceWad, string reason
    );

    function getAssetPrice(address asset) external view returns (uint256 priceUsdWad);
    function getAssetPriceWithConfidence(address asset)
        external
        view
        returns (uint256 priceUsdWad, uint256 confidenceBps);
    function isCircuitBreakerTripped(address asset) external view returns (bool tripped);
}
