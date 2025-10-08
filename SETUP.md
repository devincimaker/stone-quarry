# Quarry - Pebble Token Launcher Setup

## Overview

This project extracts the token launch and Uniswap V4 liquidity deployment features from the NFTStrategyFactory. The Quarry contract launches a **$pebble** token and deploys it to Uniswap V4 with an initial liquidity pool.

## Contracts

### `Pebble.sol`

A **non-transferable** ERC20 token with:

- Name: "Pebble"
- Symbol: "PEBBLE"
- Initial Supply: 1,000,000,000 tokens (1 billion)
- **Can only be traded through Uniswap V4** - direct transfers are blocked
- Uses transient storage for transfer allowances controlled by the hook

### `PebbleHook.sol`

A Uniswap V4 hook that:

- **Controls token transfers** via transient allowance system
- Charges **dynamic fees** that decrease over time:
  - Buy fees: Start at **99%** and decrease **1% per minute** down to **10%**
  - Sell fees: Constant **10%**
- Collects fees and sends to designated recipient
- Restricts exact output swaps

### `Quarry.sol`

The launcher contract that:

1. Deploys the Pebble token (immutable)
2. Creates a Uniswap V4 pool (ETH/PEBBLE) with hook
3. Adds initial liquidity (1 wei ETH + 1B PEBBLE tokens)
4. Burns the LP tokens by sending to dead address

### `IPebble.sol`

Interface for the Pebble token contract

## Required Dependencies

To compile and deploy these contracts, install the following dependencies:

```bash
# Solady (for ERC20 implementation)
forge install vectorized/solady

# Uniswap V4 Core
forge install Uniswap/v4-core

# Uniswap V4 Periphery
forge install Uniswap/v4-periphery

# Permit2
forge install Uniswap/permit2
```

## Foundry Remappings

Add these to your `foundry.toml`:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
    "solady/=lib/solady/src/",
    "@uniswap/v4-core/=lib/v4-core/",
    "@uniswap/v4-periphery/=lib/v4-periphery/",
    "permit2/=lib/permit2/"
]
```

## Key Features Extracted

### From Factory.sol:

1. **Token Deployment** - Simplified to deploy a single Pebble token instead of NFTStrategy proxies
2. **`_loadLiquidity()` Function** - Creates Uniswap V4 pool with:

   - ETH as currency0
   - PEBBLE as currency1
   - 0% LP fee
   - Tick spacing of 60
   - Starting price: 10 ETH = 1B PEBBLE
   - Full range liquidity position
   - LP tokens sent to dead address (burned)

3. **`_mintLiquidityParams()` Helper** - Encodes parameters for Uniswap V4 position manager

## Deployment

Once dependencies are installed, deploy in this order:

### Step 1: Deploy Pebble Token

```solidity
// Deploy with poolManager and hook address
Pebble pebbleToken = new Pebble(poolManager, hookAddress);
```

### Step 2: Deploy PebbleHook

```solidity
// Deploy the hook
PebbleHook hook = new PebbleHook(
    poolManager,      // IPoolManager
    address(pebbleToken),  // Pebble token
    feeRecipient      // Address to receive fees
);

// Set the Quarry contract address (before initialization)
hook.setQuarryContract(quarryAddress);
```

### Step 3: Deploy Quarry

```solidity
// Constructor parameters:
// - _posm: Uniswap V4 Position Manager address
// - _permit2: Permit2 contract address
// - _poolManager: Uniswap V4 Pool Manager address
// - _hookAddress: PebbleHook address

Quarry quarry = new Quarry(posm, permit2, poolManager, address(hook));

// The Pebble token is deployed in the constructor
address pebbleToken = address(quarry.pebbleToken());
```

### Step 4: Launch Liquidity

```solidity
// Launch liquidity into Uniswap V4
quarry.launch{value: 2 wei}();
```

### Key Design Decisions

- **Non-Transferable Token**: Users cannot transfer tokens directly (wallet-to-wallet). They must trade through Uniswap V4
- **Transient Storage Allowances**: The hook authorizes exact transfer amounts during swaps using transient storage (EIP-1153)
- **Dynamic Fee Decay**: Buy fees start at 99% and decrease 1% per minute (5 blocks) down to 10%
- **Immutable Architecture**: All core addresses (poolManager, hook) are immutable for gas efficiency

## How Non-Transferability Works

The Pebble token uses a sophisticated transient storage system to prevent direct transfers:

### Transfer Rules:

1. ✅ **Minting** - Allowed during deployment (`from == address(0)`)
2. ✅ **Burning** - Allowed to dead address (`to == 0x...dEaD`)
3. ✅ **Pool Swaps** - Allowed only if hook has set transient allowance
4. ❌ **Direct Transfers** - All other transfers revert with `InvalidTransfer()`

### Transient Allowance Flow:

```solidity
// During a swap:
1. User initiates swap through Uniswap V4
2. Hook's _afterSwap() calculates transfer amount
3. Hook calls pebbleToken.increaseTransferAllowance(amount)
4. Token's _afterTokenTransfer() checks and decrements allowance
5. Transfer succeeds if allowance >= amount
```

### Benefits:

- 🔒 **Prevents token sniping bots** from using other DEXs
- 💰 **All fees captured** - no way to bypass the fee system
- ⚡ **Gas efficient** - uses transient storage (EIP-1153)
- 🎯 **Precise control** - hook authorizes exact amounts needed

## Simplifications from NFTStrategy

The following features were **removed** as they weren't needed for basic token launch:

- ❌ NFT collection integration and NFT buying/selling
- ❌ NFTStrategy proxy pattern and upgradeability
- ❌ PunkStrategy (PNKSTR) buyback/burn mechanism
- ❌ TWAP-based token buyback system
- ❌ Collection owner fee distribution (80/10/10 split)
- ❌ Router validation and marketplace calls
- ❌ NFT price multiplier and sale system
- ❌ Multiple deployment/collection management
- ❌ Factory authorization system

### What Was Kept:

✅ Non-transferable token mechanism  
✅ Transient allowance system  
✅ Dynamic time-based fee decay  
✅ Hook-controlled transfers  
✅ Uniswap V4 liquidity deployment  
✅ LP token burning

The result is a **clean, focused launcher** that deploys a non-transferable token with dynamic fees.
