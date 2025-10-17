// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { StateLibrary } from "v4-core/src/libraries/StateLibrary.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { ModifyLiquidityParams, SwapParams } from "v4-core/src/types/PoolOperation.sol";
import { PoolSwapTest } from "v4-core/src/test/PoolSwapTest.sol";
import { BalanceDelta } from "v4-core/src/types/BalanceDelta.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { console } from "forge-std/console.sol";

import { StoneQuarry } from "../src/StoneQuarry.sol";
import { Pebble } from "../src/Pebble.sol";
import { StoneQuarryHook } from "../src/StoneQuarryHook.sol";

contract QuarryTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;


    StoneQuarry public quarry;
    StoneQuarryHook public hook;
    Pebble public pebble;

    address private constant posm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant dev = address(0x02);


    function setUp() public {
        vm.createSelectFork("https://mainnet.infura.io/v3/7e5e10bd463a477eb38669c5ed176e46");
        
        quarry = new StoneQuarry(
            posm,
            permit2,
            poolManager,
            dev
        );

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | 
            Hooks.AFTER_ADD_LIQUIDITY_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        address hookAddress = address(flags);

        bytes memory args = abi.encode(poolManager, address(quarry));
        deployCodeTo("StoneQuarryHook.sol", args, hookAddress);

        hook = StoneQuarryHook(payable(hookAddress));
        quarry.updateHookAddress(hookAddress);

        quarry.startQuarry{value: 2 wei}();
        pebble = quarry.pebble();
    }

    /// @notice Helper function to swap ETH for Pebble tokens
    /// @param ethAmount Amount of ETH to swap
    /// @return swapRouter The PoolSwapTest router used for the swap
    /// @return delta The balance changes from the swap
    function _swapETHForPebble(uint256 ethAmount) internal returns (PoolSwapTest swapRouter, BalanceDelta delta) {
        swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hookAddress())
        });
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        delta = swapRouter.swap{value: ethAmount}(pool, params, testSettings, "");
    }

    function test_StartQuarry() public view {
        assertNotEq(address(0x0), address(pebble));

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hookAddress()) // Should be address(0) based on Quarry.sol
        });
        
        PoolId poolId = pool.toId();
        
        // Get the pool's slot0 data from the PoolManager
        IPoolManager manager = IPoolManager(poolManager);
        (uint160 sqrtPriceX96,,, uint24 lpFee) = manager.getSlot0(poolId);
        
        // If sqrtPriceX96 is 0, the pool doesn't exist/wasn't initialized
        assertTrue(sqrtPriceX96 > 0, "Pool was not initialized");

        // Optionally verify the starting price matches what was set in Quarry
        uint160 expectedStartingPrice = 501082896750095888663770159906816;
        assertEq(sqrtPriceX96, expectedStartingPrice, "Pool price doesn't match expected starting price");
        
        // Verify fee settings
        assertEq(lpFee, 0, "LP fee should be 0");
    }

    function test_SwapETHForPebble() public {
        // Deploy a swap helper
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        
        // Reconstruct the pool key
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hookAddress())
        });
        
        // Record balances before swap
        uint256 ethBalanceBefore = address(this).balance;
        uint256 pebbleBalanceBefore = pebble.balanceOf(address(this));
        
        // Define swap params: swap 0.01 ETH for Pebble tokens
        // zeroForOne = true (ETH -> Pebble)
        // amountSpecified negative = exact input
        uint256 ethToSwap = 0.01 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap), // negative means exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // no price limit
        });
        
        // Perform the swap
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap{value: ethToSwap}(
            pool,
            params,
            testSettings,
            ""
        );
        
        // Record balances after swap
        uint256 ethBalanceAfter = address(this).balance;
        uint256 pebbleBalanceAfter = pebble.balanceOf(address(this));

        
        // Calculate actual amounts swapped
        uint256 ethSpent = ethBalanceBefore - ethBalanceAfter;
        uint256 pebbleReceived = pebbleBalanceAfter - pebbleBalanceBefore;
        
        // Assertions
        assertApproxEqAbs(ethSpent, ethToSwap, 1, "Should have spent approximately the ETH amount");
        assertTrue(pebbleReceived > 0, "Should have received some Pebble tokens");
        
        // Based on the pool setup (1 wei ETH : 1B Pebble), with 0.01 ETH
        // we should receive a substantial amount of Pebble tokens
        // Let's verify we get at least 1 million Pebble (conservative estimate)
        uint256 minExpectedPebble = 300_000 * 10 ** 18;
        assertTrue(
            pebbleReceived >= minExpectedPebble,
            "Should receive at least 350k Pebble tokens for 0.01"
        );

        
        // Log the amounts for visibility
        emit log_named_uint("ETH spent", ethSpent);
        emit log_named_uint("Pebble received", pebbleReceived);
        emit log_named_decimal_uint("Pebble received (readable)", pebbleReceived, 18);
        
        // Verify the delta matches what we received
        assertEq(-delta.amount0(), int256(ethToSwap), "Delta amount0 should match ETH spent");
        assertEq(delta.amount1(), int256(pebbleReceived), "Delta amount1 should match Pebble received");
    }

    function test_SwapPebbleForETH() public {
        // First swap ETH for Pebble to get some Pebble tokens
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hookAddress())
        });
        
        _swapETHForPebble(0.01 ether);

        // Now swap Pebble back to ETH
        uint256 pebbleBalance = pebble.balanceOf(address(this));
        uint256 pebbleToSwap = pebbleBalance / 2; // Swap half back
        
        // Approve the swap router to spend our Pebble tokens
        pebble.approve(address(swapRouter), pebbleToSwap);
        
        uint256 ethBalanceBefore = address(this).balance;
        
        SwapParams memory sellParams = SwapParams({
            zeroForOne: false, // Pebble -> ETH
            amountSpecified: -int256(pebbleToSwap),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap(pool, sellParams, testSettings, "");
        
        uint256 ethBalanceAfter = address(this).balance;
        uint256 ethReceived = ethBalanceAfter - ethBalanceBefore;
        
        assertTrue(ethReceived > 0, "Should have received ETH");
        assertTrue(delta.amount0() > 0, "Delta should show ETH received");
        assertTrue(delta.amount1() < 0, "Delta should show Pebble sent");
        
        emit log_named_uint("Pebble swapped", pebbleToSwap);
        emit log_named_uint("ETH received", ethReceived);
    }


    function test_FeeCollection() public {
        // Record Quarry's ETH balance before swap (fees are now collected in ETH)
        uint256 quarryETHBalanceBefore = address(quarry).balance;
        
        // Perform a swap (ETH -> Pebble, fee taken in Pebble then converted to ETH)
        uint256 ethToSwap = 0.1 ether;
        (, BalanceDelta delta) = _swapETHForPebble(ethToSwap);
        
        // Record Quarry's ETH balance after swap
        uint256 quarryETHBalanceAfter = address(quarry).balance;
        
        // Calculate fees collected
        // The fee is 10% of the Pebble output, but it gets swapped to ETH
        uint256 pebbleReceived = uint256(int256(delta.amount1()));
        
        // Quarry should have received fees in ETH (converted from Pebble)
        uint256 feeCollected = quarryETHBalanceAfter - quarryETHBalanceBefore;
        
        // The fee should be > 0 since we took 10% of Pebble and swapped it to ETH
        assertTrue(feeCollected > 0, "Fee should have been collected in ETH");

        emit log_named_uint("Pebble received by swapper", pebbleReceived);
        emit log_named_uint("Fee collected by Quarry (in ETH)", feeCollected);
        emit log_named_uint("Quarry ETH balance before", quarryETHBalanceBefore);
        emit log_named_uint("Quarry ETH balance after", quarryETHBalanceAfter);
    }

    function test_DirectTransferBlocked() public {
        // First get some Pebble tokens via swap
        _swapETHForPebble(0.01 ether);
        
        // Now try to transfer Pebble directly to another address
        address recipient = address(0x1234);
        uint256 transferAmount = 1000 * 10 ** 18;
        
        // This should revert with InvalidTransfer
        vm.expectRevert(Pebble.InvalidTransfer.selector);
        pebble.transfer(recipient, transferAmount);
    }

    function test_ExactOutputReverts() public {
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hookAddress())
        });
        
        // Try exact output swap (positive amountSpecified)
        uint256 pebbleDesired = 1000 * 10 ** 18;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: int256(pebbleDesired), // POSITIVE = exact output
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Should revert with ExactOutputNotAllowed
        vm.expectRevert(); // The custom error will be encoded in the revert
        swapRouter.swap{value: 1 ether}(pool, params, testSettings, "");
    }

    // Add this helper function to receive ETH refunds from the swap router
    receive() external payable {}

}
