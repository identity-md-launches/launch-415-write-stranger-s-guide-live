// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimeLockToken} from "../src/TimeLockToken.sol";
import {TimeLockBank} from "../src/TimeLockBank.sol";

contract FactoryProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "deployment failed");
    }
}

contract FactoryCompatibilityTest is Test {
    FactoryProbe private factory;
    TimeLockToken private token;
    TimeLockBank private bank;

    function setUp() public {
        factory = new FactoryProbe();
        token = TimeLockToken(factory.deploy(type(TimeLockToken).creationCode, bytes32(uint256(1))));
        bytes memory code =
            abi.encodePacked(type(TimeLockBank).creationCode, abi.encode(address(token), 31536000));
        bank = TimeLockBank(factory.deploy(code, bytes32(uint256(2))));
    }

    function test_factoryConstructionMintsOnlyToFactoryAndNeedsNoInitialization() public view {
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(token.balanceOf(address(factory)), 10 ** 27);
        assertEq(token.balanceOf(address(bank)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(address(bank.token()), address(token));
        assertEq(bank.maxLockSeconds(), 31536000);
        assertEq(bank.totalLocked(), 0);
    }

    function test_runtimeSizesAndForbiddenOpcodes() public view {
        _checkRuntime(address(token));
        _checkRuntime(address(bank));
    }

    function test_constructorsRejectETH() public {
        vm.deal(address(this), 2 wei);
        assertEq(_createWithValue(type(TimeLockToken).creationCode), address(0));
        bytes memory code =
            abi.encodePacked(type(TimeLockBank).creationCode, abi.encode(address(token), 31536000));
        assertEq(_createWithValue(code), address(0));
    }

    function test_contractsRejectOrdinaryETHTransfers() public {
        vm.deal(address(this), 2 wei);
        (bool tokenSuccess,) = address(token).call{value: 1}("");
        (bool bankSuccess,) = address(bank).call{value: 1}("");
        assertFalse(tokenSuccess);
        assertFalse(bankSuccess);
    }

    function test_bankHasNoAdminOrRescueSelectorsEvenForFactory() public {
        string[7] memory signatures = [
            "owner()",
            "pause()",
            "transferOwnership(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "rescueTokens(address,uint256)",
            "emergencyWithdraw(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], address(this), 1);
            vm.prank(address(factory));
            (bool success,) = address(bank).call(data);
            assertFalse(success, signatures[i]);
        }
    }

    function _createWithValue(bytes memory code) private returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
    }

    function _checkRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }
}
