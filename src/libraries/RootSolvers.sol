// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {WadRayMath} from "./WadRayMath.sol";

/// @title RootSolvers
/// @notice Numerical root-finding algorithms (Newton-Raphson and Halley's method) for non-linear yield equilibrium solving.
/// @dev Solves polynomial equations of the form f(x) = a*x^3 + b*x^2 + c*x + d = 0 in 18-decimal fixed-point precision.
library RootSolvers {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant TOLERANCE_WAD = 1e12; // 10^-6 precision
    uint256 internal constant MAX_ITERATIONS = 32;

    error SolverDidNotConverge();
    error ZeroDerivative();

    /// @notice Solves for root of f(x) = a*x^3 + b*x^2 + c*x + d using Newton-Raphson iteration.
    /// @dev All coefficients and initial guess are in WAD format.
    function solveCubicNewton(int256 a, int256 b, int256 c, int256 d, int256 initialGuess)
        internal
        pure
        returns (int256 root)
    {
        int256 x = initialGuess;

        for (uint256 i = 0; i < MAX_ITERATIONS; ++i) {
            // f(x) = a*x^3 + b*x^2 + c*x + d
            int256 x2 = (x * x) / int256(WAD);
            int256 x3 = (x2 * x) / int256(WAD);

            int256 fx = (a * x3) / int256(WAD) + (b * x2) / int256(WAD) + (c * x) / int256(WAD) + d;

            // Check tolerance: |f(x)| <= TOLERANCE
            if (fx >= -int256(TOLERANCE_WAD) && fx <= int256(TOLERANCE_WAD)) {
                return x;
            }

            // f'(x) = 3*a*x^2 + 2*b*x + c
            int256 fpx = (3 * a * x2) / int256(WAD) + (2 * b * x) / int256(WAD) + c;
            if (fpx == 0) revert ZeroDerivative();

            // x_{n+1} = x_n - f(x) / f'(x)
            int256 dx = (fx * int256(WAD)) / fpx;
            x = x - dx;

            if (dx >= -int256(TOLERANCE_WAD) && dx <= int256(TOLERANCE_WAD)) {
                return x;
            }
        }

        revert SolverDidNotConverge();
    }

    /// @notice Solves for root using Halley's third-order iterative method:
    /// x_{n+1} = x_n - [2 * f(x) * f'(x)] / [2 * (f'(x))^2 - f(x) * f''(x)]
    function solveCubicHalley(int256 a, int256 b, int256 c, int256 d, int256 initialGuess)
        internal
        pure
        returns (int256 root)
    {
        int256 x = initialGuess;

        for (uint256 i = 0; i < MAX_ITERATIONS; ++i) {
            int256 x2 = (x * x) / int256(WAD);
            int256 x3 = (x2 * x) / int256(WAD);

            int256 fx = (a * x3) / int256(WAD) + (b * x2) / int256(WAD) + (c * x) / int256(WAD) + d;

            if (fx >= -int256(TOLERANCE_WAD) && fx <= int256(TOLERANCE_WAD)) {
                return x;
            }

            // f'(x) = 3*a*x^2 + 2*b*x + c
            int256 fpx = (3 * a * x2) / int256(WAD) + (2 * b * x) / int256(WAD) + c;
            // f''(x) = 6*a*x + 2*b
            int256 fppx = (6 * a * x) / int256(WAD) + 2 * b;

            int256 denominator = (2 * fpx * fpx) / int256(WAD) - (fx * fppx) / int256(WAD);
            if (denominator == 0) revert ZeroDerivative();

            int256 numerator = (2 * fx * fpx) / int256(WAD);
            int256 dx = (numerator * int256(WAD)) / denominator;

            x = x - dx;

            if (dx >= -int256(TOLERANCE_WAD) && dx <= int256(TOLERANCE_WAD)) {
                return x;
            }
        }

        revert SolverDidNotConverge();
    }
}
