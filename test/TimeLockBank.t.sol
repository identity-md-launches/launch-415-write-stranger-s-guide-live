// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TimeLockToken} from "../src/TimeLockToken.sol";
import {TimeLockBank} from "../src/TimeLockBank.sol";

contract TimeLockBankTest is Test {
    TimeLockToken private token;
    TimeLockBank private bank;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant CAP = 365 days;
    uint256 private constant FUNDS = 1_000_000 ether;

    event Deposited(uint256 indexed lockId, address indexed owner, uint256 amount, uint64 unlockAt);
    event Extended(
        uint256 indexed lockId, address indexed owner, uint64 previousUnlockAt, uint64 newUnlockAt
    );
    event Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount);

    function setUp() public {
        vm.warp(1_800_000_000);
        token = new TimeLockToken();
        bank = new TimeLockBank(address(token), CAP);
        token.transfer(ALICE, FUNDS);
        token.transfer(BOB, FUNDS);
        vm.prank(ALICE);
        token.approve(address(bank), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(bank), type(uint256).max);
    }

    function test_constructorAndEmptyViews() public view {
        assertEq(address(bank.token()), address(token));
        assertEq(bank.maxLockSeconds(), CAP);
        assertEq(bank.totalLocked(), 0);
        assertEq(bank.nextLockId(), 1);
        assertEq(bank.locksOf(ALICE).length, 0);
    }

    function test_constructorRejectsZeroToken() public {
        vm.expectRevert(TimeLockBank.InvalidToken.selector);
        new TimeLockBank(address(0), CAP);
    }

    function test_constructorRejectsTokenWithoutCode() public {
        vm.expectRevert(TimeLockBank.InvalidToken.selector);
        new TimeLockBank(ALICE, CAP);
    }

    function test_constructorRejectsZeroCap() public {
        vm.expectRevert(TimeLockBank.InvalidMaxLockSeconds.selector);
        new TimeLockBank(address(token), 0);
    }

    function test_depositIndexesOwnersAndEmitsEvent() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1 days);
        vm.expectEmit(true, true, false, true, address(bank));
        emit Deposited(1, ALICE, 3 ether, unlockAt);
        uint256 first = _deposit(ALICE, 3 ether, unlockAt);
        uint256 second = _deposit(BOB, 5 ether, unlockAt);
        uint256 third = _deposit(ALICE, 7 ether, unlockAt);
        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(third, 3);
        uint256[] memory ids = bank.locksOf(ALICE);
        assertEq(ids.length, 2);
        assertEq(ids[0], first);
        assertEq(ids[1], third);
        assertEq(bank.locksOf(BOB)[0], second);
        TimeLockBank.Lock memory position = bank.lock(first);
        assertEq(position.owner, ALICE);
        assertEq(position.amount, 3 ether);
        assertEq(position.unlockAt, unlockAt);
        assertFalse(position.withdrawn);
        assertEq(bank.totalLocked(), 15 ether);
        assertEq(token.balanceOf(address(bank)), 15 ether);
        assertEq(token.balanceOf(ALICE), FUNDS - 10 ether);
        assertEq(token.balanceOf(BOB), FUNDS - 5 ether);
    }

    function test_zeroAmountReverts() public {
        vm.expectRevert(TimeLockBank.ZeroAmount.selector);
        _deposit(ALICE, 0, uint64(vm.getBlockTimestamp() + 1));
        _assertEmptyBank();
    }

    function test_depositAtNowOrInPastReverts() public {
        vm.expectRevert(TimeLockBank.UnlockNotFuture.selector);
        _deposit(ALICE, 1 ether, uint64(vm.getBlockTimestamp()));
        vm.expectRevert(TimeLockBank.UnlockNotFuture.selector);
        _deposit(ALICE, 1 ether, uint64(vm.getBlockTimestamp() - 1));
        _assertEmptyBank();
    }

    function test_depositCapInclusiveAndOneSecondBeyondReverts() public {
        vm.expectRevert(TimeLockBank.LockTooLong.selector);
        _deposit(ALICE, 1 ether, uint64(vm.getBlockTimestamp() + CAP + 1));
        _assertEmptyBank();
        uint256 id = _deposit(ALICE, 1 ether, uint64(vm.getBlockTimestamp() + CAP));
        assertEq(bank.lock(id).unlockAt, vm.getBlockTimestamp() + CAP);
    }

    function test_depositWithoutAllowanceRollsBackAllState() public {
        vm.prank(ALICE);
        token.approve(address(bank), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(bank), 0, 1 ether
            )
        );
        _deposit(ALICE, 1 ether, uint64(vm.getBlockTimestamp() + 1));
        _assertEmptyBank();
        assertEq(token.balanceOf(ALICE), FUNDS);
    }

    function test_depositBeyondBalanceRollsBackAllState() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, FUNDS, FUNDS + 1)
        );
        _deposit(ALICE, FUNDS + 1, uint64(vm.getBlockTimestamp() + 1));
        _assertEmptyBank();
    }

    function test_earlyWithdrawRevertsAtOneSecondBeforeUnlock() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1 days);
        uint256 id = _deposit(ALICE, 5 ether, unlockAt);
        vm.warp(unlockAt - 1);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.StillLocked.selector, id, unlockAt));
        bank.withdraw(id);
        assertFalse(bank.lock(id).withdrawn);
        assertEq(bank.totalLocked(), 5 ether);
        assertEq(token.balanceOf(address(bank)), 5 ether);
    }

    function test_exactUnlockBoundaryWithdrawsFullAmountAndEmitsEvent() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1 days);
        uint256 id = _deposit(ALICE, 5 ether, unlockAt);
        vm.warp(unlockAt);
        vm.expectEmit(true, true, false, true, address(bank));
        emit Withdrawn(id, ALICE, 5 ether);
        vm.prank(ALICE);
        bank.withdraw(id);
        TimeLockBank.Lock memory position = bank.lock(id);
        assertTrue(position.withdrawn);
        assertEq(position.amount, 5 ether);
        assertEq(position.owner, ALICE);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(token.balanceOf(ALICE), FUNDS);
        assertEq(bank.locksOf(ALICE)[0], id);
    }

    function test_doubleWithdrawReverts() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1);
        uint256 id = _deposit(ALICE, 1 ether, unlockAt);
        vm.warp(unlockAt);
        vm.startPrank(ALICE);
        bank.withdraw(id);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.AlreadyWithdrawn.selector, id));
        bank.withdraw(id);
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), FUNDS);
        assertEq(bank.totalLocked(), 0);
    }

    function test_nonOwnerWithdrawAndExtendRevert() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1);
        uint256 id = _deposit(ALICE, 1 ether, unlockAt);
        vm.warp(unlockAt);
        vm.startPrank(BOB);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.NotLockOwner.selector, id));
        bank.withdraw(id);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.NotLockOwner.selector, id));
        bank.extend(id, unlockAt + 1);
        vm.stopPrank();
        assertEq(bank.lock(id).unlockAt, unlockAt);
        assertFalse(bank.lock(id).withdrawn);
        assertEq(token.balanceOf(BOB), FUNDS);
    }

    function test_unknownLockViewsAndMutationsRevert() public {
        for (uint256 id; id < 2; ++id) {
            vm.expectRevert(abi.encodeWithSelector(TimeLockBank.UnknownLock.selector, id));
            bank.lock(id);
            vm.expectRevert(abi.encodeWithSelector(TimeLockBank.UnknownLock.selector, id));
            bank.withdraw(id);
            vm.expectRevert(abi.encodeWithSelector(TimeLockBank.UnknownLock.selector, id));
            bank.extend(id, uint64(vm.getBlockTimestamp() + 1));
        }
    }

    function test_extendCannotShortenOrKeepSameTime() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1 days);
        uint256 id = _deposit(ALICE, 1 ether, unlockAt);
        vm.startPrank(ALICE);
        vm.expectRevert(TimeLockBank.MustExtend.selector);
        bank.extend(id, unlockAt - 1);
        vm.expectRevert(TimeLockBank.MustExtend.selector);
        bank.extend(id, unlockAt);
        vm.stopPrank();
        assertEq(bank.lock(id).unlockAt, unlockAt);
    }

    function test_extendCapMeasuredFromNowInclusive() public {
        uint64 oldUnlockAt = uint64(vm.getBlockTimestamp() + CAP);
        uint256 id = _deposit(ALICE, 5 ether, oldUnlockAt);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint64 newUnlockAt = uint64(vm.getBlockTimestamp() + CAP);
        vm.prank(ALICE);
        vm.expectRevert(TimeLockBank.LockTooLong.selector);
        bank.extend(id, newUnlockAt + 1);
        assertEq(bank.lock(id).unlockAt, oldUnlockAt);

        vm.expectEmit(true, true, false, true, address(bank));
        emit Extended(id, ALICE, oldUnlockAt, newUnlockAt);
        vm.prank(ALICE);
        bank.extend(id, newUnlockAt);
        assertEq(bank.lock(id).unlockAt, newUnlockAt);
        assertEq(bank.totalLocked(), 5 ether);
        assertEq(token.balanceOf(address(bank)), 5 ether);
        vm.warp(oldUnlockAt);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.StillLocked.selector, id, newUnlockAt));
        bank.withdraw(id);
        vm.warp(newUnlockAt);
        vm.prank(ALICE);
        bank.withdraw(id);
        assertEq(token.balanceOf(ALICE), FUNDS);
    }

    function test_maturedLockMayExtendButOnlyIntoFuture() public {
        uint64 oldUnlockAt = uint64(vm.getBlockTimestamp() + 1);
        uint256 id = _deposit(ALICE, 1 ether, oldUnlockAt);
        vm.warp(oldUnlockAt + 2);
        vm.startPrank(ALICE);
        vm.expectRevert(TimeLockBank.UnlockNotFuture.selector);
        bank.extend(id, oldUnlockAt + 1);
        vm.expectRevert(TimeLockBank.UnlockNotFuture.selector);
        bank.extend(id, uint64(vm.getBlockTimestamp()));
        bank.extend(id, uint64(vm.getBlockTimestamp() + 1));
        vm.stopPrank();
        assertEq(bank.lock(id).unlockAt, vm.getBlockTimestamp() + 1);
    }

    function test_withdrawnLockCannotExtend() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1);
        uint256 id = _deposit(ALICE, 1 ether, unlockAt);
        vm.warp(unlockAt);
        vm.startPrank(ALICE);
        bank.withdraw(id);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.AlreadyWithdrawn.selector, id));
        bank.extend(id, unlockAt + 1);
        vm.stopPrank();
    }

    function test_directDonationCreatesNoLockOrWithdrawalRight() public {
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + 1);
        uint256 id = _deposit(ALICE, 1 ether, unlockAt);
        token.transfer(address(bank), 7 ether);
        assertEq(bank.totalLocked(), 1 ether);
        assertEq(token.balanceOf(address(bank)), 8 ether);
        assertEq(bank.locksOf(address(this)).length, 0);
        vm.warp(unlockAt);
        vm.prank(ALICE);
        bank.withdraw(id);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 7 ether);
    }

    function test_maxUintCapDoesNotOverflowValidation() public {
        TimeLockBank largeCapBank = new TimeLockBank(address(token), type(uint256).max);
        token.approve(address(largeCapBank), 1);
        uint256 id = largeCapBank.deposit(1, type(uint64).max);
        assertEq(largeCapBank.lock(id).unlockAt, type(uint64).max);
    }

    function testFuzz_depositsAndWithdrawalsConserveTokens(
        uint256 aliceAmount,
        uint256 bobAmount,
        uint256 duration,
        bool bobFirst
    ) public {
        aliceAmount = bound(aliceAmount, 1, FUNDS);
        bobAmount = bound(bobAmount, 1, FUNDS);
        duration = bound(duration, 1, CAP);
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + duration);
        uint256 a = _deposit(ALICE, aliceAmount, unlockAt);
        uint256 b = _deposit(BOB, bobAmount, unlockAt);
        assertEq(bank.totalLocked(), aliceAmount + bobAmount);
        assertEq(token.balanceOf(address(bank)), bank.totalLocked());
        vm.warp(unlockAt);
        vm.prank(bobFirst ? BOB : ALICE);
        bank.withdraw(bobFirst ? b : a);
        assertEq(bank.totalLocked(), bobFirst ? aliceAmount : bobAmount);
        assertEq(token.balanceOf(address(bank)), bank.totalLocked());
        vm.prank(bobFirst ? ALICE : BOB);
        bank.withdraw(bobFirst ? a : b);
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(token.balanceOf(ALICE), FUNDS);
        assertEq(token.balanceOf(BOB), FUNDS);
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function testFuzz_extensionPreservesAmountAndEnforcesNewBoundary(uint256 amount, uint256 delay) public {
        amount = bound(amount, 1, FUNDS);
        delay = bound(delay, 2, CAP);
        uint256 id = _deposit(ALICE, amount, uint64(vm.getBlockTimestamp() + 1));
        uint64 newUnlockAt = uint64(vm.getBlockTimestamp() + delay);
        vm.prank(ALICE);
        bank.extend(id, newUnlockAt);
        assertEq(bank.lock(id).amount, amount);
        assertEq(bank.totalLocked(), amount);
        assertEq(token.balanceOf(address(bank)), amount);
        vm.warp(newUnlockAt - 1);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(TimeLockBank.StillLocked.selector, id, newUnlockAt));
        bank.withdraw(id);
        vm.warp(newUnlockAt);
        vm.prank(ALICE);
        bank.withdraw(id);
        assertEq(token.balanceOf(ALICE), FUNDS);
        assertEq(bank.totalLocked(), 0);
    }

    function _deposit(address owner, uint256 amount, uint64 unlockAt) private returns (uint256) {
        vm.prank(owner);
        return bank.deposit(amount, unlockAt);
    }

    function _assertEmptyBank() private view {
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(bank.nextLockId(), 1);
        assertEq(bank.locksOf(ALICE).length, 0);
    }
}
