// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CompositeOracle} from "../src/oracle/CompositeOracle.sol";
import {MockPriceFeed} from "../src/oracle/MockPriceFeed.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";

contract CompositeOracleTest is Test {
    LatticeAccessController public access;
    CompositeOracle public oracle;
    MockPriceFeed public primaryEthFeed;
    MockPriceFeed public secondaryEthFeed;

    address public constant WETH = address(0x1111);
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        oracle = new CompositeOracle(address(access));

        // 8-decimal Chainlink mock feed: $3,000 = 3000 * 1e8
        primaryEthFeed = new MockPriceFeed(3000e8, 8);
        secondaryEthFeed = new MockPriceFeed(3005e8, 8);

        oracle.setAssetFeed(WETH, address(primaryEthFeed), 8, 3600, 500); // 500 bps = 5% max deviation
        oracle.setSecondaryFeed(WETH, address(secondaryEthFeed), 8, 3600);
    }

    function test_GetAssetPrice_NormalizedToWad() public view {
        uint256 priceWad = oracle.getAssetPrice(WETH);
        assertEq(priceWad, 3000 * WAD);
    }

    function test_GetAssetPriceWithConfidence() public view {
        (uint256 priceWad, uint256 confidenceBps) = oracle.getAssetPriceWithConfidence(WETH);
        assertEq(priceWad, 3000 * WAD);
        assertEq(confidenceBps, 9900);
    }

    function test_StaleFeedReverts() public {
        // Warp past heartbeat (3600 seconds)
        vm.warp(block.timestamp + 3601);
        vm.expectRevert();
        oracle.getAssetPrice(WETH);
    }
}
