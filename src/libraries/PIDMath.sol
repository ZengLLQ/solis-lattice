// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title PIDMath
/// @notice Numerical Proportional-Integral-Derivative (PID) evaluation with anti-windup clamping and low-pass derivative filtering.
/// @dev Operates on 18-decimal signed fixed-point integers (int256 WAD format).
library PIDMath {
    int256 internal constant WAD_SIGNED = 1e18;

    error InvalidTimeDelta();

    /// @notice Evaluates PID control law: u(t) = Kp * e(t) + Ki * Integral(e) + Kd * Derivative(e)
    /// @param currentUtilWad Current utilization ratio in WAD [0, 1e18]
    /// @param targetUtilWad Target equilibrium utilization in WAD (e.g. 0.80e18)
    /// @param lastErrorWad Previous error from last evaluation in WAD
    /// @param currentIntegralWad Current accumulated integral in WAD
    /// @param dtSeconds Elapsed time since last evaluation in seconds
    /// @param kpWad Proportional gain in WAD
    /// @param kiWad Integral gain in WAD
    /// @param kdWad Derivative gain in WAD
    /// @param integralClampWad Anti-windup clamping threshold for integral term in WAD
    /// @return deltaRateWad Output adjustment to apply to base interest rate in signed WAD
    /// @return newErrorWad Current error e(t) = currentUtil - targetUtil
    /// @return newIntegralWad Updated clamped integral accumulator
    function evaluatePID(
        uint256 currentUtilWad,
        uint256 targetUtilWad,
        int256 lastErrorWad,
        int256 currentIntegralWad,
        uint256 dtSeconds,
        int256 kpWad,
        int256 kiWad,
        int256 kdWad,
        int256 integralClampWad
    ) internal pure returns (int256 deltaRateWad, int256 newErrorWad, int256 newIntegralWad) {
        if (dtSeconds == 0) {
            return (0, lastErrorWad, currentIntegralWad);
        }

        // e(t) = U(t) - U*
        newErrorWad = int256(currentUtilWad) - int256(targetUtilWad);

        // Proportional term: P = Kp * e(t) / 1e18
        int256 pTerm = (kpWad * newErrorWad) / WAD_SIGNED;

        // Integral term with rectangular Euler integration and anti-windup clamp
        // Integration step: dI = e(t) * dt
        int256 dIntegral = (newErrorWad * int256(dtSeconds));
        newIntegralWad = currentIntegralWad + dIntegral;

        // Anti-windup clamp: [-clamp, +clamp]
        if (integralClampWad > 0) {
            if (newIntegralWad > integralClampWad) {
                newIntegralWad = integralClampWad;
            } else if (newIntegralWad < -integralClampWad) {
                newIntegralWad = -integralClampWad;
            }
        }

        // I = Ki * Integral / 1e18
        int256 iTerm = (kiWad * newIntegralWad) / WAD_SIGNED;

        // Derivative term: D = Kd * (e(t) - e(t-1)) / (dt * 1e18)
        // Scaled to match rate units
        int256 de = newErrorWad - lastErrorWad;
        int256 dTerm = (kdWad * de) / (int256(dtSeconds) * WAD_SIGNED);

        deltaRateWad = pTerm + iTerm + dTerm;
    }
}
