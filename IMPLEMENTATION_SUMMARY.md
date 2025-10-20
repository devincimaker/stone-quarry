# Per-Rock Tracking Implementation Summary

## Overview

Implemented a comprehensive per-rock tracking system that allows users to contribute funds toward specific rock purchases and receive proportional MiniRock allocations. Each MiniRock now tracks its source rock, with proper accounting for different rock prices.

## Key Features Implemented

### 1. Per-Rock Price Calculation

- Each rock has a different price (fetched from EtherRockOG contract)
- Contributions are calculated as multiples of `rock_price / 100`
- If a rock costs 250 ETH and someone contributes 50 ETH, they get 20 MiniRocks
- If a rock costs 100 ETH and someone contributes 50 ETH, they get 50 MiniRocks

### 2. Single MiniRock Contract for All Rocks

- One `MiniRock` NFT contract handles all rocks
- Each MiniRock token stores its `sourceRockNumber`
- Token metadata includes source rock information in JSON format

### 3. Enhanced StoneQuarry Contract

#### New State Variables

```solidity
mapping(address => mapping(uint256 => uint256)) public miniRockAllocations;
mapping(uint256 => bool) public rockAcquired;
mapping(uint256 => uint256) public miniRocksMintedPerRock;
mapping(uint256 => uint256) public miniRocksAllocatedPerRock;
```

#### Updated Functions

**`acquireRock(uint256 rockNumber)` - Enhanced**

- Accepts ETH contributions when purchasing a rock
- Calculates `miniRockPrice = rock_price / 100`
- Validates contribution is exact multiple of miniRockPrice
- Allocates MiniRocks proportionally to contributor
- Marks rock as acquired in the mapping
- Tracks allocated amounts per rock

**`claimAllocatedMiniRocks(uint256 rockNumber, uint256 amount)` - New**

- Users specify which rock to claim MiniRocks from
- Validates rock has been acquired
- No cooldown restrictions (immediate claiming)
- Mints MiniRocks with source rock tracking
- Updates per-rock minting counters

**`mintMiniRock(uint256 rockNumber)` - Enhanced**

- Users specify which rock to mint from
- Validates rock has been acquired
- Calculates available supply: `100 - miniRocksAllocatedPerRock[rockNumber]`
- Existing cooldown and price checks still apply
- Tracks minted count per rock

#### New Errors

- `RockNotAcquired()` - Attempting to mint/claim from unacquired rock
- `ExceedsMaxAllocation()` - Trying to allocate more than 100 MiniRocks per rock
- `InvalidContributionAmount()` - Contribution not exact multiple of miniRockPrice

#### New Events

- `MiniRockAllocated(address indexed user, uint256 amount, uint256 contribution, uint256 rockNumber)`

### 4. Enhanced MiniRock Contract

#### New State Variables

```solidity
mapping(uint256 => uint256) public sourceRockNumber;
```

#### Updated Functions

**`mint(address to, uint256 rockNumber)` - Enhanced**

- Accepts `rockNumber` parameter
- Stores source rock number for each token
- Returns tokenId

**`tokenURI(uint256 tokenId)` - Enhanced**

- Returns JSON metadata instead of simple URL
- Includes source rock number in metadata
- Format: `data:application/json;utf8,{"name":"MiniRock #X","description":"A fragment from EtherRock #Y","sourceRock":Y}`

**`_toString(uint256 value)` - New Helper**

- Internal function to convert uint256 to string
- Used for generating dynamic metadata

## Usage Examples

### Contributing to Rock Purchase

```solidity
// Rock costs 100 ETH, contribute 60 ETH
// You get 60 MiniRocks allocated
quarry.acquireRock{value: 60 ether}(20);
```

### Claiming Allocated MiniRocks

```solidity
// Claim 10 of your allocated MiniRocks from rock #20
quarry.claimAllocatedMiniRocks(20, 10);
```

### Public Minting

```solidity
// Mint from rock #20 (if available after allocations)
quarry.mintMiniRock{value: mintPrice}(20);
```

### Checking Source Rock

```solidity
// Get source rock for a token
uint256 sourceRock = miniRock.sourceRockNumber(tokenId);

// Get metadata
string memory metadata = miniRock.tokenURI(tokenId);
```

## Testing

All 22 tests passing, including:

- Rock acquisition with contributions
- Per-rock allocation tracking
- MiniRock minting with source tracking
- Metadata generation with rock numbers
- Error handling for unacquired rocks
- Complete flow tests

## Future Enhancements

- SVG generation based on source rock characteristics
- IPFS metadata hosting
- Group buying mechanism for multiple contributors per rock
- Enhanced metadata with acquisition history

