// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RootSolvers} from "../src/libraries/RootSolvers.sol";

contract RootSolversTest is Test {
    uint256 internal constant WAD = 1e18;

    function test_NewtonSolver_LinearEquation() public pure {
        // f(x) = 2x - 4 = 0 => root = 2
        // a=0, b=0, c=2, d=-4
        int256 a = 0;
        int256 b = 0;
        int256 c = 2 * int256(WAD);
        int256 d = -4 * int256(WAD);
        int256 guess = 1 * int256(WAD);

        int256 root = RootSolvers.solveCubicNewton(a, b, c, d, guess);
        assertApproxEqAbs(root, 2 * int256(WAD), 1e12);
    }

    function test_NewtonSolver_CubicEquation() public pure {
        // f(x) = x^3 - 8 = 0 => root = 2
        // a=1, b=0, c=0, d=-8
        int256 a = 1 * int256(WAD);
        int256 b = 0;
        int256 c = 0;
        int256 d = -8 * int256(WAD);
        int256 guess = 1.5e18;

        int256 root = RootSolvers.solveCubicNewton(a, b, c, d, guess);
        assertApproxEqAbs(root, 2 * int256(WAD), 1e12);
    }

    function test_HalleySolver_CubicEquation() public pure {
        // f(x) = x^3 - 27 = 0 => root = 3
        int256 a = 1 * int256(WAD);
        int256 b = 0;
        int256 c = 0;
        int256 d = -27 * int256(WAD);
        int256 guess = 2 * int256(WAD);

        int256 root = RootSolvers.solveCubicHalley(a, b, c, d, guess);
        assertApproxEqAbs(root, 3 * int256(WAD), 1e12);
    }
}
