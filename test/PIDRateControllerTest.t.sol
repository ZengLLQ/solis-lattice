// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PIDRateController} from "../src/core/PIDRateController.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {IPIDRateController} from "../src/interfaces/IPIDRateController.sol";

contract PIDRateControllerTest is Test {
    LatticeAccessController public access;
    PIDRateController public controller;

    uint256 internal constant WAD = 1e18;

    function setUp() public {
        access = new LatticeAccessController(address(this));

        controller = new PIDRateController(
            address(access),
            0.1e18, // Kp = 0.10
            0.01e18, // Ki = 0.01
            0.05e18, // Kd = 0.05
            0.8e18, // Target utilization = 80%
            0.04e18, // Base rate = 4%
            0.01e18, // Min rate = 1%
            0.5e18, // Max rate = 50%
            5e18 // Anti-windup clamp
        );
    }

    function test_InitialRateAtTargetUtilization() public {
        // Borrows = 80, Reserves = 20 => Util = 80%
        uint256 rate = controller.computeBorrowRate(80 * WAD, 20 * WAD);
        assertEq(rate, 0.04e18); // Equal to base rate 4%
    }

    function test_RateIncreasesWhenUtilizationAboveTarget() public {
        // Step time
        vm.warp(block.timestamp + 3600);

        // Borrows = 90, Reserves = 10 => Util = 90% (Error = +10%)
        uint256 rate = controller.computeBorrowRate(90 * WAD, 10 * WAD);
        assertGt(rate, 0.04e18);
    }

    function test_RateDecreasesWhenUtilizationBelowTarget() public {
        vm.warp(block.timestamp + 3600);

        // Borrows = 50, Reserves = 50 => Util = 50% (Error = -30%)
        uint256 rate = controller.computeBorrowRate(50 * WAD, 50 * WAD);
        assertLt(rate, 0.04e18);
        assertGe(rate, 0.01e18); // Respects min rate floor
    }
}
