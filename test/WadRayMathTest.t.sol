// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";

contract WadRayMathTest is Test {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function test_WadMul_Standard() public pure {
        uint256 a = 2 * WAD;
        uint256 b = 3 * WAD;
        uint256 res = a.wadMul(b);
        assertEq(res, 6 * WAD);
    }

    function test_WadMul_Rounding() public pure {
        uint256 a = 1;
        uint256 b = 1;
        uint256 resDown = a.wadMul(b);
        uint256 resUp = a.wadMulUp(b);
        assertEq(resDown, 0);
        assertEq(resUp, 1);
    }

    function test_WadDiv_Standard() public pure {
        uint256 a = 10 * WAD;
        uint256 b = 2 * WAD;
        uint256 res = a.wadDiv(b);
        assertEq(res, 5 * WAD);
    }

    function test_WadDiv_Rounding() public pure {
        uint256 a = 1;
        uint256 b = 2;
        uint256 resDown = a.wadDiv(b);
        uint256 resUp = a.wadDivUp(b);
        assertEq(resDown, 0.5e18);
        assertEq(resUp, 0.5e18);
    }

    function test_RayMul_Standard() public pure {
        uint256 a = 2 * RAY;
        uint256 b = 4 * RAY;
        uint256 res = a.rayMul(b);
        assertEq(res, 8 * RAY);
    }

    function test_RayDiv_Standard() public pure {
        uint256 a = 9 * RAY;
        uint256 b = 3 * RAY;
        uint256 res = a.rayDiv(b);
        assertEq(res, 3 * RAY);
    }

    function test_Conversions() public pure {
        uint256 wadVal = 5 * WAD;
        uint256 rayVal = wadVal.wadToRay();
        assertEq(rayVal, 5 * RAY);

        uint256 backWad = rayVal.rayToWad();
        assertEq(backWad, wadVal);

        uint256 backWadUp = rayVal.rayToWadUp();
        assertEq(backWadUp, wadVal);
    }

    function test_RayPow() public pure {
        uint256 xRay = 1.05e27; // 1.05
        uint256 res0 = xRay.rayPow(0);
        assertEq(res0, RAY);

        uint256 res1 = xRay.rayPow(1);
        assertEq(res1, xRay);

        uint256 res2 = xRay.rayPow(2);
        assertEq(res2, xRay.rayMul(xRay));
    }

    function testFuzz_WadMul(uint128 a, uint128 b) public pure {
        uint256 aWad = uint256(a);
        uint256 bWad = uint256(b);
        uint256 res = aWad.wadMul(bWad);
        uint256 expected = (aWad * bWad) / WAD;
        assertEq(res, expected);
    }
}
