// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFlashCallback} from "../core/FlashEngine.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";

/// @title FlashLiquidator
/// @notice Reference arbitrage and liquidation receiver contract executing atomic liquidations via flash loans.
contract FlashLiquidator is IFlashCallback {
    bytes32 public constant FLASH_CALLBACK_SUCCESS = keccak256("IFlashCallback.onFlashOperation");

    address public immutable flashEngine;
    ILendingPool public immutable pool;
    ISolisDebtToken public immutable debtToken;
    address public owner;

    error OnlyFlashEngine();
    error OnlyOwner();
    error InsufficientProfit();

    modifier onlyFlash() {
        if (msg.sender != flashEngine) revert OnlyFlashEngine();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _flashEngine, address _pool, address _debtToken) {
        flashEngine = _flashEngine;
        pool = ILendingPool(_pool);
        debtToken = ISolisDebtToken(_debtToken);
        owner = msg.sender;
    }

    /// @notice Callback invoked by FlashEngine during flash operation.
    function onFlashOperation(uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        onlyFlash
        returns (bytes32)
    {
        (address underwaterBorrower, address collateralAsset) = abi.decode(data, (address, address));

        // Liquidate borrower's bad debt using flash-borrowed debt tokens
        IERC20(address(debtToken)).approve(address(pool), amount);
        pool.liquidateBadDebtDirect(underwaterBorrower, collateralAsset, amount);

        // Approve flashEngine to retrieve repayment plus fee
        uint256 totalOwed = amount + fee;
        IERC20(address(debtToken)).approve(flashEngine, totalOwed);

        return FLASH_CALLBACK_SUCCESS;
    }

    function withdrawToken(address token, address recipient) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(recipient, balance);
    }
}
