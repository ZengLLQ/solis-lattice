// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFlashCallback, FlashEngine} from "../../src/core/FlashEngine.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @title MockFlashReceiver
/// @notice Test helper receiver for validating FlashEngine behavior.
contract MockFlashReceiver is IFlashCallback {
    bytes32 public constant FLASH_CALLBACK_SUCCESS = keccak256("IFlashCallback.onFlashOperation");

    address public immutable debtToken;
    bool public shouldFail;
    bool public shouldRefuseRepay;

    constructor(address _debtToken) {
        debtToken = _debtToken;
    }

    function setShouldFail(bool _fail) external {
        shouldFail = _fail;
    }

    function setShouldRefuseRepay(bool _refuse) external {
        shouldRefuseRepay = _refuse;
    }

    function onFlashOperation(
        uint256 amount,
        uint256 fee,
        bytes calldata /* data */
    )
        external
        override
        returns (bytes32)
    {
        if (shouldFail) {
            return bytes32(0);
        }

        if (!shouldRefuseRepay) {
            // Approve FlashEngine to reclaim amount + fee
            IERC20(debtToken).approve(msg.sender, amount + fee);
        }

        return FLASH_CALLBACK_SUCCESS;
    }
}
