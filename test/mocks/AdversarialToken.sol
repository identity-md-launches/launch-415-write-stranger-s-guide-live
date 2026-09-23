// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TimeLockBank} from "../../src/TimeLockBank.sol";

/// @dev Test-only token that can fail after moving balances or attempt arbitrary bank callbacks.
contract AdversarialToken is ERC20 {
    enum Mode {
        Normal,
        ReturnFalse,
        Revert,
        NoReturn
    }

    Mode public inboundMode;
    Mode public outboundMode;
    TimeLockBank public bank;
    bytes public callback;
    bytes public callbackResult;
    bool public callbackSuccess;
    uint256 public callbackCount;

    error DeliberateFailure();

    constructor() ERC20("Test Only", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function configure(TimeLockBank bank_, Mode inbound, Mode outbound, bytes memory data) external {
        bank = bank_;
        inboundMode = inbound;
        outboundMode = outbound;
        callback = data;
    }

    function depositOwned(uint256 amount, uint64 unlockAt) external returns (uint256) {
        _approve(address(this), address(bank), amount);
        return bank.deposit(amount, unlockAt);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        _callback();
        return _respond(outboundMode);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        _callback();
        return _respond(inboundMode);
    }

    function _callback() private {
        if (callback.length != 0) {
            bytes memory data = callback;
            delete callback;
            ++callbackCount;
            (callbackSuccess, callbackResult) = address(bank).call(data);
        }
    }

    function _respond(Mode mode) private pure returns (bool) {
        if (mode == Mode.ReturnFalse) return false;
        if (mode == Mode.Revert) revert DeliberateFailure();
        if (mode == Mode.NoReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }
}
