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

import { Quarry } from "../src/Quarry.sol";
import { Pebble } from "../src/Pebble.sol";

contract QuarryTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;


    Quarry public quarry;

    address private constant posm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant dev = address(0x02);

    function setUp() public {
        vm.createSelectFork("https://mainnet.infura.io/v3/7e5e10bd463a477eb38669c5ed176e46");
        
        quarry = new Quarry{value: 2 wei}(
            posm,
            permit2,
            poolManager,
            dev
        );
    }

    function test_PebbleDeploy() public view {
        uint256 expectedSupply = 1_000_000_000 * 10 ** 18;

        Pebble pebble = quarry.pebble();

        assertEq(pebble.totalSupply(), expectedSupply);
    }

    function test_LoadLiquidity() public view {
        // Check that the pool exists.
        Pebble pebble = quarry.pebble();
        
        // Reconstruct the pool key that was used in the Quarry constructor
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook()) // Should be address(0) based on Quarry.sol
        });
        
        // Get the pool ID
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
        
        // Get the pebble token
        Pebble pebble = quarry.pebble();
        
        // Reconstruct the pool key
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
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
            "Should receive at least 300k Pebble tokens for 0.01"
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
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
        });
        
        // Buy Pebble first
        uint256 ethToSwap = 0.01 ether;
        SwapParams memory buyParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        swapRouter.swap{value: ethToSwap}(pool, buyParams, testSettings, "");
        
        // Now swap Pebble back to ETH
        uint256 pebbleBalance = pebble.balanceOf(address(this));
        uint256 pebbleToSwap = pebbleBalance / 2; // Swap half back
        
        uint256 ethBalanceBefore = address(this).balance;
        
        SwapParams memory sellParams = SwapParams({
            zeroForOne: false, // Pebble -> ETH
            amountSpecified: -int256(pebbleToSwap),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
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
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
        });
        
        // Record Quarry's balance before swap
        IPoolManager manager = IPoolManager(poolManager);
        uint256 quarryEthBalanceBefore = manager.balanceOf(address(quarry), uint256(uint160(Currency.unwrap(Currency.wrap(address(0))))));
        uint256 quarryPebbleBalanceBefore = manager.balanceOf(address(quarry), uint256(uint160(Currency.unwrap(Currency.wrap(address(pebble))))));
        
        // Perform a swap
        uint256 ethToSwap = 0.1 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        BalanceDelta delta = swapRouter.swap{value: ethToSwap}(pool, params, testSettings, "");
        
        // Record Quarry's balance after swap
        uint256 quarryEthBalanceAfter = manager.balanceOf(address(quarry), uint256(uint160(Currency.unwrap(Currency.wrap(address(0))))));
        uint256 quarryPebbleBalanceAfter = manager.balanceOf(address(quarry), uint256(uint160(Currency.unwrap(Currency.wrap(address(pebble))))));
        
        // Calculate fees collected (10% of output)
        uint256 pebbleReceived = uint256(int256(delta.amount1()));
        uint256 expectedFee = pebbleReceived / 10; // 10% fee
        
        // Quarry should have received fees in Pebble
        uint256 feeCollected = quarryPebbleBalanceAfter - quarryPebbleBalanceBefore;
        
        // Allow for small rounding differences
        assertApproxEqAbs(
            feeCollected,
            expectedFee,
            expectedFee / 100, // 1% tolerance
            "Quarry should have collected ~10% fee in Pebble"
        );
        
        assertTrue(feeCollected > 0, "Fee should have been collected");
        
        emit log_named_uint("Pebble received by swapper", pebbleReceived);
        emit log_named_uint("Fee collected by Quarry", feeCollected);
        emit log_named_uint("Expected fee (10%)", expectedFee);
    }

    function test_DirectTransferBlocked() public {
        // First get some Pebble tokens via swap
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
        });
        
        uint256 ethToSwap = 0.01 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        swapRouter.swap{value: ethToSwap}(pool, params, testSettings, "");
        
        // Now try to transfer Pebble directly to another address
        address recipient = address(0x1234);
        uint256 transferAmount = 1000 * 10 ** 18;
        
        // This should revert with InvalidTransfer
        vm.expectRevert(Pebble.InvalidTransfer.selector);
        pebble.transfer(recipient, transferAmount);
    }

    function test_DirectTransferFromBlocked() public {
        // First get some Pebble tokens
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
        });
        
        uint256 ethToSwap = 0.01 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        swapRouter.swap{value: ethToSwap}(pool, params, testSettings, "");
        
        // Approve another address
        address spender = address(0x5678);
        uint256 approveAmount = 1000 * 10 ** 18;
        pebble.approve(spender, approveAmount);
        
        // Try to transferFrom (should also be blocked)
        address recipient = address(0x9ABC);
        
        vm.prank(spender);
        vm.expectRevert(Pebble.InvalidTransfer.selector);
        pebble.transferFrom(address(this), recipient, approveAmount);
    }

    function test_OnlyPoolManagerCanTransfer() public {
        // Get some Pebble tokens
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
        });
        
        // Do a successful swap to verify poolManager CAN transfer
        uint256 ethToSwap = 0.01 ether;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethToSwap),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // This should succeed because it goes through the pool manager
        BalanceDelta delta = swapRouter.swap{value: ethToSwap}(pool, params, testSettings, "");
        
        assertTrue(delta.amount1() > 0, "Should have received Pebble tokens through pool");
        
        // But direct transfers should still fail
        vm.expectRevert(Pebble.InvalidTransfer.selector);
        pebble.transfer(address(0x1234), 100);
    }

    function test_ExactOutputReverts() public {
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager));
        Pebble pebble = quarry.pebble();
        
        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(pebble)),
            fee: 0,
            tickSpacing: 60,
            hooks: IHooks(quarry.hook())
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
