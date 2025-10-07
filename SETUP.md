# Quarry - Pebble Token Launcher Setup

## Overview

This project extracts the token launch and Uniswap V4 liquidity deployment features from the NFTStrategyFactory. The Quarry contract launches a **$pebble** token and deploys it to Uniswap V4 with an initial liquidity pool.

## Contracts

### `Pebble.sol`

A simple ERC20 token with:

- Name: "Pebble"
- Symbol: "PEBBLE"
- Initial Supply: 1,000,000,000 tokens (1 billion)

### `Quarry.sol`

The launcher contract that:

1. Deploys the Pebble token
2. Creates a Uniswap V4 pool (ETH/PEBBLE)
3. Adds initial liquidity (1 wei ETH + 1B PEBBLE tokens)
4. Burns the LP tokens by sending to dead address

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

Once dependencies are installed:

```solidity
// Constructor parameters needed:
// - _posm: Uniswap V4 Position Manager address
// - _permit2: Permit2 contract address
// - _poolManager: Uniswap V4 Pool Manager address
// - _hookAddress: Optional hook address (use address(0) for no hook)

// Deploy Quarry - this also deploys the Pebble token
Quarry quarry = new Quarry(posm, permit2, poolManager, hookAddress);

// The Pebble token is now deployed and accessible
address pebbleToken = address(quarry.pebbleToken());

// Launch liquidity into Uniswap V4
quarry.launch{value: 2 wei}();
```

### Key Design Decisions

- **Immutable Pebble Token**: The token is deployed in the constructor, making it immutable and more gas-efficient
- **Separate Launch Function**: Liquidity deployment is separated into the `launch()` function, allowing the token to exist before liquidity is added

## Simplifications from Factory.sol

The following features were **removed** as they weren't needed for basic token launch:

- ❌ NFT collection integration
- ❌ NFTStrategy proxy pattern
- ❌ Collection owner fee management
- ❌ Multiple token deployments
- ❌ PunkStrategy buyback/burn mechanism
- ❌ TWAP functionality
- ❌ Launcher authorization system
- ❌ Upgradeability
- ❌ Admin functions
- ❌ Factory fee collection

The result is a **clean, focused launcher** that does one thing: deploy a token and create a Uniswap V4 liquidity pool.
