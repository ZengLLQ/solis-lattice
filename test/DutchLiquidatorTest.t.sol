// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DutchLiquidator} from "../src/core/DutchLiquidator.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";

contract DutchLiquidatorTest is Test {
    LatticeAccessController public access;
    LendingPool public pool;
    StabilityPool public stabilityPool;
    DutchLiquidator public liquidator;
    CompositeOracle public oracle;
    MockPriceFeed public ethFeed;
    SolisDebtToken public debtToken;
    SolisCollateralToken public collateral;
    PIDRateController public rateCtrl;

    address public borrower = address(0xBA);
    address public buyer = address(0xBB);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        pool = new LendingPool(address(access));
        debtToken = new SolisDebtToken(address(pool));
        oracle = new CompositeOracle(address(access));

        ethFeed = new MockPriceFeed(3000e8, 8); // $3000
        collateral = new SolisCollateralToken("WETH", "WETH", 18);
        oracle.setAssetFeed(address(collateral), address(ethFeed), 8, 3600, 500);

        stabilityPool = new StabilityPool(address(access), address(debtToken), address(pool));

        rateCtrl =
            new PIDRateController(address(access), 0.1e18, 0.01e18, 0.01e18, 0.8e18, 0.04e18, 0.01e18, 0.5e18, 5e18);

        pool.setDependencies(
            address(debtToken), address(rateCtrl), address(oracle), address(stabilityPool), address(this)
        );
        pool.configureCollateral(address(collateral), 0.8e18, 0.85e18, 0.05e18, 1000 * WAD, true);

        liquidator = new DutchLiquidator(
            address(access), address(pool), address(stabilityPool), address(oracle), address(debtToken)
        );

        // Fund borrower with collateral and borrow debt
        collateral.mint(borrower, 10 * WAD);
        vm.startPrank(borrower);
        collateral.approve(address(pool), 10 * WAD);
        pool.deposit(address(collateral), 10 * WAD, borrower);
        // Borrow $20,000 (Collateral = $30,000, LTV = 66%)
        pool.borrow(20000 * WAD, borrower);
        vm.stopPrank();

        // Mint debt tokens to buyer for liquidations
        vm.prank(address(pool));
        debtToken.mint(buyer, 50000 * WAD, RAY);
    }

    function test_PriceDecaysOverTime() public {
        // Drop ETH price to $2200 to trigger liquidation threshold ($22,000 * 0.85 = $18,700 < $20,000 debt)
        ethFeed.setPrice(2200e8);

        uint256 auctionId = liquidator.startAuction(borrower, address(collateral), 5000 * WAD);

        uint256 price0 = liquidator.getCurrentAuctionPriceRay(auctionId);

        uint256 t0 = block.timestamp;
        // Warp 900 seconds (halfway through 1800s auction)
        vm.warp(t0 + 900);
        uint256 priceHalf = liquidator.getCurrentAuctionPriceRay(auctionId);

        // Warp to end of auction (1800s)
        vm.warp(t0 + 1800);
        uint256 priceEnd = liquidator.getCurrentAuctionPriceRay(auctionId);

        assertLt(priceHalf, price0);
        assertLt(priceEnd, priceHalf);
    }

    function test_BuyAuctionExecution() public {
        ethFeed.setPrice(2200e8);
        uint256 auctionId = liquidator.startAuction(borrower, address(collateral), 5000 * WAD);

        uint256 t0 = block.timestamp;
        vm.warp(t0 + 900);

        vm.startPrank(buyer);
        debtToken.approve(address(liquidator), 5000 * WAD);
        (uint256 bought, uint256 cleared) = liquidator.buyAuction(auctionId, 5000 * WAD);
        vm.stopPrank();

        assertGt(bought, 0);
        assertEq(cleared, 5000 * WAD);
        assertGt(collateral.balanceOf(buyer), 0);
    }
}
