// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { PoolKey } from "v4-core/types/PoolKey.sol";
import { Currency} from "v4-core/types/Currency.sol";
import { IPositionManager } from "v4-periphery/interfaces/IPositionManager.sol";

import "./Pebble.sol";
import "./Hook.sol";

contract Quarry {
    Pebble immutable pebble;
    Hook public hook; 

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    uint256 private constant ethToPair = 2 wei;
    IPositionManager private immutable posm;

    constructor() {
        pebble = new Pebble();
        hook = new Hook();

        _loadLiquidity();
    }

    function _loadLiquidity() internal {
        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(address(pebble));

        uint lpFee = 0;
        uint tickSpacing = 60;

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: address(hook)
        });
    }
}


