// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {LatticeRouter} from "../src/periphery/LatticeRouter.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {ILatticeRouter} from "../src/interfaces/ILatticeRouter.sol";

contract LatticeRouterTest is Test {
    LatticeAccessController public access;
    LendingPool public pool;
    SolisDebtToken public debtToken;
    SolisCollateralToken public collateral;
    CompositeOracle public oracle;
    MockPriceFeed public feed;
    PIDRateController public rateCtrl;
    StabilityPool public stabilityPool;
    LatticeRouter public router;

    address public user = address(0xFACE);
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        pool = new LendingPool(address(access));
        debtToken = new SolisDebtToken(address(pool));
        oracle = new CompositeOracle(address(access));

        feed = new MockPriceFeed(2500e8, 8); // $2500
        collateral = new SolisCollateralToken("WETH", "WETH", 18);
        oracle.setAssetFeed(address(collateral), address(feed), 8, 3600, 500);

        stabilityPool = new StabilityPool(address(access), address(debtToken), address(pool));

        rateCtrl =
            new PIDRateController(address(access), 0.1e18, 0.01e18, 0.01e18, 0.8e18, 0.04e18, 0.01e18, 0.5e18, 5e18);

        pool.setDependencies(
            address(debtToken), address(rateCtrl), address(oracle), address(stabilityPool), address(this)
        );
        pool.configureCollateral(address(collateral), 0.8e18, 0.85e18, 0.05e18, 1000 * WAD, true);

        router = new LatticeRouter(address(pool), address(debtToken));

        collateral.mint(user, 10 * WAD);
    }

    function test_DepositAndBorrowAtomic() public {
        vm.startPrank(user);
        collateral.approve(address(router), 4 * WAD);

        ILatticeRouter.DepositAndBorrowParams memory params = ILatticeRouter.DepositAndBorrowParams({
            collateralAsset: address(collateral),
            depositAmount: 4 * WAD, // $10,000
            borrowAmount: 5000 * WAD,
            recipient: user
        });

        uint256 minted = router.depositAndBorrow(params);
        assertEq(minted, 5000 * WAD);
        assertEq(debtToken.balanceOf(user), 5000 * WAD);
        assertEq(pool.getCollateralBalance(user, address(collateral)), 4 * WAD);
        vm.stopPrank();
    }
}
