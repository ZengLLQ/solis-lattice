// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransientSlot} from "../src/libraries/TransientSlot.sol";

contract TransientSlotCaller {
    function acquireLock() external {
        TransientSlot.lock();
    }

    function releaseLock() external {
        TransientSlot.unlock();
    }

    function tryReentrantLock() external {
        TransientSlot.lock();
        TransientSlot.lock(); // Should revert
    }

    function runBalancedFlashScope() external {
        TransientSlot.recordFlashDebtDelta(100);
        TransientSlot.recordFlashDebtDelta(-100);
        TransientSlot.assertFlashSettled();
    }

    function runUnbalancedFlashScope() external {
        TransientSlot.recordFlashDebtDelta(100);
        TransientSlot.assertFlashSettled(); // Should revert
    }
}

contract TransientSlotTest is Test {
    TransientSlotCaller public caller;

    function setUp() public {
        caller = new TransientSlotCaller();
    }

    function test_TransientLock_Success() public {
        caller.acquireLock();
        caller.releaseLock();
    }

    function test_TransientLock_ReentrantReverts() public {
        vm.expectRevert(TransientSlot.ReentrantCall.selector);
        caller.tryReentrantLock();
    }

    function test_TransientFlashAccounting_Settled() public {
        caller.runBalancedFlashScope();
    }

    function test_TransientFlashAccounting_UnbalancedReverts() public {
        vm.expectRevert();
        caller.runUnbalancedFlashScope();
    }
}
