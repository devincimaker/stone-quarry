// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { PoolKey } from "v4-core/types/PoolKey.sol";
import { Currency} from "v4-core/types/Currency.sol";
import { IPositionManager } from "v4-periphery/interfaces/IPositionManager.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import "./Pebble.sol";
import "./QuarryHook.sol";

contract Quarry {
    Pebble immutable public pebble;
    QuarryHook public hook; 

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    uint256 private constant ethToPair = 2 wei;
    IPositionManager private immutable posm;
    IAllowanceTransfer private immutable permit2;
    IPoolManager private immutable poolManager;

    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;


    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    uint public feeAddress;

    constructor(address _posm, address _permit2, address _poolManager, address _feeAddress) {
        posm = IPositionManager(_posm);
        permit2 = IAllowanceTransfer(_permit2);
        poolManager = IPoolManager(_poolManager);

        
        pebble = new Pebble();
        hook = new QuarryHook();

        _loadLiquidity();
    }

    function _loadLiquidity() internal {
        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(address(pebble));

        uint lpFee = 0;
        uint tickSpacing = 60;

        // PoolKey memory pool = PoolKey({
        //     currency0: currency0,
        //     currency1: currency1,
        //     fee: lpFee,
        //     tickSpacing: tickSpacing,
        //     hooks: address(hook)
        // });


        // Create a pool

        // Add liquidity
    }
}


