// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ILendingPool
/// @notice Core interface for the SolisLattice lending facility and multi-asset collateral pool.
interface ILendingPool {
    struct CollateralConfig {
        uint256 ltvWad; // Loan-to-Value ratio (18 decimals)
        uint256 liquidationThresholdWad; // Liquidation threshold ratio (18 decimals)
        uint256 liquidationBonusWad; // Liquidation incentive bonus (18 decimals)
        uint256 supplyCap; // Maximum allowable collateral deposit
        uint256 totalSupplied; // Current total supplied collateral
        bool isEnabled; // Whether the collateral is active
        bool isFrozen; // Emergency pause on new deposits
    }

    struct UserAccountData {
        uint256 totalCollateralValueUsdWad;
        uint256 totalDebtValueUsdWad;
        uint256 availableBorrowsUsdWad;
        uint256 currentLiquidationThresholdWad;
        uint256 healthFactorWad;
    }

    event DepositCollateral(address indexed asset, address indexed user, address indexed onBehalfOf, uint256 amount);
    event WithdrawCollateral(address indexed asset, address indexed user, address indexed to, uint256 amount);
    event BorrowDebt(address indexed user, address indexed to, uint256 amount, uint256 borrowIndex);
    event RepayDebt(address indexed user, address indexed onBehalfOf, uint256 amount, uint256 borrowIndex);
    event FlashAccountingTriggered(address indexed initiator, uint256 netDeltaDebt);

    function deposit(address asset, uint256 amount, address onBehalfOf) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function borrow(uint256 amount, address to) external;
    function borrowOnBehalf(address onBehalfOf, uint256 amount, address to) external;
    function repay(uint256 amount, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user) external view returns (UserAccountData memory);
    function getCollateralBalance(address user, address asset) external view returns (uint256);
    function getAssetConfig(address asset) external view returns (CollateralConfig memory);
    function totalProtocolDebt() external view returns (uint256);
    function borrowIndex() external view returns (uint256);
    function liquidateBadDebtDirect(address user, address collateralAsset, uint256 debtToCover)
        external
        returns (uint256 collateralLiquidated);
}
