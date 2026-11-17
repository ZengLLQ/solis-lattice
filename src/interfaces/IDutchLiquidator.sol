// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IDutchLiquidator
/// @notice Interface for continuous Dutch auction waterfall liquidation engine.
interface IDutchLiquidator {
    struct AuctionState {
        address borrower;
        address collateralAsset;
        uint256 debtToLiquidate;
        uint256 collateralAvailable;
        uint256 startTimestamp;
        uint256 duration;
        uint256 startPriceRay;
        uint256 floorPriceRay;
        bool settled;
    }

    event AuctionCreated(
        uint256 indexed auctionId, address indexed borrower, address indexed collateralAsset, uint256 debtToCover
    );
    event AuctionCleared(
        uint256 indexed auctionId, address indexed liquidator, uint256 debtPaid, uint256 collateralReceived
    );

    function startAuction(address borrower, address collateralAsset, uint256 debtToCover)
        external
        returns (uint256 auctionId);
    function buyAuction(uint256 auctionId, uint256 maxDebtToPay)
        external
        returns (uint256 collateralBought, uint256 debtCleared);
    function getCurrentAuctionPriceRay(uint256 auctionId) external view returns (uint256 priceRay);
    function getAuction(uint256 auctionId) external view returns (AuctionState memory);
}
