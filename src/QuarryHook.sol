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
import "./Pebble.sol";

contract QuarryHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for uint256;
    using SafeCast for int128;

    error NotQuarry();
    error ExactOutputNotAllowed();

    uint128 private constant TOTAL_BIPS = 10000;
    uint128 private constant FEE = 1000; // 10%

    address public immutable quarryAddress;
    address public immutable pebbleAddress;
    bool public loadingLiquidity;

    constructor(
        address _poolManager,
        address _quarryAddress,
        address _pebbleAddress
    ) BaseHook(IPoolManager(_poolManager)) {
        quarryAddress = _quarryAddress;
        pebbleAddress = _pebbleAddress;
    }

    function setLoadingLiquidity(bool _loading) external {
        require(msg.sender == quarryAddress, "Not quarry");
        loadingLiquidity = _loading;
    }

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

    function _beforeInitialize(address, PoolKey calldata, uint160) internal view override returns (bytes4) {
        if (!loadingLiquidity) {
            revert NotQuarry();
        }
        return BaseHook.beforeInitialize.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        if (!loadingLiquidity) {
            revert NotQuarry();
        } else {
            // we are loading liquidity so admit a transfer allowance
            // safe casting, liquidity additions are -values
            Pebble(Currency.unwrap(key.currency1)).increaseTransferAllowance(uint256(int256(-delta.amount1())));
        }
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (params.amountSpecified > 0) {
            revert ExactOutputNotAllowed();
        }
        
        // Calculate fee based on the swap amount
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        if (swapAmount < 0) swapAmount = -swapAmount;
        
        uint256 feeAmount = uint128(swapAmount) * FEE / TOTAL_BIPS;

        // regardless if PEBBLE is inbound or outbound from PoolManager, we need to set the transfer allowance
        uint256 pebbleAmountToTransfer =
            delta.amount1() < 0 ? uint256(int256(-delta.amount1())) : uint256(int256(delta.amount1()));

        if (feeAmount == 0) {
            Pebble(pebbleAddress).increaseTransferAllowance(pebbleAmountToTransfer);
            return (BaseHook.afterSwap.selector, 0);
        }

        // account for "fees-in-PEBBLE" for the transfer allowance
        // for exact inputs (ETH --> ??? PEBBLE) the fee is skimmed from delta.amount1() but its transferred to the hook
        pebbleAmountToTransfer += (feeCurrency == key.currency1) ? feeAmount : 0;

        Pebble(pebbleAddress).increaseTransferAllowance(pebbleAmountToTransfer);

        poolManager.take(feeCurrency, address(this), feeAmount);

        // Send fees to quarry using settle
        feeCurrency.settle(poolManager, quarryAddress, feeAmount, false);

        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    receive() external payable {}
}