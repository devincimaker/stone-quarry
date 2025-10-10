// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { StateLibrary } from "v4-core/src/libraries/StateLibrary.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency } from "v4-core/src/types/Currency.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
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
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
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

    // Add this helper function to receive ETH refunds from the swap router
    receive() external payable {}

}
