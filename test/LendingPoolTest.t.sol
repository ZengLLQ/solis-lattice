// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";

contract LendingPoolTest is Test {
    LatticeAccessController public access;
    LendingPool public pool;
    SolisDebtToken public debtToken;
    SolisCollateralToken public collateral;
    CompositeOracle public oracle;
    MockPriceFeed public feed;
    PIDRateController public rateCtrl;
    StabilityPool public stabilityPool;

    address public user = address(0xCAFE);
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        pool = new LendingPool(address(access));
        debtToken = new SolisDebtToken(address(pool));
        oracle = new CompositeOracle(address(access));

        feed = new MockPriceFeed(2000e8, 8); // $2000
        collateral = new SolisCollateralToken("WETH", "WETH", 18);
        oracle.setAssetFeed(address(collateral), address(feed), 8, 3600, 500);

        stabilityPool = new StabilityPool(address(access), address(debtToken), address(pool));

        rateCtrl =
            new PIDRateController(address(access), 0.1e18, 0.01e18, 0.01e18, 0.8e18, 0.04e18, 0.01e18, 0.5e18, 5e18);

        pool.setDependencies(
            address(debtToken), address(rateCtrl), address(oracle), address(stabilityPool), address(this)
        );
        pool.configureCollateral(address(collateral), 0.75e18, 0.8e18, 0.05e18, 1000 * WAD, true);

        collateral.mint(user, 10 * WAD);
    }

    function test_DepositAndBorrow() public {
        vm.startPrank(user);
        collateral.approve(address(pool), 5 * WAD);
        // Deposit 5 WETH ($10,000)
        pool.deposit(address(collateral), 5 * WAD, user);

        ILendingPool.UserAccountData memory data = pool.getUserAccountData(user);
        assertEq(data.totalCollateralValueUsdWad, 10000 * WAD);
        // LTV 75% => $7,500 borrow power
        assertEq(data.availableBorrowsUsdWad, 7500 * WAD);

        // Borrow $5,000
        pool.borrow(5000 * WAD, user);
        assertEq(debtToken.balanceOf(user), 5000 * WAD);

        data = pool.getUserAccountData(user);
        assertEq(data.totalDebtValueUsdWad, 5000 * WAD);
        assertGt(data.healthFactorWad, 1e18);
        vm.stopPrank();
    }

    function test_RepayReducesDebt() public {
        vm.startPrank(user);
        collateral.approve(address(pool), 5 * WAD);
        pool.deposit(address(collateral), 5 * WAD, user);
        pool.borrow(3000 * WAD, user);

        debtToken.approve(address(pool), 1000 * WAD);
        uint256 repaid = pool.repay(1000 * WAD, user);
        assertEq(repaid, 1000 * WAD);

        ILendingPool.UserAccountData memory data = pool.getUserAccountData(user);
        assertEq(data.totalDebtValueUsdWad, 2000 * WAD);
        vm.stopPrank();
    }
}
