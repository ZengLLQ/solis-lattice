// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StabilityPool} from "../src/core/StabilityPool.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {SolisCollateralToken} from "../src/tokens/SolisCollateralToken.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";

contract StabilityPoolTest is Test {
    LatticeAccessController public access;
    SolisDebtToken public debtToken;
    SolisCollateralToken public collateral;
    StabilityPool public pool;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public mockLendingPool = address(this);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        debtToken = new SolisDebtToken(mockLendingPool);
        collateral = new SolisCollateralToken("Wrapped Ether", "WETH", 18);

        pool = new StabilityPool(address(access), address(debtToken), mockLendingPool);

        // Mint debt tokens to Alice and Bob
        debtToken.mint(alice, 1000 * WAD, RAY);
        debtToken.mint(bob, 2000 * WAD, RAY);

        // Mint collateral to mock lending pool
        collateral.mint(address(this), 100 * WAD);
        collateral.approve(address(pool), type(uint256).max);
    }

    function test_ProvideAndWithdraw() public {
        vm.startPrank(alice);
        debtToken.approve(address(pool), 500 * WAD);
        pool.provideDeposit(500 * WAD);

        assertEq(pool.getCompoundedDeposit(alice), 500 * WAD);
        assertEq(pool.totalDepositPool(), 500 * WAD);

        pool.withdrawDeposit(200 * WAD);
        assertEq(pool.getCompoundedDeposit(alice), 300 * WAD);
        assertEq(pool.totalDepositPool(), 300 * WAD);
        vm.stopPrank();
    }

    function test_AbsorbDebt_ConstantTime() public {
        // Alice deposits 1000 debt tokens
        vm.startPrank(alice);
        debtToken.approve(address(pool), 1000 * WAD);
        pool.provideDeposit(1000 * WAD);
        vm.stopPrank();

        // Transfer 1 WETH collateral to pool as liquidation reward
        collateral.transfer(address(pool), 1 * WAD);

        // Absorb 200 debt tokens (20% loss)
        uint256 offset = pool.absorbDebt(200 * WAD, address(collateral), 1 * WAD);
        assertEq(offset, 200 * WAD);

        // Alice compounded deposit should now be 800 WAD
        assertEq(pool.getCompoundedDeposit(alice), 800 * WAD);
        assertEq(pool.totalDepositPool(), 800 * WAD);
    }
}
