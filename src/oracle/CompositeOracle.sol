// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICompositeOracle} from "../interfaces/ICompositeOracle.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

interface IAggregatorRound {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title CompositeOracle
/// @notice Institutional multi-source oracle aggregator with staleness checks, decimal normalization, and deviation bounds.
contract CompositeOracle is ICompositeOracle {
    LatticeAccessController public immutable accessController;

    mapping(address => OracleSource) public primaryFeeds;
    mapping(address => OracleSource) public secondaryFeeds;
    mapping(address => bool) private _circuitBreakerTripped;

    error Unauthorized();
    error ZeroAddress();
    error StalePriceFeed(address asset, uint256 updatedAt, uint256 heartbeat);
    error InvalidPrice(address asset, int256 price);
    error FeedNotConfigured(address asset);
    error CircuitBreakerActive(address asset);

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _accessController) {
        if (_accessController == address(0)) revert ZeroAddress();
        accessController = LatticeAccessController(_accessController);
    }

    function setAssetFeed(
        address asset,
        address primaryFeed,
        uint8 feedDecimals,
        uint32 heartbeatSeconds,
        uint256 maxDeviationBps
    ) external onlyAdmin {
        if (asset == address(0) || primaryFeed == address(0)) revert ZeroAddress();
        primaryFeeds[asset] = OracleSource({
            feedAddress: primaryFeed,
            feedDecimals: feedDecimals,
            heartbeatSeconds: heartbeatSeconds,
            maxDeviationBps: maxDeviationBps,
            isActive: true
        });
    }

    function setSecondaryFeed(address asset, address secondaryFeed, uint8 feedDecimals, uint32 heartbeatSeconds)
        external
        onlyAdmin
    {
        if (asset == address(0) || secondaryFeed == address(0)) revert ZeroAddress();
        secondaryFeeds[asset] = OracleSource({
            feedAddress: secondaryFeed,
            feedDecimals: feedDecimals,
            heartbeatSeconds: heartbeatSeconds,
            maxDeviationBps: 0,
            isActive: true
        });
    }

    function resetCircuitBreaker(address asset) external onlyAdmin {
        _circuitBreakerTripped[asset] = false;
    }

    function isCircuitBreakerTripped(address asset) external view override returns (bool) {
        return _circuitBreakerTripped[asset];
    }

    /// @notice Returns asset price normalized to 18-decimal USD WAD.
    function getAssetPrice(address asset) public view override returns (uint256 priceUsdWad) {
        (priceUsdWad,) = getAssetPriceWithConfidence(asset);
    }

    /// @notice Returns asset price normalized to 18-decimal USD WAD and confidence score in basis points.
    function getAssetPriceWithConfidence(address asset)
        public
        view
        override
        returns (uint256 priceUsdWad, uint256 confidenceBps)
    {
        if (_circuitBreakerTripped[asset]) revert CircuitBreakerActive(asset);

        OracleSource memory primary = primaryFeeds[asset];
        if (!primary.isActive || primary.feedAddress == address(0)) revert FeedNotConfigured(asset);

        (, int256 answer,, uint256 updatedAt,) = IAggregatorRound(primary.feedAddress).latestRoundData();
        if (answer <= 0) revert InvalidPrice(asset, answer);
        if (block.timestamp > updatedAt + primary.heartbeatSeconds) {
            revert StalePriceFeed(asset, updatedAt, primary.heartbeatSeconds);
        }

        priceUsdWad = _normalizeToWad(uint256(answer), primary.feedDecimals);
        confidenceBps = 9900; // baseline 99% confidence

        // Secondary cross-check if active
        OracleSource memory secondary = secondaryFeeds[asset];
        if (secondary.isActive && secondary.feedAddress != address(0)) {
            (, int256 secAnswer,, uint256 secUpdatedAt,) = IAggregatorRound(secondary.feedAddress).latestRoundData();
            if (secAnswer > 0 && block.timestamp <= secUpdatedAt + secondary.heartbeatSeconds) {
                uint256 secPriceWad = _normalizeToWad(uint256(secAnswer), secondary.feedDecimals);
                uint256 diffWad = priceUsdWad > secPriceWad ? priceUsdWad - secPriceWad : secPriceWad - priceUsdWad;
                uint256 deviationBps = (diffWad * 10000) / priceUsdWad;

                if (deviationBps > primary.maxDeviationBps && primary.maxDeviationBps > 0) {
                    confidenceBps = deviationBps > 5000 ? 5000 : 10000 - deviationBps;
                }
            }
        }
    }

    function _normalizeToWad(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return price;
        } else if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else {
            return price / (10 ** (decimals - 18));
        }
    }
}
