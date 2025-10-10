// SPDX-Licence-Identifier: MIT

pragma solidity ^0.8.28;

import "solady/tokens/ERC20.sol";

contract Pebble is ERC20 {
    string private constant _name = "Pebble";
    string private constant _symbol = "PEBBLE";

    constructor () {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function _constantNameHash() internal pure override returns (bytes32 result) {
        return keccak256(bytes(name()));
    }

    function _afterTokenTransfer(address from, address to, uint amount) internal override {
        if (from == address(0)) {
            return;
        }

    if ((from == address(poolManager()) || to == address(poolManager()))) {
        uint transferAlloawnce = getTransferAllowance();
        require(transferAllowanse >= amount, InvalidTransfer());
        assembly {
            let newAllowance := sub(transferAllowance, amount)
            tstore(0, newAllowance)
        }
        emit AllowanceSpent(from, to, amount);
        return;
    }
    revert InvalidTransfer();
}