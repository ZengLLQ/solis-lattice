// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDutchLiquidator} from "../interfaces/IDutchLiquidator.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IStabilityPool} from "../interfaces/IStabilityPool.sol";
import {ICompositeOracle} from "../interfaces/ICompositeOracle.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

/// @title DutchLiquidator
/// @notice Continuous Dutch auction liquidation engine with linear price decay and stability pool fallback.
contract DutchLiquidator is IDutchLiquidator {
    using WadRayMath for uint256;

    uint256 public constant DEFAULT_AUCTION_DURATION = 1800; // 30 minutes
    uint256 public constant START_PREMIUM_BPS = 500; // +5% start price
    uint256 public constant FLOOR_DISCOUNT_BPS = 1500; // -15% floor price
    uint256 public constant BPS = 10000;

    LatticeAccessController public immutable accessController;
    ILendingPool public immutable lendingPool;
    IStabilityPool public immutable stabilityPool;
    ICompositeOracle public immutable oracle;
    ISolisDebtToken public immutable debtToken;

    uint256 public auctionCount;
    mapping(uint256 => AuctionState) public auctions;

    error Unauthorized();
    error AuctionAlreadySettled();
    error AuctionNotSettled();
    error AuctionNotExpired();
    error InsufficientHealthFactor();
    error ZeroDebt();

    constructor(
        address _accessController,
        address _lendingPool,
        address _stabilityPool,
        address _oracle,
        address _debtToken
    ) {
        require(_accessController != address(0) && _lendingPool != address(0), "Zero address");
        accessController = LatticeAccessController(_accessController);
        lendingPool = ILendingPool(_lendingPool);
        stabilityPool = IStabilityPool(_stabilityPool);
        oracle = ICompositeOracle(_oracle);
        debtToken = ISolisDebtToken(_debtToken);
    }

    /// @notice Initiates a Dutch liquidation auction for an underwater borrower account.
    function startAuction(address borrower, address collateralAsset, uint256 debtToCover)
        external
        override
        returns (uint256 auctionId)
    {
        if (debtToCover == 0) revert ZeroDebt();

        ILendingPool.UserAccountData memory accountData = lendingPool.getUserAccountData(borrower);
        if (accountData.healthFactorWad >= WadRayMath.WAD) revert InsufficientHealthFactor();

        uint256 oraclePriceWad = oracle.getAssetPrice(collateralAsset);
        uint256 startPriceWad = (oraclePriceWad * (BPS + START_PREMIUM_BPS)) / BPS;
        uint256 floorPriceWad = (oraclePriceWad * (BPS - FLOOR_DISCOUNT_BPS)) / BPS;

        // Convert to RAY
        uint256 startPriceRay = startPriceWad.wadToRay();
        uint256 floorPriceRay = floorPriceWad.wadToRay();

        // Calculate collateral required to cover debt at floor price
        uint256 collateralAvailable = (debtToCover * WadRayMath.WAD) / floorPriceWad;
        uint256 borrowerCollateral = lendingPool.getCollateralBalance(borrower, collateralAsset);
        if (collateralAvailable > borrowerCollateral) {
            collateralAvailable = borrowerCollateral;
        }

        auctionId = ++auctionCount;
        auctions[auctionId] = AuctionState({
            borrower: borrower,
            collateralAsset: collateralAsset,
            debtToLiquidate: debtToCover,
            collateralAvailable: collateralAvailable,
            startTimestamp: block.timestamp,
            duration: DEFAULT_AUCTION_DURATION,
            startPriceRay: startPriceRay,
            floorPriceRay: floorPriceRay,
            settled: false
        });

        emit AuctionCreated(auctionId, borrower, collateralAsset, debtToCover);
    }

    /// @notice Executes a purchase of collateral from the Dutch auction by paying down borrower debt.
    function buyAuction(uint256 auctionId, uint256 maxDebtToPay)
        external
        override
        returns (uint256 collateralBought, uint256 debtCleared)
    {
        AuctionState storage auction = auctions[auctionId];
        if (auction.settled) revert AuctionAlreadySettled();

        uint256 currentPriceRay = getCurrentAuctionPriceRay(auctionId);
        uint256 currentPriceWad = currentPriceRay.rayToWad();

        // Determine how much debt to clear
        debtCleared = maxDebtToPay > auction.debtToLiquidate ? auction.debtToLiquidate : maxDebtToPay;
        collateralBought = (debtCleared * WadRayMath.WAD) / currentPriceWad;

        if (collateralBought > auction.collateralAvailable) {
            collateralBought = auction.collateralAvailable;
            debtCleared = (collateralBought * currentPriceWad) / WadRayMath.WAD;
        }

        auction.debtToLiquidate -= debtCleared;
        auction.collateralAvailable -= collateralBought;

        if (auction.debtToLiquidate == 0 || auction.collateralAvailable == 0) {
            auction.settled = true;
        }

        // Transfer debt tokens from liquidator to lending pool for burning
        bool transferred = IERC20(address(debtToken)).transferFrom(msg.sender, address(this), debtCleared);
        require(transferred, "Debt transfer failed");

        // Repay on behalf of borrower in pool
        IERC20(address(debtToken)).approve(address(lendingPool), debtCleared);
        lendingPool.repay(debtCleared, auction.borrower);

        // Seize collateral from pool to liquidator
        uint256 seized = lendingPool.liquidateBadDebtDirect(auction.borrower, auction.collateralAsset, debtCleared);
        if (seized < collateralBought) {
            collateralBought = seized;
        }
        IERC20(auction.collateralAsset).transfer(msg.sender, collateralBought);

        emit AuctionCleared(auctionId, msg.sender, debtCleared, collateralBought);
    }

    /// @notice Returns the decaying auction price at current block timestamp.
    function getCurrentAuctionPriceRay(uint256 auctionId) public view override returns (uint256 priceRay) {
        AuctionState memory auction = auctions[auctionId];
        if (block.timestamp <= auction.startTimestamp) {
            return auction.startPriceRay;
        }

        uint256 elapsed = block.timestamp - auction.startTimestamp;
        if (elapsed >= auction.duration) {
            return auction.floorPriceRay;
        }

        uint256 priceDeltaRay = auction.startPriceRay - auction.floorPriceRay;
        uint256 decayAmountRay = (priceDeltaRay * elapsed) / auction.duration;

        return auction.startPriceRay - decayAmountRay;
    }

    function getAuction(uint256 auctionId) external view override returns (AuctionState memory) {
        return auctions[auctionId];
    }
}
