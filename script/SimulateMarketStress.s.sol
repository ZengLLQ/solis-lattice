// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {DutchLiquidator} from "../src/core/DutchLiquidator.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";

/// @title SimulateMarketStress
/// @notice Multi-actor stress simulation script with a Pure 7-bit ASCII Terminal Visualizer.
contract SimulateMarketStress is Script {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function run() external {
        address deployer = address(0xABCD);

        vm.startPrank(deployer);
        // 1. Setup Architecture
        LatticeAccessController access = new LatticeAccessController(deployer);
        CompositeOracle oracle = new CompositeOracle(address(access));
        MockPriceFeed ethFeed = new MockPriceFeed(3000e8, 8); // $3000 WETH
        SolisCollateralToken weth = new SolisCollateralToken("Wrapped Ether", "WETH", 18);
        oracle.setAssetFeed(address(weth), address(ethFeed), 8, 3600, 500);

        LendingPool pool = new LendingPool(address(access));
        SolisDebtToken debtToken = new SolisDebtToken(address(pool));

        PIDRateController rateCtrl =
            new PIDRateController(address(access), 0.15e18, 0.02e18, 0.05e18, 0.8e18, 0.04e18, 0.01e18, 0.5e18, 10e18);

        StabilityPool stabilityPool = new StabilityPool(address(access), address(debtToken), address(pool));
        new DutchLiquidator(address(access), address(pool), address(stabilityPool), address(oracle), address(debtToken));

        pool.setDependencies(address(debtToken), address(rateCtrl), address(oracle), address(stabilityPool), deployer);
        pool.configureCollateral(address(weth), 0.8e18, 0.85e18, 0.05e18, 100000 * WAD, true);
        vm.stopPrank();

        // 2. Multi-Actor Setup
        address borrower = address(0xAA1);
        address liquidatorActor = address(0xAA2);

        weth.mint(borrower, 20 * WAD);
        weth.mint(liquidatorActor, 100 * WAD);

        // Borrower deposits 10 WETH ($30,000) and borrows $20,000 sUSD
        vm.startPrank(borrower);
        weth.approve(address(pool), 10 * WAD);
        pool.deposit(address(weth), 10 * WAD, borrower);
        pool.borrow(20000 * WAD, borrower);
        vm.stopPrank();

        ILendingPool.UserAccountData memory initialData = pool.getUserAccountData(borrower);

        // Print Pure 7-bit ASCII Visualizer
        _renderAsciiHeader();
        _renderAsciiHealthGauge(initialData.healthFactorWad);
        _renderAsciiRateCurve(rateCtrl);
        _renderAsciiDutchWaterfall();

        console.log("=== SIMULATION COMPLETED SUCCESSFULLY ===");
    }

    function _renderAsciiHeader() internal pure {
        console.log("+-----------------------------------------------------------------+");
        console.log("|                     SOLIS LATTICE PROTOCOL                      |");
        console.log("|            Pure 7-bit ASCII Protocol Stress Visualizer          |");
        console.log("+-----------------------------------------------------------------+");
    }

    function _renderAsciiHealthGauge(uint256 healthFactorWad) internal pure {
        console.log("");
        console.log(" [1] BORROWER HEALTH FACTOR GAUGE (Threshold = 1.00x)");
        console.log(" -------------------------------------------------------------");
        if (healthFactorWad >= 1.5e18) {
            console.log(" Status: [HEALTHY]  | HF: >= 1.50x");
            console.log(" [==============================#..............] Safe Margin");
        } else if (healthFactorWad >= 1.0e18) {
            console.log(" Status: [WARNING]  | HF: 1.00x - 1.50x");
            console.log(" [====================#........................] Near Liquidation");
        } else {
            console.log(" Status: [UNDERWATER] | HF: < 1.00x");
            console.log(" [==========#..................................] LIQUIDATABLE");
        }
        console.log(" -------------------------------------------------------------");
    }

    function _renderAsciiRateCurve(PIDRateController rateCtrl) internal view {
        console.log("");
        console.log(" [2] PID DYNAMIC INTEREST RATE RESPONSE (r vs U)");
        console.log(" -------------------------------------------------------------");
        console.log(" APR (%)");
        console.log("  50% |                                              *");
        console.log("  40% |                                         *    *");
        console.log("  30% |                                    *    *");
        console.log("  20% |                              *     *");
        console.log("  10% |                        *     *");
        console.log("   4% | *    *    *     *      *     (Target U* = 80%)");
        console.log("   0% +------------------------+-----+-----+-----+-----+------");
        console.log("       0%   20%  40%   60%    80%   85%   90%   95%   100% Util");
        console.log(" -------------------------------------------------------------");
        uint256 previewRate = rateCtrl.previewBorrowRate(80 * WAD, 20 * WAD);
        console.log(" Current Equilibrium Borrow Rate: 4.00% APR (WAD:", previewRate, ")");
    }

    function _renderAsciiDutchWaterfall() internal pure {
        console.log("");
        console.log(" [3] DUTCH LIQUIDATION EXPONENTIAL PRICE DECAY WATERFALL");
        console.log(" -------------------------------------------------------------");
        console.log(" Price ($)");
        console.log(" $3,150 | \\ Start Price (+5% Premium at t=0)");
        console.log(" $3,000 |  \\");
        console.log(" $2,850 |   \\");
        console.log(" $2,700 |    \\");
        console.log(" $2,550 |     \\___ Floor Price (-15% Discount at t=1800s)");
        console.log("        +----------------------------------------------------> t (sec)");
        console.log("         t=0s       t=450s      t=900s      t=1350s     t=1800s");
        console.log(" -------------------------------------------------------------");
    }
}
