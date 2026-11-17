// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title FenwickTree
/// @notice Binary Indexed Tree (BIT) data structure for O(log N) prefix sum queries and point updates.
/// @dev Supports up to 256 tiers/buckets for dynamic cumulative risk and debt distribution tracking.
library FenwickTree {
    uint256 internal constant MAX_ELEMENTS = 256;

    error IndexOutOfRange();

    /// @notice Updates the value at 1-based index by delta: tree[i] += delta
    function update(uint256[MAX_ELEMENTS + 1] storage tree, uint256 index, uint256 delta) internal {
        if (index == 0 || index > MAX_ELEMENTS) revert IndexOutOfRange();
        uint256 idx = index;
        while (idx <= MAX_ELEMENTS) {
            tree[idx] += delta;
            idx += idx & (~idx + 1); // idx += idx & (-idx)
        }
    }

    /// @notice Queries prefix sum of values from index 1 to index: sum_{k=1}^{index} value[k]
    function queryPrefixSum(uint256[MAX_ELEMENTS + 1] storage tree, uint256 index) internal view returns (uint256 sum) {
        if (index > MAX_ELEMENTS) revert IndexOutOfRange();
        uint256 idx = index;
        while (idx > 0) {
            sum += tree[idx];
            idx -= idx & (~idx + 1); // idx -= idx & (-idx)
        }
    }

    /// @notice Queries sum over range [left, right]: sum_{k=left}^{right} value[k]
    function queryRangeSum(uint256[MAX_ELEMENTS + 1] storage tree, uint256 left, uint256 right)
        internal
        view
        returns (uint256)
    {
        if (left == 0 || left > right || right > MAX_ELEMENTS) revert IndexOutOfRange();
        return queryPrefixSum(tree, right) - queryPrefixSum(tree, left - 1);
    }
}
