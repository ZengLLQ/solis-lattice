// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPIDRateController
/// @notice Interface for closed-loop Proportional-Integral-Derivative interest rate regulation.
interface IPIDRateController {
    struct PIDParameters {
        int256 kpWad; // Proportional gain
        int256 kiWad; // Integral gain
        int256 kdWad; // Derivative gain
        uint256 targetUtilWad; // Target equilibrium utilization (e.g., 0.80 * 10^18)
        uint256 baseRateWad; // Baseline floor borrow rate
        uint256 minRateWad; // Absolute minimum borrow rate
        uint256 maxRateWad; // Absolute maximum borrow rate cap
        int256 integralClampWad; // Anti-windup clamping threshold for integral term
    }

    struct PIDMetrics {
        int256 lastErrorWad;
        int256 integralAccumulatorWad;
        uint256 lastTimestamp;
        uint256 currentRateWad;
        uint256 currentUtilizationWad;
    }

    event PIDStateUpdated(uint256 newRateWad, uint256 utilizationWad, int256 errorWad, int256 integralTermWad);

    function computeBorrowRate(uint256 totalBorrows, uint256 totalReserves) external returns (uint256 newRateWad);
    function previewBorrowRate(uint256 totalBorrows, uint256 totalReserves) external view returns (uint256 rateWad);
    function getPIDParameters() external view returns (PIDParameters memory);
    function getPIDMetrics() external view returns (PIDMetrics memory);
}
