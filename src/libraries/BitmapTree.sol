// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title BitmapTree
/// @notice 256-bit packed bitmap index manipulation and bit-scanning routines for sparse liquidation tiers.
library BitmapTree {
    error IndexOutOfBounds();

    /// @notice Sets the bit at given index [0, 255].
    function setBit(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap | (1 << index);
    }

    /// @notice Clears the bit at given index [0, 255].
    function clearBit(uint256 bitmap, uint8 index) internal pure returns (uint256) {
        return bitmap & ~(1 << index);
    }

    /// @notice Checks if the bit at given index is set.
    function isBitSet(uint256 bitmap, uint8 index) internal pure returns (bool) {
        return (bitmap & (1 << index)) != 0;
    }

    /// @notice Finds the least significant bit (LSB) set in the bitmap.
    /// @dev Uses assembly CTZ (count trailing zeros) or de Bruijn sequence.
    function findLeastSignificantBit(uint256 bitmap) internal pure returns (uint8 index) {
        require(bitmap != 0, "Empty bitmap");
        assembly {
            // Isolates the lowest set bit: x & (-x)
            let lowest := and(bitmap, sub(0, bitmap))
            // Count trailing zeros
            // In EVM Cancun, we can compute via binary search
            let r := 0
            if iszero(and(lowest, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) {
                lowest := shr(128, lowest)
                r := add(r, 128)
            }
            if iszero(and(lowest, 0xFFFFFFFFFFFFFFFF)) {
                lowest := shr(64, lowest)
                r := add(r, 64)
            }
            if iszero(and(lowest, 0xFFFFFFFF)) {
                lowest := shr(32, lowest)
                r := add(r, 32)
            }
            if iszero(and(lowest, 0xFFFF)) {
                lowest := shr(16, lowest)
                r := add(r, 16)
            }
            if iszero(and(lowest, 0xFF)) {
                lowest := shr(8, lowest)
                r := add(r, 8)
            }
            if iszero(and(lowest, 0xF)) {
                lowest := shr(4, lowest)
                r := add(r, 4)
            }
            if iszero(and(lowest, 0x3)) {
                lowest := shr(2, lowest)
                r := add(r, 2)
            }
            if iszero(and(lowest, 0x1)) {
                r := add(r, 1)
            }
            index := r
        }
    }

    /// @notice Finds the most significant bit (MSB) set in the bitmap.
    function findMostSignificantBit(uint256 bitmap) internal pure returns (uint8 index) {
        require(bitmap != 0, "Empty bitmap");
        assembly {
            let r := 0
            if gt(bitmap, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                bitmap := shr(128, bitmap)
                r := add(r, 128)
            }
            if gt(bitmap, 0xFFFFFFFFFFFFFFFF) {
                bitmap := shr(64, bitmap)
                r := add(r, 64)
            }
            if gt(bitmap, 0xFFFFFFFF) {
                bitmap := shr(32, bitmap)
                r := add(r, 32)
            }
            if gt(bitmap, 0xFFFF) {
                bitmap := shr(16, bitmap)
                r := add(r, 16)
            }
            if gt(bitmap, 0xFF) {
                bitmap := shr(8, bitmap)
                r := add(r, 8)
            }
            if gt(bitmap, 0xF) {
                bitmap := shr(4, bitmap)
                r := add(r, 4)
            }
            if gt(bitmap, 0x3) {
                bitmap := shr(2, bitmap)
                r := add(r, 2)
            }
            if gt(bitmap, 0x1) {
                r := add(r, 1)
            }
            index := r
        }
    }
}
