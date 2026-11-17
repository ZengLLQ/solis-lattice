// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

/// @title VolatilityCircuitBreaker
/// @notice Automated market volatility circuit breaker detecting rapid price swings and anomalous spreads.
contract VolatilityCircuitBreaker {
    LatticeAccessController public immutable accessController;

    struct PriceSample {
        uint256 priceWad;
        uint256 timestamp;
    }

    uint256 public constant MAX_VOLATILITY_WINDOW = 1 hours;
    uint256 public maxAllowedSwingBps = 1500; // 15% max swing within window

    mapping(address => PriceSample) public lastSamples;
    mapping(address => bool) public isTripped;

    event BreakerTripped(address indexed asset, uint256 oldPrice, uint256 newPrice, uint256 swingBps);
    event BreakerReset(address indexed asset, address indexed admin);
    event MaxSwingUpdated(uint256 newSwingBps);

    error Unauthorized();
    error CircuitBreakerTrippedError(address asset);

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _accessController) {
        require(_accessController != address(0), "Zero address");
        accessController = LatticeAccessController(_accessController);
    }

    /// @notice Validates incoming price against previous sample and updates state.
    /// @dev Sets isTripped to true and returns false if price swing exceeds threshold.
    function validateAndRecordPrice(address asset, uint256 newPriceWad) external returns (bool valid) {
        if (isTripped[asset]) return false;

        PriceSample memory prev = lastSamples[asset];
        if (prev.priceWad != 0 && block.timestamp <= prev.timestamp + MAX_VOLATILITY_WINDOW) {
            uint256 delta = newPriceWad > prev.priceWad ? newPriceWad - prev.priceWad : prev.priceWad - newPriceWad;
            uint256 swingBps = (delta * 10000) / prev.priceWad;

            if (swingBps > maxAllowedSwingBps) {
                isTripped[asset] = true;
                emit BreakerTripped(asset, prev.priceWad, newPriceWad, swingBps);
                return false;
            }
        }

        lastSamples[asset] = PriceSample({priceWad: newPriceWad, timestamp: block.timestamp});

        return true;
    }

    function resetBreaker(address asset) external onlyAdmin {
        isTripped[asset] = false;
        delete lastSamples[asset];
        emit BreakerReset(asset, msg.sender);
    }

    function setMaxAllowedSwingBps(uint256 newSwingBps) external onlyAdmin {
        require(newSwingBps >= 100 && newSwingBps <= 5000, "Invalid swing bounds");
        maxAllowedSwingBps = newSwingBps;
        emit MaxSwingUpdated(newSwingBps);
    }
}
