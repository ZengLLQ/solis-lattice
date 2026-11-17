// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BitmapTree} from "../src/libraries/BitmapTree.sol";

contract BitmapTreeTest is Test {
    using BitmapTree for uint256;

    function test_Bitmap_SetAndClear() public pure {
        uint256 map = 0;
        assertFalse(map.isBitSet(5));

        map = map.setBit(5);
        assertTrue(map.isBitSet(5));
        assertFalse(map.isBitSet(6));

        map = map.setBit(128);
        assertTrue(map.isBitSet(128));

        map = map.clearBit(5);
        assertFalse(map.isBitSet(5));
        assertTrue(map.isBitSet(128));
    }

    function test_Bitmap_FindLeastSignificantBit() public pure {
        uint256 map = 0;
        map = map.setBit(3);
        map = map.setBit(15);
        map = map.setBit(200);

        uint8 lsb = map.findLeastSignificantBit();
        assertEq(lsb, 3);
    }

    function test_Bitmap_FindMostSignificantBit() public pure {
        uint256 map = 0;
        map = map.setBit(3);
        map = map.setBit(15);
        map = map.setBit(200);

        uint8 msb = map.findMostSignificantBit();
        assertEq(msb, 200);
    }
}
