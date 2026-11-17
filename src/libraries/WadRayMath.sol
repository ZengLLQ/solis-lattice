// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title WadRayMath
/// @notice High-precision fixed-point mathematical library supporting 18-decimal (WAD) and 27-decimal (RAY) operations.
/// @dev Designed with explicit rounding modes (down vs up) to guarantee protocol solvency and zero-favor arbitrage.
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;

    uint256 internal constant WAD_TO_RAY_RATIO = 1e9;

    error MathOverflow();
    error DivisionByZero();

    /// @notice Multiplies two WAD numbers, rounding down to nearest integer.
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert MathOverflow();
        c = (a * b) / WAD;
    }

    /// @notice Multiplies two WAD numbers, rounding up (conservative for debt accruals).
    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert MathOverflow();
        c = (a * b + WAD - 1) / WAD;
    }

    /// @notice Divides two WAD numbers, rounding down.
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert DivisionByZero();
        if (a == 0) return 0;
        if (a > type(uint256).max / WAD) revert MathOverflow();
        c = (a * WAD) / b;
    }

    /// @notice Divides two WAD numbers, rounding up (conservative for protocol debt calculations).
    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert DivisionByZero();
        if (a == 0) return 0;
        if (a > type(uint256).max / WAD) revert MathOverflow();
        c = (a * WAD + b - 1) / b;
    }

    /// @notice Multiplies two RAY numbers, rounding down.
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert MathOverflow();
        c = (a * b) / RAY;
    }

    /// @notice Multiplies two RAY numbers, rounding up.
    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert MathOverflow();
        c = (a * b + RAY - 1) / RAY;
    }

    /// @notice Divides two RAY numbers, rounding down.
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert DivisionByZero();
        if (a == 0) return 0;
        if (a > type(uint256).max / RAY) revert MathOverflow();
        c = (a * RAY) / b;
    }

    /// @notice Divides two RAY numbers, rounding up.
    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert DivisionByZero();
        if (a == 0) return 0;
        if (a > type(uint256).max / RAY) revert MathOverflow();
        c = (a * RAY + b - 1) / b;
    }

    /// @notice Converts a WAD value (18 decimals) into a RAY value (27 decimals).
    function wadToRay(uint256 a) internal pure returns (uint256) {
        if (a > type(uint256).max / WAD_TO_RAY_RATIO) revert MathOverflow();
        return a * WAD_TO_RAY_RATIO;
    }

    /// @notice Converts a RAY value (27 decimals) into a WAD value (18 decimals), rounding down.
    function rayToWad(uint256 a) internal pure returns (uint256) {
        return a / WAD_TO_RAY_RATIO;
    }

    /// @notice Converts a RAY value (27 decimals) into a WAD value (18 decimals), rounding up.
    function rayToWadUp(uint256 a) internal pure returns (uint256) {
        if (a == 0) return 0;
        return (a + WAD_TO_RAY_RATIO - 1) / WAD_TO_RAY_RATIO;
    }

    /// @notice Computes (x^n) in RAY fixed point using binary exponentiation (exponentiation by squaring).
    function rayPow(uint256 xRay, uint256 n) internal pure returns (uint256 zRay) {
        zRay = n % 2 != 0 ? xRay : RAY;
        for (n /= 2; n != 0; n /= 2) {
            xRay = rayMul(xRay, xRay);
            if (n % 2 != 0) {
                zRay = rayMul(zRay, xRay);
            }
        }
    }
}
