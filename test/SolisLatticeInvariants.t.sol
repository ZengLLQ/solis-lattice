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
import {TransientSlot} from "../src/libraries/TransientSlot.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";

contract SolisLatticeInvariants is Test {
    using WadRayMath for uint256;

    LatticeAccessController public access;
    LendingPool public pool;
    SolisDebtToken public debtToken;
    SolisCollateralToken public collateral;
    CompositeOracle public oracle;
    MockPriceFeed public feed;
    PIDRateController public rateCtrl;
    StabilityPool public stabilityPool;

    address[] public actors;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

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
        pool.configureCollateral(address(collateral), 0.75e18, 0.8e18, 0.05e18, 100000 * WAD, true);

        // Setup actors
        actors.push(address(0x101));
        actors.push(address(0x102));
        actors.push(address(0x103));

        for (uint256 i = 0; i < actors.length; ++i) {
            collateral.mint(actors[i], 100 * WAD);
            vm.prank(actors[i]);
            collateral.approve(address(pool), type(uint256).max);
        }
    }

    /// @notice Invariant 1: Total protocol debt equals scaledTotalSupply * borrowIndex / RAY.
    function testFuzz_InvariantTotalDebtAccounting(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 100 * WAD, 50000 * WAD);

        address actor = actors[0];
        vm.startPrank(actor);
        pool.deposit(address(collateral), 50 * WAD, actor); // $100,000 collateral => $75,000 max borrow
        pool.borrow(borrowAmount, actor);
        vm.stopPrank();

        // Warp time to trigger interest accrual
        vm.warp(block.timestamp + 86400); // 1 day
        pool.updateState();

        uint256 calculatedTotalDebt = (debtToken.scaledTotalSupply() * pool.borrowIndex()) / RAY;
        assertEq(pool.totalProtocolDebt(), calculatedTotalDebt);
    }

    /// @notice Invariant 2: Account health factor calculation preserves solvency condition.
    function testFuzz_InvariantSolvency(uint256 depositAmt, uint256 borrowAmt) public {
        depositAmt = bound(depositAmt, 10 * WAD, 100 * WAD);
        uint256 maxBorrow = (depositAmt * 2000 * 75) / 100;
        borrowAmt = bound(borrowAmt, 10 * WAD, maxBorrow);

        address actor = actors[1];
        vm.startPrank(actor);
        pool.deposit(address(collateral), depositAmt, actor);
        pool.borrow(borrowAmt, actor);
        vm.stopPrank();

        ILendingPool.UserAccountData memory data = pool.getUserAccountData(actor);
        assertGe(data.healthFactorWad, WAD);
    }

    /// @notice Invariant 3: Stability pool product accumulator P is bounded: P <= 1.0 (1e18) within epoch.
    function test_InvariantStabilityPoolProductBound() public {
        address actor = actors[2];

        // Mint debt tokens to actor
        vm.prank(address(pool));
        debtToken.mint(actor, 1000 * WAD, RAY);

        vm.startPrank(actor);
        debtToken.approve(address(stabilityPool), 1000 * WAD);
        stabilityPool.provideDeposit(1000 * WAD);
        vm.stopPrank();

        assertLe(stabilityPool.pProduct(), WAD);

        // Absorb debt
        collateral.mint(address(stabilityPool), 1 * WAD);
        vm.prank(address(pool));
        stabilityPool.absorbDebt(300 * WAD, address(collateral), 1 * WAD);

        assertLe(stabilityPool.pProduct(), WAD);
    }
}
