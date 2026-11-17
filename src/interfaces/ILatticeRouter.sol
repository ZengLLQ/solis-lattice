// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ILatticeRouter
/// @notice Interface for multicall periphery router executing atomic deposit, borrow, and flash-unwind operations.
interface ILatticeRouter {
    struct DepositAndBorrowParams {
        address collateralAsset;
        uint256 depositAmount;
        uint256 borrowAmount;
        address recipient;
    }

    struct RepayAndWithdrawParams {
        address collateralAsset;
        uint256 repayAmount;
        uint256 withdrawAmount;
        address recipient;
    }

    function depositAndBorrow(DepositAndBorrowParams calldata params) external returns (uint256 debtMinted);
    function repayAndWithdraw(RepayAndWithdrawParams calldata params) external returns (uint256 collateralReturned);
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}
