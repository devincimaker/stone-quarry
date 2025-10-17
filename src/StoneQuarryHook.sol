// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import "./Pebble.sol";
import "./IStoneQuarry.sol";

contract StoneQuarryHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int128;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice Total basis points for percentage calculations
    uint128 private constant TOTAL_BIPS = 10000;
    /// @notice Default fee rate (10%)
    uint128 private constant FEE = 1000;
    /// @notice Maximum price limit for swaps
    uint160 private constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;
    /// @notice The address for the stone quarry
    address public immutable quarryAddress;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Flag to prevent recursive fee collection during internal swaps
    bool private processingFees;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    error NotQuarry();
    error ExactOutputNotAllowed();

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
        
    /// @notice Constructor initializes the hook with required dependencies
    /// @param _poolManager The Uniswap V4 Pool Manager interface
    /// @param _quarryAddress The NFTStrategyFactory contract
    constructor(
        address _poolManager,
        address _quarryAddress
    ) BaseHook(IPoolManager(_poolManager)) {
        quarryAddress = _quarryAddress;
    }

    /// @notice Returns the hook's permissions for the Uniswap V4 pool
    /// @return Hooks.Permissions struct indicating which hooks are enabled
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Validates initialization of a new pool
    /// @return Selector indicating successful hook execution
    /// @dev Validates call is from the quarry
    function _beforeInitialize(address, PoolKey calldata, uint160) internal view override returns (bytes4) {
        if (!IStoneQuarry(quarryAddress).loadingLiquidity()) {
            revert NotQuarry();
        }
        return BaseHook.beforeInitialize.selector;
    }

    /// @notice Validates liquidity addition to a pool
    /// @param key The pool key containing currency pair information
    /// @param delta The balance changes from the liquidity addition
    /// @return Hook selector and zero delta
    /// @dev Only allows liquidity addition during factory loading, sets transfer allowance
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (!IStoneQuarry(quarryAddress).loadingLiquidity()) {
            revert NotQuarry();
        } else {
            // we are loading liquidity so admit a transfer allowance
            // safe casting, liquidity additions are -values
            Pebble(Currency.unwrap(key.currency1)).increaseTransferAllowance(uint256(int256(-delta.amount1())));
        }
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @notice Processes swap events and takes the swap fee
    /// @param key The pool key containing token pair and fee information
    /// @param params Swap parameters including direction and amount
    /// @param delta Balance changes resulting from the swap
    /// @return Hook selector and fee amount taken
    /// @dev Calculates fees, takes fee from swap, converts to ETH if needed, and sends to quarry
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Skip fee processing if we're doing an internal swap to convert fees
        // But still need to handle Pebble transfer allowance
        if (processingFees) {
            uint256 pebbleAmount =
                delta.amount1() < 0 ? uint256(int256(-delta.amount1())) : uint256(int256(delta.amount1()));
            Pebble(Currency.unwrap(key.currency1)).increaseTransferAllowance(pebbleAmount);
            return (BaseHook.afterSwap.selector, 0);
        }

        if (params.amountSpecified > 0) {
            revert ExactOutputNotAllowed();
        }
        
        // Calculate fee based on the swap amount
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        if (swapAmount < 0) swapAmount = -swapAmount;
        
        bool ethFee = Currency.unwrap(feeCurrency) == address(0);
        uint256 feeAmount = uint128(swapAmount) * FEE / TOTAL_BIPS;

        // regardless if PEBBLE is inbound or outbound from PoolManager, we need to set the transfer allowance
        uint256 pebbleAmountToTransfer =
            delta.amount1() < 0 ? uint256(int256(-delta.amount1())) : uint256(int256(delta.amount1()));

        if (feeAmount == 0) {
            Pebble(Currency.unwrap(key.currency1)).increaseTransferAllowance(pebbleAmountToTransfer);
            return (BaseHook.afterSwap.selector, 0);
        }

        // account for "fees-in-PEBBLE" for the transfer allowance
        // for exact inputs (ETH --> ??? PEBBLE) the fee is skimmed from delta.amount1() but its transferred to the hook
        pebbleAmountToTransfer += (feeCurrency == key.currency1) ? feeAmount : 0;

        Pebble(Currency.unwrap(key.currency1)).increaseTransferAllowance(pebbleAmountToTransfer);

        poolManager.take(feeCurrency, address(this), feeAmount);

        // Convert fee to ETH if needed, then send to quarry
        uint256 feeInETH;
        if (!ethFee) {
            // Fee is in Pebble, swap it to ETH (set flag to avoid recursive fee)
            processingFees = true;
            feeInETH = _swapPebbleToEth(key, feeAmount);
            processingFees = false;
        } else {
            // Fee is already in ETH
            feeInETH = feeAmount;
        }

        // Send ETH fees directly to quarry
        SafeTransferLib.forceSafeTransferETH(quarryAddress, feeInETH);

        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    /// @notice Swaps Pebble fees to ETH
    /// @param key The pool key for the swap
    /// @param amount The amount of Pebble to swap
    /// @return The amount of ETH received from the swap
    /// @dev Internal function to convert Pebble fees to ETH before sending to quarry
    function _swapPebbleToEth(PoolKey memory key, uint256 amount) internal returns (uint256) {
        uint256 ethBefore = address(this).balance;

        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: false, 
                amountSpecified: -int256(amount), 
                sqrtPriceLimitX96: MAX_PRICE_LIMIT
            }),
            bytes("")
        );

        // Handle settlements - it's ALWAYS a oneForZero swap (Pebble -> ETH)
        key.currency1.settle(poolManager, address(this), uint256(int256(-delta.amount1())), false);
        key.currency0.take(poolManager, address(this), uint256(int256(delta.amount0())), false);

        return address(this).balance - ethBefore;
    }

    receive() external payable {}
}