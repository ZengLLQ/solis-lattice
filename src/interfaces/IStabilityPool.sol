// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IStabilityPool
/// @notice Interface for O(1) constant-time debt absorption stability pool using dual product-sum accumulators.
interface IStabilityPool {
    struct DepositSnapshot {
        uint256 initialDeposit;
        uint256 pProduct;
        uint256 sSum;
        uint128 epoch;
        uint128 scale;
    }

    event StabilityDepositProvided(address indexed user, uint256 amount);
    event StabilityDepositWithdrawn(address indexed user, uint256 amount);
    event DebtAbsorbed(uint256 debtAbsorbed, uint256 collateralReceived, uint128 epoch, uint128 scale);
    event CollateralGainClaimed(address indexed user, address indexed asset, uint256 amount);

    function provideDeposit(uint256 amount) external;
    function withdrawDeposit(uint256 amount) external;
    function absorbDebt(uint256 debtToAbsorb, address collateralAsset, uint256 collateralReward)
        external
        returns (uint256 actualDebtOffset);
    function claimCollateralGains(address collateralAsset) external returns (uint256 gain);
    function getCompoundedDeposit(address user) external view returns (uint256);
    function getPendingCollateralGain(address user, address collateralAsset) external view returns (uint256);
    function totalDepositPool() external view returns (uint256);
}
