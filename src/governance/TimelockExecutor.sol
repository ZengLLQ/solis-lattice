// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LatticeAccessController} from "./LatticeAccessController.sol";

/// @title TimelockExecutor
/// @notice Two-step timelock proposal queue and delayed execution controller for risk parameter updates.
contract TimelockExecutor {
    uint256 public constant MINIMUM_DELAY = 1 days;
    uint256 public constant MAXIMUM_DELAY = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;

    LatticeAccessController public immutable accessController;
    uint256 public delay;

    mapping(bytes32 => bool) public queuedTransactions;

    event TransactionQueued(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta
    );
    event TransactionExecuted(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta
    );
    event TransactionCancelled(bytes32 indexed txHash);
    event DelayUpdated(uint256 newDelay);

    error InvalidDelay();
    error NotTimelockAdmin();
    error TransactionNotQueued();
    error TransactionLocked();
    error TransactionStale();
    error ExecutionFailed();

    modifier onlyTimelockAdmin() {
        if (!accessController.hasRole(accessController.TIMELOCK_ROLE(), msg.sender)) {
            revert NotTimelockAdmin();
        }
        _;
    }

    constructor(address _accessController, uint256 _delay) {
        if (_delay < MINIMUM_DELAY || _delay > MAXIMUM_DELAY) revert InvalidDelay();
        accessController = LatticeAccessController(_accessController);
        delay = _delay;
    }

    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyTimelockAdmin returns (bytes32 txHash) {
        if (eta < block.timestamp + delay) revert InvalidDelay();

        txHash = keccak256(abi.encode(target, value, signature, data, eta));
        queuedTransactions[txHash] = true;

        emit TransactionQueued(txHash, target, value, signature, data, eta);
    }

    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyTimelockAdmin {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) revert TransactionNotQueued();

        queuedTransactions[txHash] = false;
        emit TransactionCancelled(txHash);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable onlyTimelockAdmin returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        if (!queuedTransactions[txHash]) revert TransactionNotQueued();
        if (block.timestamp < eta) revert TransactionLocked();
        if (block.timestamp > eta + GRACE_PERIOD) revert TransactionStale();

        queuedTransactions[txHash] = false;

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) revert ExecutionFailed();

        emit TransactionExecuted(txHash, target, value, signature, data, eta);
        return returnData;
    }

    function setDelay(uint256 newDelay) external {
        if (msg.sender != address(this)) revert NotTimelockAdmin();
        if (newDelay < MINIMUM_DELAY || newDelay > MAXIMUM_DELAY) revert InvalidDelay();
        delay = newDelay;
        emit DelayUpdated(newDelay);
    }
}
