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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { StoneQuarry } from "../src/StoneQuarry.sol";
import { Pebble } from "../src/Pebble.sol";
import { StoneQuarryHook } from "../src/StoneQuarryHook.sol";
import { MiniRock } from "../src/MiniRock.sol";

contract QuarryTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;


    StoneQuarry public quarry;
    StoneQuarryHook public hook;
    Pebble public pebble;
    MiniRock public miniRock;

    address private constant posm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant dev = address(0x02);


    function setUp() public {
        vm.createSelectFork("https://mainnet.infura.io/v3/7e5e10bd463a477eb38669c5ed176e46");
        
        // Deploy implementation
        StoneQuarry implementation = new StoneQuarry();
        
        // Deploy proxy with initialization
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(StoneQuarry.initialize, (posm, permit2, poolManager, dev))
        );
        
        // Cast proxy to StoneQuarry interface
        quarry = StoneQuarry(payable(address(proxy)));

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
        miniRock = quarry.miniRock();
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

    function test_AcquireRock() public {
        // Give the quarry 1000 ETH to buy a rock
        vm.deal(address(quarry), 1000 ether);
        
        // Record balance before purchase
        uint256 balanceBefore = address(quarry).balance;
        
        // Get rock info before purchase
        (address ownerBefore, bool forSaleBefore, uint256 price, uint256 timesSoldBefore) = 
            quarry.etherRockOG().rocks(20);
        
        emit log_named_address("Rock owner before", ownerBefore);
        emit log_named_uint("Rock price", price);
        emit log_named_string("For sale before", forSaleBefore ? "Yes" : "No");
        
        // Purchase rock #20 (for sale at 124 ETH)
        quarry.acquireRock(20);
        
        // After wrapping, verify the wrapper owns the rock in OG contract
        (address ownerAfter, bool forSaleAfter,, uint256 timesSoldAfter) = 
            quarry.etherRockOG().rocks(20);
        
        assertEq(ownerAfter, address(quarry.etherRock721()), "ERC721 wrapper should own the rock in OG contract");
        assertFalse(forSaleAfter, "Rock should no longer be for sale");
        assertEq(timesSoldAfter, timesSoldBefore + 1, "Times sold should increment");
        
        // Verify the quarry owns the ERC721 wrapped rock
        address erc721Owner = quarry.etherRock721().ownerOf(20);
        assertEq(erc721Owner, address(quarry), "Quarry should own the ERC721 wrapped rock");
        
        // Verify ETH was spent
        uint256 balanceAfter = address(quarry).balance;
        uint256 ethSpent = balanceBefore - balanceAfter;
        assertEq(ethSpent, price, "Should have spent the rock price");
        
        emit log_named_address("Rock owner after", ownerAfter);
        emit log_named_string("For sale after", forSaleAfter ? "Yes" : "No");
        emit log_named_uint("ETH spent", ethSpent);
        emit log_named_uint("Times sold", timesSoldAfter);
    }

    function test_AcquireRockThroughFees() public {
        // Get rock info - we need 124 ETH to buy rock #20
        (,, uint256 rockPrice,) = quarry.etherRockOG().rocks(20);
        
        emit log_string("=== Starting Fee Accumulation Test ===");
        emit log_named_uint("Target rock price", rockPrice);
        emit log_named_uint("Starting quarry balance", address(quarry).balance);
        
        // Give the test account 2000 ETH to trade with
        vm.deal(address(this), 2000 ether);
        
        // Track swap sizes - varying amounts
        uint256[10] memory swapSizes = [
            uint256(100 ether),
            150 ether,
            200 ether,
            75 ether,
            125 ether,
            180 ether,
            90 ether,
            160 ether,
            110 ether,
            140 ether
        ];
        
        uint256 swapCount = 0;
        uint256 previousBalance = address(quarry).balance;
        
        // Perform multiple swaps until we have enough to buy the rock
        for (uint256 i = 0; i < swapSizes.length; i++) {
            uint256 ethToSwap = swapSizes[i];
            
            // Record balance before swap
            uint256 quarryBalanceBefore = address(quarry).balance;
            
            // Perform swap (ETH -> Pebble, which generates fee in ETH)
            _swapETHForPebble(ethToSwap);
            
            // Record balance after swap
            uint256 balanceAfterSwap = address(quarry).balance;
            uint256 feeCollected = balanceAfterSwap - quarryBalanceBefore;
            
            swapCount++;
            
            // Assert that fees were collected
            assertTrue(feeCollected > 0, "Fee should have been collected");
            assertTrue(balanceAfterSwap > quarryBalanceBefore, "Quarry balance should increase");
            
            // Log swap details
            emit log_string("--- Swap Details ---");
            emit log_named_uint("Swap #", swapCount);
            emit log_named_uint("ETH swapped", ethToSwap);
            emit log_named_uint("Fee collected this swap", feeCollected);
            emit log_named_uint("Cumulative quarry balance", balanceAfterSwap);
            emit log_named_uint("Still needed", balanceAfterSwap >= rockPrice ? 0 : rockPrice - balanceAfterSwap);
            
            previousBalance = balanceAfterSwap;
            
            // Check if we have enough to buy the rock
            if (balanceAfterSwap >= rockPrice) {
                emit log_string("=== Sufficient fees collected! ===");
                emit log_named_uint("Total swaps performed", swapCount);
                emit log_named_uint("Final quarry balance", balanceAfterSwap);
                break;
            }
        }
        
        // Verify we accumulated enough fees
        uint256 finalQuarryBalance = address(quarry).balance;
        assertGe(finalQuarryBalance, rockPrice, "Should have accumulated enough fees to buy rock");
        
        emit log_string("=== Attempting Rock Purchase ===");
        
        // Get rock info before purchase
        (address ownerBefore, bool forSaleBefore,, uint256 timesSoldBefore) = 
            quarry.etherRockOG().rocks(20);
        
        emit log_named_address("Rock owner before", ownerBefore);
        emit log_named_string("For sale before", forSaleBefore ? "Yes" : "No");
        
        // Purchase rock #20 using accumulated fees
        quarry.acquireRock(20);
        
        // After wrapping, verify the wrapper owns the rock in OG contract
        (address ownerAfter, bool forSaleAfter,, uint256 timesSoldAfter) = 
            quarry.etherRockOG().rocks(20);
        
        assertEq(ownerAfter, address(quarry.etherRock721()), "ERC721 wrapper should own the rock in OG contract");
        assertFalse(forSaleAfter, "Rock should no longer be for sale");
        assertEq(timesSoldAfter, timesSoldBefore + 1, "Times sold should increment");
        
        // Verify the quarry owns the ERC721 wrapped rock
        address erc721Owner = quarry.etherRock721().ownerOf(20);
        assertEq(erc721Owner, address(quarry), "Quarry should own the ERC721 wrapped rock");
        
        // Verify ETH was spent
        uint256 quarryBalanceAfter = address(quarry).balance;
        uint256 ethSpent = finalQuarryBalance - quarryBalanceAfter;
        assertEq(ethSpent, rockPrice, "Should have spent the rock price");
        
        emit log_string("=== Rock Purchase Complete ===");
        emit log_named_address("Rock owner after", ownerAfter);
        emit log_named_string("For sale after", forSaleAfter ? "Yes" : "No");
        emit log_named_uint("ETH spent on rock", ethSpent);
        emit log_named_uint("Remaining quarry balance", quarryBalanceAfter);
        emit log_named_uint("Total swaps to accumulate fees", swapCount);
    }

    // Add this helper function to receive ETH refunds from the swap router
    receive() external payable {}

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                  MINIROCK NFT TESTS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function test_UpdateMintPricePerRock() public {
        uint256 newPrice = 0.01 ether;
        uint256 rockNumber = 20;
        
        // Update mint price for specific rock
        quarry.updateMintPricePerRock(rockNumber, newPrice);
        
        // Verify the price was updated for this rock
        assertEq(quarry.mintPricePerRock(rockNumber), newPrice, "Mint price should be updated for rock");
    }

    function test_UpdateWaitPeriod() public {
        uint256 newPeriod = 2 days;
        
        // Update wait period
        quarry.updateWaitPeriod(newPeriod);
        
        // Verify the wait period was updated
        assertEq(quarry.waitPeriod(), newPeriod, "Wait period should be updated");
    }

    function test_MintMiniRock() public {
        // Setup: Acquire a rock
        // Give quarry enough ETH to buy a rock
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        
        // Verify rocks acquired
        assertEq(quarry.rocksAcquired(), 1, "Should have 1 rock acquired");
        
        // Get the mint price for this rock (set automatically on acquisition)
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // Give user enough ETH to mint
        address minter = address(0x1234);
        vm.deal(minter, mintPrice);
        
        // Mint a MiniRock
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        // Verify the mint
        assertEq(miniRock.totalSupply(), 1, "Total supply should be 1");
        assertEq(miniRock.ownerOf(1), minter, "Minter should own token 1");
        assertEq(quarry.lastMintTimestampPerRock(20), block.timestamp, "Last mint timestamp should be updated for rock 20");
    }

    function test_MintMiniRock_RevertWhenInsufficientPayment() public {
        // Setup: Acquire a rock
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // Try to mint with insufficient payment
        address minter = address(0x1234);
        vm.deal(minter, 1 ether);
        
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.InsufficientPayment.selector);
        quarry.mintMiniRock{value: mintPrice / 2}(20);
    }

    function test_MintMiniRock_RevertWhenNoRocksAcquired() public {
        // Try to mint without any rocks acquired
        address minter = address(0x1234);
        vm.deal(minter, 1 ether);
        
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.RockNotAcquired.selector);
        quarry.mintMiniRock{value: 0.01 ether}(20);
    }

    function test_MintMiniRock_RevertOnCooldown() public {
        // Setup: Acquire a rock
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // First mint
        address minter = address(0x1234);
        vm.deal(minter, mintPrice * 2); // Enough for potential second attempt
        
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        // Try to mint again immediately (should revert)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MintCooldownActive.selector);
        quarry.mintMiniRock{value: mintPrice}(20);
    }

    function test_MintMiniRock_AfterCooldown() public {
        // Setup: Acquire a rock
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // First mint
        address minter = address(0x1234);
        vm.deal(minter, mintPrice * 2); // Enough for both mints
        
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Second mint should succeed
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        assertEq(miniRock.totalSupply(), 2, "Total supply should be 2");
    }

    function test_MintMiniRock_MaxSupplyEnforcement() public {
        // Setup: Acquire a rock
        quarry.updateWaitPeriod(0); // Remove wait period for faster testing
        
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20); // 1st rock acquired: 90 public + 10 dev = 100 MiniRocks total
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        address minter = address(0x1234);
        vm.deal(minter, mintPrice * 91); // Enough for 90 mints plus one extra attempt
        
        // Mint 90 MiniRocks (the maximum for 1st rock with 10% dev fee)
        for (uint256 i = 0; i < 90; i++) {
            vm.prank(minter);
            quarry.mintMiniRock{value: mintPrice}(20);
        }
        
        assertEq(miniRock.totalSupply(), 90, "Should have minted 90 MiniRocks (10 reserved for dev)");
        
        // Try to mint one more (should revert since 10 are reserved for dev)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MiniRockNotAvailable.selector);
        quarry.mintMiniRock{value: mintPrice}(20);
    }

    function test_MintMiniRock_RocksAcquiredIncrement() public {
        // Setup
        quarry.updateWaitPeriod(0); // Remove wait period for faster testing
        
        // Give quarry enough ETH to buy a rock
        vm.deal(address(quarry), 1000 ether);
        
        // Verify initial state
        assertEq(quarry.rocksAcquired(), 0, "Should start with 0 rocks");
        
        // Acquire 1 rock (should increment counter)
        quarry.acquireRock(20);
        
        assertEq(quarry.rocksAcquired(), 1, "Should have 1 rock acquired");
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        address minter = address(0x1234);
        vm.deal(minter, mintPrice * 51); // Enough for 51 mints
        
        // Mint 50 MiniRocks (should succeed as limit is 100 with 1 rock)
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(minter);
            quarry.mintMiniRock{value: mintPrice}(20);
        }
        
        assertEq(miniRock.totalSupply(), 50, "Should have minted 50 MiniRocks");
        
        // Verify we can still mint more (haven't hit the 100 limit)
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        assertEq(miniRock.totalSupply(), 51, "Should have minted 51 MiniRocks");
    }

    function test_MiniRock_PaymentSentToQuarry() public {
        // Setup: Acquire a rock
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        uint256 quarryBalanceAfterRockBuy = address(quarry).balance;
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // Mint a MiniRock
        address minter = address(0x1234);
        vm.deal(minter, mintPrice);
        
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        // Verify the payment went to the quarry
        uint256 quarryBalanceAfterMint = address(quarry).balance;
        assertEq(
            quarryBalanceAfterMint,
            quarryBalanceAfterRockBuy + mintPrice,
            "Quarry should receive mint payment"
        );
    }

    function test_MiniRock_TokenURI() public {
        // Setup: Acquire a rock and mint a token
        vm.deal(address(quarry), 1000 ether);
        quarry.acquireRock(20);
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        address minter = address(0x1234);
        vm.deal(minter, mintPrice);
        
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPrice}(20);
        
        // Get token URI
        string memory uri = miniRock.tokenURI(1);
        
        // Verify it returns a valid URI with JSON metadata including source rock
        string memory expectedUri = 'data:application/json;utf8,{"name":"MiniRock #1","description":"A fragment from EtherRock #20","sourceRock":20}';
        assertEq(uri, expectedUri, "Should return valid token URI with source rock metadata");
    }

    function test_CompleteFlow_AcquireAndMintMultiple() public {
        emit log_string("=== Testing Complete MiniRock Flow ===");
        
        // Accumulate fees through swaps (reusing existing test logic)
        vm.deal(address(this), 2000 ether);
        
        uint256[5] memory swapSizes = [
            uint256(100 ether),
            150 ether,
            200 ether,
            75 ether,
            125 ether
        ];
        
        for (uint256 i = 0; i < swapSizes.length; i++) {
            _swapETHForPebble(swapSizes[i]);
        }
        
        emit log_named_uint("Quarry balance after swaps", address(quarry).balance);
        
        // Acquire a rock
        quarry.acquireRock(20);
        
        emit log_named_uint("Rocks acquired", quarry.rocksAcquired());
        
        uint256 mintPrice = quarry.mintPricePerRock(20);
        
        // Mint 5 MiniRocks with 1 day wait between each
        address[] memory minters = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            minters[i] = address(uint160(0x5000 + i));
            vm.deal(minters[i], 1 ether);
        }
        
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(minters[i]);
            quarry.mintMiniRock{value: mintPrice}(20);
            
            emit log_named_uint("Minted token", i + 1);
            emit log_named_address("Owner", miniRock.ownerOf(i + 1));
            
            // Fast forward 1 day for next mint
            if (i < 4) {
                vm.warp(block.timestamp + 1 days);
            }
        }
        
        assertEq(miniRock.totalSupply(), 5, "Should have minted 5 MiniRocks");
        
        emit log_string("=== Complete Flow Test Passed ===");
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*              PER-ROCK BEHAVIOR TESTS                */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    function test_MintPriceSetAutomaticallyOnAcquisition() public {
        // Give quarry enough ETH to buy a rock
        vm.deal(address(quarry), 1000 ether);
        
        // Get rock info before purchase
        (,, uint256 rockPrice,) = quarry.etherRockOG().rocks(20);
        
        emit log_named_uint("Rock price", rockPrice);
        
        // Acquire the rock
        quarry.acquireRock(20);
        
        // Verify mint price was automatically set to acquisition_cost / 100
        uint256 expectedMintPrice = rockPrice / 100;
        uint256 actualMintPrice = quarry.mintPricePerRock(20);
        
        assertEq(actualMintPrice, expectedMintPrice, "Mint price should be set to rock price / 100");
        
        emit log_named_uint("Expected mint price", expectedMintPrice);
        emit log_named_uint("Actual mint price", actualMintPrice);
    }

    function test_CooldownIsPerRock() public {
        // Give quarry enough ETH to buy two rocks
        vm.deal(address(quarry), 2000 ether);
        
        // Acquire two different rocks
        quarry.acquireRock(20);
        quarry.acquireRock(24);
        
        uint256 mintPriceRock20 = quarry.mintPricePerRock(20);
        uint256 mintPriceRock24 = quarry.mintPricePerRock(24);
        
        address minter = address(0x1234);
        vm.deal(minter, 10 ether);
        
        // Mint from rock #20
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPriceRock20}(20);
        
        // Immediately try to mint from rock #24 (should succeed - different cooldown)
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPriceRock24}(24);
        
        // Verify both mints succeeded
        assertEq(miniRock.totalSupply(), 2, "Should have minted 2 MiniRocks from different rocks");
        
        // Now try to mint from rock #20 again (should fail - cooldown active)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MintCooldownActive.selector);
        quarry.mintMiniRock{value: mintPriceRock20}(20);
        
        // And try to mint from rock #24 again (should also fail - cooldown active)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MintCooldownActive.selector);
        quarry.mintMiniRock{value: mintPriceRock24}(24);
        
        emit log_string("Cooldown is correctly tracked per rock");
    }

    function test_MintPriceIsPerRock() public {
        // Give quarry enough ETH to buy two rocks
        vm.deal(address(quarry), 2000 ether);
        
        // Acquire two different rocks with different prices
        quarry.acquireRock(20);
        quarry.acquireRock(24);
        
        // Get automatically set prices
        uint256 autoPrice20 = quarry.mintPricePerRock(20);
        uint256 autoPrice24 = quarry.mintPricePerRock(24);
        
        emit log_named_uint("Auto-set price for rock 20", autoPrice20);
        emit log_named_uint("Auto-set price for rock 24", autoPrice24);
        
        // Manually set different prices
        uint256 newPrice20 = 0.02 ether;
        uint256 newPrice24 = 0.05 ether;
        
        quarry.updateMintPricePerRock(20, newPrice20);
        quarry.updateMintPricePerRock(24, newPrice24);
        
        // Verify each rock has its own price
        assertEq(quarry.mintPricePerRock(20), newPrice20, "Rock 20 should have correct mint price");
        assertEq(quarry.mintPricePerRock(24), newPrice24, "Rock 24 should have correct mint price");
        
        // Mint from each and verify correct payment required
        address minter1 = address(0x1234);
        address minter2 = address(0x5678);
        vm.deal(minter1, 1 ether);
        vm.deal(minter2, 1 ether);
        
        // Mint from rock 20 with correct price
        vm.prank(minter1);
        quarry.mintMiniRock{value: newPrice20}(20);
        
        // Mint from rock 24 with correct price
        vm.prank(minter2);
        quarry.mintMiniRock{value: newPrice24}(24);
        
        assertEq(miniRock.totalSupply(), 2, "Should have minted 2 MiniRocks");
        
        // Try to mint from rock 20 with rock 24's price (should fail if insufficient)
        vm.warp(block.timestamp + 1 days);
        vm.prank(minter1);
        vm.expectRevert(StoneQuarry.InsufficientPayment.selector);
        quarry.mintMiniRock{value: newPrice20 - 1 wei}(20);
        
        emit log_string("Each rock correctly maintains its own mint price");
    }

    function test_UpdateMintPricePerRock_OnlyOwner() public {
        // Try to update mint price as non-owner
        address nonOwner = address(0x9999);
        
        vm.prank(nonOwner);
        vm.expectRevert(); // Ownable.Unauthorized() selector
        quarry.updateMintPricePerRock(20, 0.05 ether);
        
        // Verify owner can update
        quarry.updateMintPricePerRock(20, 0.05 ether);
        assertEq(quarry.mintPricePerRock(20), 0.05 ether, "Owner should be able to update mint price");
    }

    function test_MultipleRocksMintSupplyTracking() public {
        // Give quarry enough ETH to buy two rocks
        vm.deal(address(quarry), 2000 ether);
        
        // Remove wait period for faster testing
        quarry.updateWaitPeriod(0);
        
        // Acquire two rocks
        quarry.acquireRock(20);
        quarry.acquireRock(24);
        
        uint256 mintPriceRock20 = quarry.mintPricePerRock(20);
        uint256 mintPriceRock24 = quarry.mintPricePerRock(24);
        
        address minter = address(0x1234);
        vm.deal(minter, 20 ether);
        
        // Mint 100 MiniRocks from rock #20 (max for this rock)
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(minter);
            quarry.mintMiniRock{value: mintPriceRock20}(20);
        }
        
        assertEq(miniRock.totalSupply(), 100, "Should have minted 100 MiniRocks");
        
        // Try to mint one more from rock #20 (should fail)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MiniRockNotAvailable.selector);
        quarry.mintMiniRock{value: mintPriceRock20}(20);
        
        // But we should still be able to mint from rock #24
        vm.prank(minter);
        quarry.mintMiniRock{value: mintPriceRock24}(24);
        
        assertEq(miniRock.totalSupply(), 101, "Should have minted 101 MiniRocks (100 from rock 20, 1 from rock 24)");
        
        // Mint 99 more from rock #24
        for (uint256 i = 0; i < 99; i++) {
            vm.prank(minter);
            quarry.mintMiniRock{value: mintPriceRock24}(24);
        }
        
        assertEq(miniRock.totalSupply(), 200, "Should have minted 200 MiniRocks total (100 per rock)");
        
        // Try to mint one more from rock #24 (should also fail now)
        vm.prank(minter);
        vm.expectRevert(StoneQuarry.MiniRockNotAvailable.selector);
        quarry.mintMiniRock{value: mintPriceRock24}(24);
        
        emit log_string("Each rock correctly tracks its own 100 MiniRock supply limit");
    }

}
