// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title TransientSlot
/// @notice EIP-1153 transient storage abstraction leveraging tstore and tload instructions (Cancun EVM).
/// @dev Enables zero-cost gas reset for reentrancy locks, flash-accounting net balances, and cross-contract callbacks.
library TransientSlot {
    bytes32 internal constant REENTRANCY_GUARD_SLOT = keccak256("solis.lattice.transient.reentrancy");
    bytes32 internal constant FLASH_NET_DEBT_SLOT = keccak256("solis.lattice.transient.flash.debt");
    bytes32 internal constant FLASH_INITIATOR_SLOT = keccak256("solis.lattice.transient.flash.initiator");

    error ReentrantCall();
    error UnbalancedFlashAccounting(int256 netDebtDelta);

    /// @notice Writes a bytes32 word into transient storage at given slot.
    function tstore(bytes32 slot, bytes32 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Reads a bytes32 word from transient storage at given slot.
    function tload(bytes32 slot) internal view returns (bytes32 value) {
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Acquires reentrancy lock in transient storage. Reverts if already locked.
    function lock() internal {
        if (tload(REENTRANCY_GUARD_SLOT) != bytes32(0)) revert ReentrantCall();
        tstore(REENTRANCY_GUARD_SLOT, bytes32(uint256(1)));
    }

    /// @notice Releases reentrancy lock in transient storage.
    function unlock() internal {
        tstore(REENTRANCY_GUARD_SLOT, bytes32(0));
    }

    /// @notice Records delta to net flash debt in transient storage.
    function recordFlashDebtDelta(int256 delta) internal {
        int256 current = int256(uint256(tload(FLASH_NET_DEBT_SLOT)));
        int256 updated = current + delta;
        tstore(FLASH_NET_DEBT_SLOT, bytes32(uint256(updated)));
    }

    /// @notice Asserts that the net flash debt delta has returned to zero at the end of the execution scope.
    function assertFlashSettled() internal view {
        int256 netDebt = int256(uint256(tload(FLASH_NET_DEBT_SLOT)));
        if (netDebt != 0) revert UnbalancedFlashAccounting(netDebt);
    }

    /// @notice Clears flash accounting transient slots.
    function clearFlashState() internal {
        tstore(FLASH_NET_DEBT_SLOT, bytes32(0));
        tstore(FLASH_INITIATOR_SLOT, bytes32(0));
    }
}
