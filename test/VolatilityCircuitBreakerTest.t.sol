// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VolatilityCircuitBreaker} from "../src/oracle/VolatilityCircuitBreaker.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";

contract VolatilityCircuitBreakerTest is Test {
    LatticeAccessController public access;
    VolatilityCircuitBreaker public breaker;

    address public constant ASSET = address(0x2222);
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        breaker = new VolatilityCircuitBreaker(address(access));
    }

    function test_NormalPrice_Valid() public {
        bool ok = breaker.validateAndRecordPrice(ASSET, 100 * WAD);
        assertTrue(ok);

        vm.warp(block.timestamp + 60);
        // Small 2% move: 102 WAD
        ok = breaker.validateAndRecordPrice(ASSET, 102 * WAD);
        assertTrue(ok);
        assertFalse(breaker.isTripped(ASSET));
    }

    function test_AbnormalPriceSwing_TripsBreaker() public {
        breaker.validateAndRecordPrice(ASSET, 100 * WAD);

        vm.warp(block.timestamp + 60);
        // Massive 25% drop within window (limit is 15%)
        bool valid = breaker.validateAndRecordPrice(ASSET, 75 * WAD);
        assertFalse(valid);
        assertTrue(breaker.isTripped(ASSET));
    }

    function test_AdminResetBreaker() public {
        breaker.validateAndRecordPrice(ASSET, 100 * WAD);
        vm.warp(block.timestamp + 60);
        bool valid = breaker.validateAndRecordPrice(ASSET, 60 * WAD);
        assertFalse(valid);
        assertTrue(breaker.isTripped(ASSET));

        breaker.resetBreaker(ASSET);
        assertFalse(breaker.isTripped(ASSET));
    }
}
