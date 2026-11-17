// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PIDMath} from "../src/libraries/PIDMath.sol";

contract PIDMathTest is Test {
    uint256 internal constant WAD = 1e18;
    int256 internal constant WAD_SIGNED = 1e18;

    function test_PID_ZeroError() public pure {
        uint256 currentUtil = 0.8e18;
        uint256 targetUtil = 0.8e18;
        int256 lastError = 0;
        int256 currentIntegral = 0;
        uint256 dt = 100;
        int256 kp = 0.05e18;
        int256 ki = 0.001e18;
        int256 kd = 0.01e18;
        int256 clamp = 10e18;

        (int256 deltaRate, int256 newError, int256 newIntegral) =
            PIDMath.evaluatePID(currentUtil, targetUtil, lastError, currentIntegral, dt, kp, ki, kd, clamp);

        assertEq(deltaRate, 0);
        assertEq(newError, 0);
        assertEq(newIntegral, 0);
    }

    function test_PID_ProportionalResponse() public pure {
        uint256 currentUtil = 0.9e18; // 10% above target
        uint256 targetUtil = 0.8e18;
        int256 lastError = 0.1e18;
        int256 currentIntegral = 0;
        uint256 dt = 1;
        int256 kp = 0.5e18; // Kp = 0.5
        int256 ki = 0;
        int256 kd = 0;
        int256 clamp = 10e18;

        (int256 deltaRate, int256 newError,) =
            PIDMath.evaluatePID(currentUtil, targetUtil, lastError, currentIntegral, dt, kp, ki, kd, clamp);

        assertEq(newError, 0.1e18);
        // delta = Kp * error = 0.5 * 0.10 = 0.05e18
        assertEq(deltaRate, 0.05e18);
    }

    function test_PID_AntiWindupClamping() public pure {
        uint256 currentUtil = 1.0e18; // max utilization
        uint256 targetUtil = 0.8e18; // error = +0.20e18
        int256 lastError = 0;
        int256 currentIntegral = 5e18;
        uint256 dt = 1000; // massive time step
        int256 kp = 0;
        int256 ki = 0.1e18;
        int256 kd = 0;
        int256 clamp = 8e18; // clamp at 8.0

        (,, int256 newIntegral) =
            PIDMath.evaluatePID(currentUtil, targetUtil, lastError, currentIntegral, dt, kp, ki, kd, clamp);

        assertEq(newIntegral, clamp);
    }
}
