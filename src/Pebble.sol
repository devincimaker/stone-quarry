// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @title Pebble - Simple ERC20 Token
/// @notice The $pebble token
contract Pebble is ERC20 {
    string private _name;
    string private _symbol;

    constructor() {
        _name = "Pebble";
        _symbol = "PEBBLE";
        
        // Mint initial supply: 1 billion tokens
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }
}

