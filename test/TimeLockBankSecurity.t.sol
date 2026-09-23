// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TimeLockBank} from "../src/TimeLockBank.sol";
import {AdversarialToken} from "./mocks/AdversarialToken.sol";

contract TimeLockBankSecurityTest is Test {
    AdversarialToken private token;
    TimeLockBank private bank;
    address private constant ALICE = address(0xA11CE);
    uint256 private constant CAP = 365 days;

    function setUp() public {
        vm.warp(1_800_000_000);
        token = new AdversarialToken();
        bank = new TimeLockBank(address(token), CAP);
        token.mint(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(address(bank), 100 ether);
    }

    function test_falseReturningDepositRollsBackTokenAndBank() public {
        _failedDeposit(AdversarialToken.Mode.ReturnFalse);
    }

    function test_revertingDepositRollsBackTokenAndBank() public {
        _failedDeposit(AdversarialToken.Mode.Revert);
    }

    function test_falseReturningWithdrawalCanBeRetried() public {
        _failedWithdrawal(AdversarialToken.Mode.ReturnFalse);
    }

    function test_revertingWithdrawalCanBeRetried() public {
        _failedWithdrawal(AdversarialToken.Mode.Revert);
    }

    function test_noReturnTokenWorksThroughSafeERC20() public {
        token.configure(bank, AdversarialToken.Mode.NoReturn, AdversarialToken.Mode.NoReturn, "");
        uint256 id = _deposit();
        assertEq(bank.totalLocked(), 10 ether);
        assertEq(token.balanceOf(address(bank)), 10 ether);
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(ALICE);
        bank.withdraw(id);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function test_reentrantDepositDuringDepositIsBlocked() public {
        _reentrancy(false, 0);
    }

    function test_reentrantWithdrawDuringDepositIsBlocked() public {
        _reentrancy(false, 1);
    }

    function test_reentrantExtendDuringDepositIsBlocked() public {
        _reentrancy(false, 2);
    }

    function test_reentrantDepositDuringWithdrawIsBlocked() public {
        _reentrancy(true, 0);
    }

    function test_reentrantWithdrawDuringWithdrawIsBlocked() public {
        _reentrancy(true, 1);
    }

    function test_reentrantExtendDuringWithdrawIsBlocked() public {
        _reentrancy(true, 2);
    }

    function _failedDeposit(AdversarialToken.Mode mode) private {
        token.configure(bank, mode, AdversarialToken.Mode.Normal, "");
        _expectTransferFailure(mode);
        _deposit();
        assertEq(bank.nextLockId(), 1);
        assertEq(bank.locksOf(ALICE).length, 0);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.allowance(ALICE, address(bank)), 100 ether);
        // A failed transfer must also roll back the reentrancy guard and ID counter.
        token.configure(bank, AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal, "");
        assertEq(_deposit(), 1);
    }

    function _failedWithdrawal(AdversarialToken.Mode mode) private {
        uint256 id = _deposit();
        vm.warp(vm.getBlockTimestamp() + 1);
        token.configure(bank, AdversarialToken.Mode.Normal, mode, "");
        vm.prank(ALICE);
        _expectTransferFailure(mode);
        bank.withdraw(id);
        assertFalse(bank.lock(id).withdrawn);
        assertEq(bank.totalLocked(), 10 ether);
        assertEq(token.balanceOf(address(bank)), 10 ether);
        assertEq(token.balanceOf(ALICE), 90 ether);
        token.configure(bank, AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal, "");
        vm.prank(ALICE);
        bank.withdraw(id);
        assertTrue(bank.lock(id).withdrawn);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function _reentrancy(bool duringWithdrawal, uint256 action) private {
        token.configure(bank, AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal, "");
        token.mint(address(token), 6 ether);
        uint256 attackId = token.depositOwned(5 ether, uint64(vm.getBlockTimestamp() + 1));
        vm.prank(address(token));
        token.approve(address(bank), 1 ether);
        uint256 aliceId = _deposit();
        vm.warp(vm.getBlockTimestamp() + 1);
        uint64 later = uint64(vm.getBlockTimestamp() + 1);
        bytes memory data;
        if (action == 0) data = abi.encodeCall(bank.deposit, (1, later));
        if (action == 1) data = abi.encodeCall(bank.withdraw, (attackId));
        if (action == 2) data = abi.encodeCall(bank.extend, (attackId, later));
        token.configure(bank, AdversarialToken.Mode.Normal, AdversarialToken.Mode.Normal, data);
        if (duringWithdrawal) {
            vm.prank(ALICE);
            bank.withdraw(aliceId);
        } else {
            _deposit();
        }
        assertEq(token.callbackCount(), 1);
        assertFalse(token.callbackSuccess());
        assertEq(
            token.callbackResult(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
        assertFalse(bank.lock(attackId).withdrawn);
        assertEq(bank.lock(attackId).unlockAt, vm.getBlockTimestamp());
        assertEq(bank.totalLocked(), duringWithdrawal ? 5 ether : 25 ether);
        assertEq(token.balanceOf(address(bank)), bank.totalLocked());
    }

    function _deposit() private returns (uint256) {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1);
        vm.prank(ALICE);
        return bank.deposit(10 ether, unlockAt);
    }

    function _expectTransferFailure(AdversarialToken.Mode mode) private {
        if (mode == AdversarialToken.Mode.ReturnFalse) {
            vm.expectRevert(
                abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token))
            );
        } else {
            vm.expectRevert(AdversarialToken.DeliberateFailure.selector);
        }
    }
}
