// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FenwickTree} from "../src/libraries/FenwickTree.sol";

contract FenwickTreeTest is Test {
    using FenwickTree for uint256[257];

    uint256[257] private tree;

    function test_Fenwick_PrefixAndRangeSum() public {
        tree.update(1, 100);
        tree.update(2, 200);
        tree.update(3, 300);

        assertEq(tree.queryPrefixSum(1), 100);
        assertEq(tree.queryPrefixSum(2), 300);
        assertEq(tree.queryPrefixSum(3), 600);

        assertEq(tree.queryRangeSum(2, 3), 500);
        assertEq(tree.queryRangeSum(1, 2), 300);
    }
}
