// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {TimelockExecutor} from "../src/governance/TimelockExecutor.sol";
import {ProtocolTreasury} from "../src/governance/ProtocolTreasury.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {VolatilityCircuitBreaker} from "../src/oracle/VolatilityCircuitBreaker.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {DutchLiquidator} from "../src/core/DutchLiquidator.sol";
import {FlashEngine} from "../src/core/FlashEngine.sol";
import {LatticeRouter} from "../src/periphery/LatticeRouter.sol";

contract DeploySolisLattice is Script {
    uint256 internal constant WAD = 1e18;

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;

        // 1. Governance & Treasury
        LatticeAccessController access = new LatticeAccessController(deployer);
        TimelockExecutor timelock = new TimelockExecutor(address(access), 2 days);
        ProtocolTreasury treasury = new ProtocolTreasury(address(access));

        // 2. Oracle & Circuit Breaker
        CompositeOracle oracle = new CompositeOracle(address(access));
        VolatilityCircuitBreaker breaker = new VolatilityCircuitBreaker(address(access));

        MockPriceFeed ethFeed = new MockPriceFeed(3000e8, 8); // $3,000 WETH
        MockPriceFeed btcFeed = new MockPriceFeed(65000e8, 8); // $65,000 WBTC

        SolisCollateralToken weth = new SolisCollateralToken("Wrapped Ether", "WETH", 18);
        SolisCollateralToken wbtc = new SolisCollateralToken("Wrapped Bitcoin", "WBTC", 18);

        oracle.setAssetFeed(address(weth), address(ethFeed), 8, 3600, 500);
        oracle.setAssetFeed(address(wbtc), address(btcFeed), 8, 3600, 500);

        // 3. Lending Pool & Debt Token
        LendingPool pool = new LendingPool(address(access));
        SolisDebtToken debtToken = new SolisDebtToken(address(pool));

        // 4. Rate Controller & Stability Pool
        PIDRateController rateCtrl = new PIDRateController(
            address(access),
            0.12e18, // Kp
            0.015e18, // Ki
            0.04e18, // Kd
            0.8e18, // 80% target utilization
            0.04e18, // 4% base rate
            0.01e18, // 1% min rate
            0.6e18, // 60% max rate
            10e18 // anti-windup clamp
        );

        StabilityPool stabilityPool = new StabilityPool(address(access), address(debtToken), address(pool));

        DutchLiquidator liquidator = new DutchLiquidator(
            address(access), address(pool), address(stabilityPool), address(oracle), address(debtToken)
        );

        FlashEngine flashEngine = new FlashEngine(address(access), address(debtToken), address(treasury));
        LatticeRouter router = new LatticeRouter(address(pool), address(debtToken));

        // Wire Pool Dependencies
        pool.setDependencies(
            address(debtToken), address(rateCtrl), address(oracle), address(stabilityPool), address(treasury)
        );

        // Configure Collaterals: WETH (80% LTV, 85% Thresh, 5% Bonus)
        pool.configureCollateral(address(weth), 0.8e18, 0.85e18, 0.05e18, 50000 * WAD, true);
        pool.configureCollateral(address(wbtc), 0.75e18, 0.8e18, 0.06e18, 2000 * WAD, true);

        vm.stopBroadcast();
    }
}
