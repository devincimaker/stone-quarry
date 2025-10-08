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
}