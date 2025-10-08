// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "./Pebble.sol";

contract Quarry {
    Pebble immutable pebble;

    constructor() {
        pebble = new Pebble();
    }
}


