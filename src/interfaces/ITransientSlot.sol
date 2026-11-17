// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ITransientSlot
/// @notice Interface for EIP-1153 transient storage flash accounting locks and ledger offsets.
interface ITransientSlot {
    function tstoreWord(bytes32 slot, bytes32 value) external;
    function tloadWord(bytes32 slot) external view returns (bytes32 value);
}
