// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ILatticeRouter} from "../interfaces/ILatticeRouter.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";

/// @title LatticeRouter
/// @notice Periphery multicall router facilitating atomic deposit, borrow, repay, and leverage loops.
contract LatticeRouter is ILatticeRouter {
    ILendingPool public immutable pool;
    ISolisDebtToken public immutable debtToken;

    error ZeroAddress();
    error CallFailed(uint256 index, bytes reason);

    constructor(address _pool, address _debtToken) {
        if (_pool == address(0) || _debtToken == address(0)) revert ZeroAddress();
        pool = ILendingPool(_pool);
        debtToken = ISolisDebtToken(_debtToken);
    }

    /// @notice Atomically deposits collateral and borrows debt token to recipient.
    function depositAndBorrow(DepositAndBorrowParams calldata params) external override returns (uint256 debtMinted) {
        // Transfer collateral from caller to router, then approve pool
        bool transferred = IERC20(params.collateralAsset).transferFrom(msg.sender, address(this), params.depositAmount);
        require(transferred, "Collateral transfer failed");

        IERC20(params.collateralAsset).approve(address(pool), params.depositAmount);
        pool.deposit(params.collateralAsset, params.depositAmount, msg.sender);

        // Borrow debt on behalf of caller against their deposited collateral
        pool.borrowOnBehalf(msg.sender, params.borrowAmount, params.recipient);
        debtMinted = params.borrowAmount;
    }

    /// @notice Atomically repays debt and withdraws freed collateral to recipient.
    function repayAndWithdraw(RepayAndWithdrawParams calldata params)
        external
        override
        returns (uint256 collateralReturned)
    {
        // Transfer debt token from caller to router, approve pool, and repay
        bool transferred = IERC20(address(debtToken)).transferFrom(msg.sender, address(this), params.repayAmount);
        require(transferred, "Debt token transfer failed");

        IERC20(address(debtToken)).approve(address(pool), params.repayAmount);
        pool.repay(params.repayAmount, msg.sender);

        // Withdraw collateral to recipient
        pool.withdraw(params.collateralAsset, params.withdrawAmount, params.recipient);
        collateralReturned = params.withdrawAmount;
    }

    /// @notice Batches multiple calls into a single transaction.
    function multicall(bytes[] calldata data) external override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                revert CallFailed(i, result);
            }
            results[i] = result;
        }
    }
}
