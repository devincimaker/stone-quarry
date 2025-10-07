// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Pebble} from "./Pebble.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @title Quarry - Pebble Token Launcher
/// @notice Launches $pebble token and deploys it to Uniswap V4 with liquidity
contract Quarry {
    /* ═══════════════════════════════════════════════════════════ */
    /*                          IMMUTABLES                         */
    /* ═══════════════════════════════════════════════════════════ */

    /// @notice Uniswap V4 Position Manager for liquidity operations
    IPositionManager private immutable posm;
    /// @notice Permit2 contract for token approvals
    IAllowanceTransfer private immutable permit2;
    /// @notice Uniswap V4 Pool Manager for pool operations
    IPoolManager private immutable poolManager;
    /// @notice Dead address for burning LP tokens
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /* ═══════════════════════════════════════════════════════════ */
    /*                       STATE VARIABLES                       */
    /* ═══════════════════════════════════════════════════════════ */

    /// @notice The deployed Pebble token
    Pebble public immutable pebbleToken;
    /// @notice Whether liquidity has been deployed
    bool public launched;
    /// @notice The Uniswap V4 hook address (optional)
    address public immutable hookAddress;

    /* ═══════════════════════════════════════════════════════════ */
    /*                          EVENTS                             */
    /* ═══════════════════════════════════════════════════════════ */

    event PebbleLaunched(address indexed token, address indexed pool);

    /* ═══════════════════════════════════════════════════════════ */
    /*                          ERRORS                             */
    /* ═══════════════════════════════════════════════════════════ */

    error AlreadyLaunched();
    error NotLaunched();

    /* ═══════════════════════════════════════════════════════════ */
    /*                        CONSTRUCTOR                          */
    /* ═══════════════════════════════════════════════════════════ */

    /// @notice Constructor initializes Uniswap V4 dependencies and deploys Pebble token
    /// @param _posm Uniswap V4 Position Manager address
    /// @param _permit2 Permit2 contract address
    /// @param _poolManager Uniswap V4 Pool Manager address
    /// @param _hookAddress Optional hook address (address(0) for no hook)
    constructor(address _posm, address _permit2, address _poolManager, address _hookAddress) {
        posm = IPositionManager(_posm);
        permit2 = IAllowanceTransfer(_permit2);
        poolManager = IPoolManager(_poolManager);
        hookAddress = _hookAddress;
        
        // Deploy the Pebble token
        pebbleToken = new Pebble();
    }

    /* ═══════════════════════════════════════════════════════════ */
    /*                      LAUNCH FUNCTIONS                       */
    /* ═══════════════════════════════════════════════════════════ */

    /// @notice Launches the Pebble token into Uniswap V4 with liquidity pool
    /// @dev Creates pool with 1 billion tokens paired against minimal ETH
    function launch() external payable {
        if (launched) revert AlreadyLaunched();
        
        launched = true;

        // Load initial liquidity into Uniswap V4
        _loadLiquidity(address(pebbleToken));

        emit PebbleLaunched(address(pebbleToken), address(poolManager));
    }

    /* ═══════════════════════════════════════════════════════════ */
    /*                    INTERNAL FUNCTIONS                       */
    /* ═══════════════════════════════════════════════════════════ */

    /// @notice Internal function to load initial liquidity into the Uniswap V4 pool
    /// @param _token Address of the Pebble ERC20 token
    /// @dev Creates pool, initializes with starting price, and adds liquidity
    function _loadLiquidity(address _token) internal {
        // Create the pool with ETH (currency0) and PEBBLE (currency1)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(_token); // Pebble Token

        uint24 lpFee = 0;
        int24 tickSpacing = 60;

        uint256 token0Amount = 1; // 1 wei ETH
        uint256 token1Amount = 1_000_000_000 * 10 ** 18; // 1B PEBBLE

        // Starting price: 10e18 ETH = 1_000_000_000e18 PEBBLE
        uint160 startingPrice = 501082896750095888663770159906816;

        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = int24(175020);

        PoolKey memory key = PoolKey(currency0, currency1, lpFee, tickSpacing, IHooks(hookAddress));
        bytes memory hookData = new bytes(0);

        // Hardcoded liquidity amount (calculated from LiquidityAmounts.getLiquidityForAmounts)
        uint128 liquidity = 158372218983990412488087;

        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;

        (bytes memory actions, bytes[] memory mintParams) =
            _mintLiquidityParams(key, tickLower, tickUpper, liquidity, amount0Max, amount1Max, DEAD_ADDRESS, hookData);

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encodeWithSelector(posm.initializePool.selector, key, startingPrice, hookData);

        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        uint256 valueToPass = amount0Max;
        permit2.approve(_token, address(posm), type(uint160).max, type(uint48).max);

        posm.multicall{value: valueToPass}(params);
    }

    /// @notice Creates parameters for minting liquidity in Uniswap V4
    /// @param poolKey The pool key for the liquidity position
    /// @param _tickLower Lower tick boundary
    /// @param _tickUpper Upper tick boundary
    /// @param liquidity Amount of liquidity to mint
    /// @param amount0Max Maximum amount of token0 to use
    /// @param amount1Max Maximum amount of token1 to use
    /// @param recipient Address to receive the liquidity position
    /// @param hookData Additional data for hooks
    /// @return Encoded actions and parameters for position manager
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }

    receive() external payable {}
}
