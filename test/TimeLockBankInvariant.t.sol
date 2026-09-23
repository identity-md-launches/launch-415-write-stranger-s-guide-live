// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimeLockToken} from "../src/TimeLockToken.sol";
import {TimeLockBank} from "../src/TimeLockBank.sol";

contract BankHandler is Test {
    TimeLockToken public immutable token;
    TimeLockBank public immutable bank;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11)];
    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(TimeLockToken token_, TimeLockBank bank_) {
        token = token_;
        bank = bank_;
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            token.approve(address(bank), type(uint256).max);
        }
    }

    function deposit(uint256 who, uint256 amount, uint256 duration) external {
        address actor = actors[who % actors.length];
        uint256 balance = token.balanceOf(actor);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        duration = bound(duration, 1, bank.maxLockSeconds());
        uint64 unlockAt = uint64(vm.getBlockTimestamp() + duration);
        vm.prank(actor);
        bank.deposit(amount, unlockAt);
        ghostDeposited += amount;
    }

    function withdraw(uint256 seed) external {
        uint256 next = bank.nextLockId();
        if (next == 1) return;
        uint256 id = 1 + seed % (next - 1);
        TimeLockBank.Lock memory position = bank.lock(id);
        if (position.withdrawn || position.unlockAt > vm.getBlockTimestamp()) return;
        _withdraw(id, position);
    }

    function extend(uint256 seed, uint256 delay) external {
        uint256 next = bank.nextLockId();
        if (next == 1) return;
        uint256 id = 1 + seed % (next - 1);
        TimeLockBank.Lock memory position = bank.lock(id);
        if (position.withdrawn) return;
        uint256 minTime = uint256(position.unlockAt) + 1;
        if (minTime <= vm.getBlockTimestamp()) minTime = vm.getBlockTimestamp() + 1;
        uint256 maxTime = vm.getBlockTimestamp() + bank.maxLockSeconds();
        if (minTime > maxTime) return;
        uint64 newUnlockAt = uint64(bound(delay, minTime, maxTime));
        vm.prank(position.owner);
        bank.extend(id, newUnlockAt);
    }

    function advanceTime(uint256 delta) external {
        vm.warp(vm.getBlockTimestamp() + bound(delta, 1, 30 days));
    }

    function withdrawAll() external {
        vm.warp(vm.getBlockTimestamp() + bank.maxLockSeconds());
        uint256 next = bank.nextLockId();
        for (uint256 id = 1; id < next; ++id) {
            TimeLockBank.Lock memory position = bank.lock(id);
            if (!position.withdrawn) _withdraw(id, position);
        }
    }

    function _withdraw(uint256 id, TimeLockBank.Lock memory position) private {
        vm.prank(position.owner);
        bank.withdraw(id);
        ghostWithdrawn += position.amount;
    }
}

contract TimeLockBankInvariantTest is Test {
    TimeLockToken private token;
    TimeLockBank private bank;
    BankHandler private handler;
    uint256 private constant FUNDS = 1_000 ether;

    function setUp() public {
        vm.warp(1_800_000_000);
        token = new TimeLockToken();
        bank = new TimeLockBank(address(token), 365 days);
        handler = new BankHandler(token, bank);
        for (uint256 i; i < 3; ++i) {
            token.transfer(handler.actors(i), FUNDS);
        }
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = BankHandler.deposit.selector;
        selectors[1] = BankHandler.withdraw.selector;
        selectors[2] = BankHandler.extend.selector;
        selectors[3] = BankHandler.advanceTime.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_conservationAndOwnerAccounting() public view {
        uint256 activeSum;
        uint256 idCount;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256[] memory ids = bank.locksOf(actor);
            uint256 ownedActive;
            for (uint256 j; j < ids.length; ++j) {
                if (j > 0) assertGt(ids[j], ids[j - 1]);
                TimeLockBank.Lock memory position = bank.lock(ids[j]);
                assertEq(position.owner, actor);
                assertGt(position.amount, 0);
                if (!position.withdrawn) ownedActive += position.amount;
            }
            assertEq(token.balanceOf(actor) + ownedActive, FUNDS);
            activeSum += ownedActive;
            idCount += ids.length;
        }
        assertEq(bank.nextLockId(), idCount + 1);
        assertEq(bank.totalLocked(), activeSum);
        assertEq(bank.totalLocked(), handler.ghostDeposited() - handler.ghostWithdrawn());
        assertEq(token.balanceOf(address(bank)), bank.totalLocked());
        assertEq(token.totalSupply(), 10 ** 27);
    }

    function afterInvariant() public {
        handler.withdrawAll();
        assertEq(bank.totalLocked(), 0);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(handler.ghostDeposited(), handler.ghostWithdrawn());
        for (uint256 i; i < 3; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), FUNDS);
        }
    }
}
