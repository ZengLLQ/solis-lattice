// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {TransientSlot} from "../libraries/TransientSlot.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

interface IFlashCallback {
    function onFlashOperation(uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
}

/// @title FlashEngine
/// @notice EIP-1153 transient-storage powered flash minting and flash borrowing facility.
/// @dev Leverages Cancun tstore/tload to verify zero-debt delta invariance at transaction completion.
contract FlashEngine {
    bytes32 public constant FLASH_CALLBACK_SUCCESS = keccak256("IFlashCallback.onFlashOperation");

    LatticeAccessController public immutable accessController;
    ISolisDebtToken public immutable debtToken;
    address public treasury;

    uint256 public flashFeeBps = 5; // 0.05% fee (5 basis points)

    event FlashExecuted(address indexed receiver, uint256 amount, uint256 fee);
    event FlashFeeUpdated(uint256 newFeeBps);

    error Unauthorized();
    error InvalidCallbackResponse();
    error FlashFeeExceedsMax();
    error ZeroAmount();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _accessController, address _debtToken, address _treasury) {
        if (_accessController == address(0) || _debtToken == address(0)) revert ZeroAddress();
        accessController = LatticeAccessController(_accessController);
        debtToken = ISolisDebtToken(_debtToken);
        treasury = _treasury;
    }

    /// @notice Executes atomic flash minting with EIP-1153 transient balance assertion.
    function executeFlashMint(address receiver, uint256 amount, bytes calldata data) external returns (bool) {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 fee = (amount * flashFeeBps) / 10000;

        // Record transient debt delta
        TransientSlot.recordFlashDebtDelta(int256(amount));

        // Transfer debt tokens to receiver
        bool transferred = IERC20(address(debtToken)).transfer(receiver, amount);
        require(transferred, "Flash funding transfer failed");

        // Invoke callback
        bytes32 response = IFlashCallback(receiver).onFlashOperation(amount, fee, data);
        if (response != FLASH_CALLBACK_SUCCESS) revert InvalidCallbackResponse();

        // Retrieve repayment plus fee from receiver
        bool repaid = IERC20(address(debtToken)).transferFrom(receiver, address(this), amount + fee);
        require(repaid, "Flash repayment transfer failed");

        if (fee > 0 && treasury != address(0)) {
            IERC20(address(debtToken)).transfer(treasury, fee);
        }

        // Offset transient debt delta
        TransientSlot.recordFlashDebtDelta(-int256(amount));

        // Assert EIP-1153 net settlement
        TransientSlot.assertFlashSettled();

        emit FlashExecuted(receiver, amount, fee);
        return true;
    }

    function setFlashFee(uint256 newFeeBps) external onlyAdmin {
        if (newFeeBps > 100) revert FlashFeeExceedsMax(); // max 1%
        flashFeeBps = newFeeBps;
        emit FlashFeeUpdated(newFeeBps);
    }
}
