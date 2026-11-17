// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {FlashEngine} from "../src/core/FlashEngine.sol";
import {SolisDebtToken} from "../src/tokens/SolisDebtToken.sol";
import {LatticeAccessController} from "../src/governance/LatticeAccessController.sol";
import {MockFlashReceiver} from "./mocks/MockFlashReceiver.sol";

contract FlashEngineTest is Test {
    LatticeAccessController public access;
    SolisDebtToken public debtToken;
    FlashEngine public engine;
    MockFlashReceiver public receiver;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function setUp() public {
        access = new LatticeAccessController(address(this));
        debtToken = new SolisDebtToken(address(this));

        engine = new FlashEngine(address(access), address(debtToken), address(this));
        receiver = new MockFlashReceiver(address(debtToken));

        // Fund FlashEngine with liquidity for flash loans
        debtToken.mint(address(engine), 100000 * WAD, RAY);
        // Mint extra to receiver to cover fees
        debtToken.mint(address(receiver), 100 * WAD, RAY);
    }

    function test_ExecuteFlashMint_Success() public {
        uint256 flashAmount = 1000 * WAD;
        bool ok = engine.executeFlashMint(address(receiver), flashAmount, "");
        assertTrue(ok);
    }

    function test_ExecuteFlashMint_FailCallbackReverts() public {
        receiver.setShouldFail(true);
        vm.expectRevert();
        engine.executeFlashMint(address(receiver), 1000 * WAD, "");
    }
}
