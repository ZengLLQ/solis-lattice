// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WadRayMath} from "./WadRayMath.sol";

/// @title ExpCompoundMath
/// @notice Computes continuous and discrete compounding factors via high-accuracy Taylor series expansion.
/// @dev Implements 6th-order Taylor polynomial for exp(r * dt) in RAY precision (1e27).
library ExpCompoundMath {
    using WadRayMath for uint256;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant SECONDS_PER_YEAR = 31536000; // 365 days

    error InputExponentTooLarge();

    /// @notice Computes exp(r * dt) in RAY precision using a 6th-order Taylor polynomial:
    /// e^x = 1 + x + x^2/2! + x^3/3! + x^4/4! + x^5/5! + x^6/6!
    /// @param annualRateWad Annual interest rate in WAD (1e18 = 100% APR)
    /// @param timeDeltaSeconds Elapsed time in seconds
    /// @return compoundFactorRay Compound factor in RAY (1e27 = 1.0x)
    function continuousCompoundFactorRay(uint256 annualRateWad, uint256 timeDeltaSeconds)
        internal
        pure
        returns (uint256 compoundFactorRay)
    {
        if (annualRateWad == 0 || timeDeltaSeconds == 0) {
            return RAY;
        }

        // x in RAY = (annualRateWad * 1e9 * timeDeltaSeconds) / SECONDS_PER_YEAR
        uint256 xRay = (annualRateWad * WadRayMath.WAD_TO_RAY_RATIO * timeDeltaSeconds) / SECONDS_PER_YEAR;

        // Ensure x is within reasonable Taylor convergence window (< 4.0 in RAY)
        if (xRay > 4 * RAY) revert InputExponentTooLarge();

        // Term 0 = 1.0 in RAY
        uint256 sumRay = RAY;

        // Term 1 = x
        sumRay += xRay;

        // Term 2 = x^2 / 2
        uint256 term2 = (xRay.rayMul(xRay)) / 2;
        sumRay += term2;

        // Term 3 = x^3 / 6
        uint256 term3 = (term2.rayMul(xRay)) / 3;
        sumRay += term3;

        // Term 4 = x^4 / 24
        uint256 term4 = (term3.rayMul(xRay)) / 4;
        sumRay += term4;

        // Term 5 = x^5 / 120
        uint256 term5 = (term4.rayMul(xRay)) / 5;
        sumRay += term5;

        // Term 6 = x^6 / 720
        uint256 term6 = (term5.rayMul(xRay)) / 6;
        sumRay += term6;

        return sumRay;
    }

    /// @notice Discrete compounding: (1 + r / SECONDS_PER_YEAR)^dt
    /// Linear approximation for micro-time intervals: 1 + (r * dt) / SECONDS_PER_YEAR
    function linearCompoundFactorRay(uint256 annualRateWad, uint256 timeDeltaSeconds) internal pure returns (uint256) {
        if (annualRateWad == 0 || timeDeltaSeconds == 0) {
            return RAY;
        }
        uint256 ratePerSecondRay = (annualRateWad * WadRayMath.WAD_TO_RAY_RATIO) / SECONDS_PER_YEAR;
        return RAY + (ratePerSecondRay * timeDeltaSeconds);
    }
}
