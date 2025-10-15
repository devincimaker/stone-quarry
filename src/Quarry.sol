// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency} from "v4-core/src/types/Currency.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { IPoolInitializer_v4 } from "v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "v4-core/test/utils/LiquidityAmounts.sol";

import "./Pebble.sol";
import "./QuarryHook.sol";

contract Quarry {
    Pebble immutable public pebble;
    QuarryHook immutable public hook; 

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

    address public feeAddress;

    constructor(address _posm, address _permit2, address _poolManager, address _feeAddress) payable {
        posm = IPositionManager(_posm);
        permit2 = IAllowanceTransfer(_permit2);
        poolManager = IPoolManager(_poolManager);
        feeAddress = _feeAddress;
 
        pebble = new Pebble(_poolManager);
        hook = new QuarryHook(_poolManager, address(this), address(pebble));
        
        pebble.setHookAddress(address(hook));
        hook.setLoadingLiquidity(true);

        _loadLiquidity();
        
        hook.setLoadingLiquidity(false);
    }

    function _loadLiquidity() internal {
        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(address(pebble));

        uint24 lpFee = 0;
        int24 tickSpacing = 60;

        uint256 token0Amount = 1; // 1 wei
        uint256 token1Amount = 1_000_000_000 * 10 ** 18;

        uint160 startingPrice = 501082896750095888663770159906816;

        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = int24(175020);

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        bytes memory hookData = new bytes(0);

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;

        bytes[] memory params = new bytes[](2);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION),uint8(Actions.SETTLE_PAIR));
        bytes[] memory mintParams = new bytes[](2);
        
        mintParams[0] = abi.encode(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, DEAD_ADDRESS, hookData);
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);
        
        params[0] = abi.encodeWithSelector(
            IPoolInitializer_v4.initializePool.selector,
            pool,
            startingPrice,
            hookData
        );
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 3600
        );

        uint256 valueToPass = amount0Max;
        pebble.approve(address(permit2), type(uint256).max);
        permit2.approve(address(pebble), address(posm), type(uint160).max, type(uint48).max);
    
        posm.multicall{ value: valueToPass }(params);
    }
}

