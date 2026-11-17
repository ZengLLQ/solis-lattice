// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ExpCompoundMath} from "../src/libraries/ExpCompoundMath.sol";

contract ExpCompoundMathTest is Test {
    uint256 internal constant RAY = 1e27;
    uint256 internal constant WAD = 1e18;

    function test_ContinuousCompound_ZeroRateOrTime() public pure {
        assertEq(ExpCompoundMath.continuousCompoundFactorRay(0, 1000), RAY);
        assertEq(ExpCompoundMath.continuousCompoundFactorRay(0.05e18, 0), RAY);
    }

    function test_ContinuousCompound_SmallTimeStep() public pure {
        uint256 rateWad = 0.05e18; // 5% APR
        uint256 dt = 1; // 1 second
        uint256 factor = ExpCompoundMath.continuousCompoundFactorRay(rateWad, dt);

        assertGt(factor, RAY);
        assertLt(factor, RAY + 1e20); // very small increase per second
    }

    function test_ContinuousCompound_OneYear() public pure {
        uint256 rateWad = 0.1e18; // 10% APR
        uint256 dt = 31536000; // 1 year
        uint256 factor = ExpCompoundMath.continuousCompoundFactorRay(rateWad, dt);

        // e^0.10 ~ 1.105170918...
        // in RAY: 1.1051709... * 1e27
        uint256 expectedMin = 1.1051e27;
        uint256 expectedMax = 1.1052e27;

        assertGt(factor, expectedMin);
        assertLt(factor, expectedMax);
    }

    function test_LinearCompound_Consistency() public pure {
        uint256 rateWad = 0.08e18;
        uint256 dt = 3600;
        uint256 factorLinear = ExpCompoundMath.linearCompoundFactorRay(rateWad, dt);
        uint256 factorContinuous = ExpCompoundMath.continuousCompoundFactorRay(rateWad, dt);

        assertGt(factorContinuous, RAY);
        assertGt(factorLinear, RAY);
        // For 1 hour at 8%, difference between linear and continuous is negligible (< 10^-10 in RAY)
        assertApproxEqAbs(factorLinear, factorContinuous, 1e17);
    }
}
