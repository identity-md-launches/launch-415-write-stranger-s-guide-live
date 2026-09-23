// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TimeLockToken} from "../src/TimeLockToken.sol";

contract TimeLockTokenTest is Test {
    TimeLockToken private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant SUPPLY = 10 ** 27;

    function setUp() public {
        token = new TimeLockToken();
    }

    function test_metadataAndFixedSupply() public view {
        assertEq(token.name(), "Time Lock");
        assertEq(token.symbol(), "LOCK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferAndTransferFromMoveExactAmounts() public {
        assertTrue(token.transfer(ALICE, 100 ether));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 40 ether));
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 40 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.balanceOf(ALICE), 60 ether);
        assertEq(token.balanceOf(BOB), 40 ether);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferInsufficientBalanceReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        token.transfer(ALICE, 1 ether);
        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1 ether)
        );
        token.transferFrom(ALICE, BOB, 1 ether);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noPrivilegedSelectorsForDeployerOrStranger() public {
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "burn(uint256)",
            "setTax(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory payload = abi.encodeWithSignature(signatures[i], ALICE, type(uint128).max);
            (bool deployerSuccess,) = address(token).call(payload);
            assertFalse(deployerSuccess, signatures[i]);
            vm.prank(ALICE);
            (bool outsiderSuccess,) = address(token).call(payload);
            assertFalse(outsiderSuccess, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(ALICE), 0);
        }
    }

    function testFuzz_transfersConserveSupply(uint256 amount, uint256 onward) public {
        amount = bound(amount, 0, SUPPLY);
        onward = bound(onward, 0, amount);
        token.transfer(ALICE, amount);
        vm.prank(ALICE);
        token.transfer(BOB, onward);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount - onward);
        assertEq(token.balanceOf(BOB), onward);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
