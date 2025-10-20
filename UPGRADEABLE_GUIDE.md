# StoneQuarry Upgradeable Contract Guide

## Overview

The StoneQuarry contract has been successfully converted to an upgradeable contract using the **UUPS (Universal Upgradeable Proxy Standard)** pattern with OpenZeppelin's upgradeable contracts library.

## What Changed

### 1. Contract Structure

**Before:**

- Used Solady's `Ownable` contract
- Had immutable variables (`posm`, `permit2`, `poolManager`)
- Used a constructor for initialization

**After:**

- Uses OpenZeppelin's `OwnableUpgradeable` and `UUPSUpgradeable`
- Converted immutable variables to regular storage variables
- Uses an `initialize()` function instead of constructor
- Added storage gap for future upgrades

### 2. Key Files Modified

#### `/Users/devinci/Code/quarry/src/StoneQuarry.sol`

- Added imports for OpenZeppelin upgradeable contracts
- Changed inheritance to include `Initializable`, `OwnableUpgradeable`, and `UUPSUpgradeable`
- Converted constructor to `initialize()` function with `initializer` modifier
- Added `_authorizeUpgrade()` function (restricted to owner)
- Added 50-slot storage gap for future upgrades
- Explicitly initialized `waitPeriod` in the initializer

#### `/Users/devinci/Code/quarry/foundry.toml`

- Added remappings for OpenZeppelin upgradeable contracts

#### `/Users/devinci/Code/quarry/test/Quarry.t.sol`

- Updated to deploy contracts using the proxy pattern
- Uses `ERC1967Proxy` to wrap the implementation

### 3. New Files Created

#### `/Users/devinci/Code/quarry/script/DeployStoneQuarryProxy.s.sol`

Deployment script that:

- Deploys the StoneQuarry implementation
- Deploys an ERC1967 proxy pointing to the implementation
- Initializes the proxy with the required parameters
- Verifies the deployment

#### `/Users/devinci/Code/quarry/script/UpgradeStoneQuarry.s.sol`

Upgrade script that:

- Deploys a new implementation contract
- Calls `upgradeToAndCall()` on the existing proxy
- Verifies the upgrade was successful

#### `/Users/devinci/Code/quarry/test/StoneQuarryUpgradeable.t.sol`

Comprehensive test suite for upgradeable functionality:

- Tests initialization
- Tests that contracts cannot be reinitialized
- Tests upgrade authorization
- Tests state preservation after upgrades

## Deployment Guide

### Initial Deployment

1. Set environment variables:

```bash
export POSM_ADDRESS=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e
export PERMIT2_ADDRESS=0x000000000022D473030F116dDEE9F6B43aC78BA3
export POOL_MANAGER_ADDRESS=0x000000000004444c5dc75cB358380D2e3dE08A90
export DEV_ADDRESS=0xYourDevAddress
```

2. Run the deployment script:

```bash
forge script script/DeployStoneQuarryProxy.s.sol:DeployStoneQuarryProxy --rpc-url $RPC_URL --broadcast --verify
```

3. Save the proxy address from the deployment output. This is the address users will interact with.

### Upgrading

1. Set the proxy address:

```bash
export PROXY_ADDRESS=0xYourProxyAddress
```

2. Make changes to StoneQuarry.sol (ensure storage layout compatibility!)

3. Run the upgrade script:

```bash
forge script script/UpgradeStoneQuarry.s.sol:UpgradeStoneQuarry --rpc-url $RPC_URL --broadcast
```

## Important Considerations

### Storage Layout

⚠️ **CRITICAL**: When upgrading, you MUST maintain storage variable order and types. New variables must be added at the end, after existing ones.

**Current storage layout:**

1. Pebble public pebble
2. MiniRock public miniRock
3. IPositionManager private posm
4. IAllowanceTransfer private permit2
5. IPoolManager private poolManager
6. address public hookAddress
7. address public devAddress
8. bool public loadingLiquidity
9. bool public quarryStarted
10. uint256 public rocksAcquired
11. ... (mappings and other state variables)

### Do's and Don'ts

✅ **DO:**

- Add new state variables at the end
- Add new functions
- Modify function logic
- Use the storage gap for new variables

❌ **DON'T:**

- Change the order of existing state variables
- Change the types of existing state variables
- Remove existing state variables
- Add state variables in the middle
- Change parent contract inheritance order

### Security Features

1. **Initialization Protection**: The constructor calls `_disableInitializers()` to prevent the implementation from being initialized.

2. **Reinitialization Protection**: The `initialize()` function has the `initializer` modifier, which prevents it from being called more than once.

3. **Upgrade Authorization**: Only the contract owner can authorize upgrades via the `_authorizeUpgrade()` function.

4. **Storage Gap**: A 50-slot storage gap reserves space for future storage variables without breaking compatibility.

## Testing

Run all upgradeable tests:

```bash
forge test --match-contract StoneQuarryUpgradeable -vv
```

Run all tests including the original suite:

```bash
forge test
```

## Child Contracts

As per the implementation plan:

- ✅ **StoneQuarry**: Upgradeable (UUPS pattern)
- ❌ **MiniRock**: Non-upgradeable (as requested)
- ❌ **Pebble**: Non-upgradeable (as requested)

## Verification

After deployment, verify the contracts on a block explorer:

1. **Verify the implementation:**

```bash
forge verify-contract $IMPLEMENTATION_ADDRESS StoneQuarry --chain-id $CHAIN_ID
```

2. **Verify the proxy:**
   The proxy is already verified (standard ERC1967Proxy from OpenZeppelin).

3. **Link proxy to implementation on Etherscan:**
   Navigate to the proxy address on Etherscan and click "Is this a proxy?" to link it to the implementation.

## Additional Resources

- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/4.x/upgradeable)
- [UUPS Pattern Documentation](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
- [Writing Upgradeable Contracts](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable)

## Support

For questions or issues with the upgradeable implementation, please refer to:

- OpenZeppelin documentation
- The test suite in `test/StoneQuarryUpgradeable.t.sol`
- The deployment scripts in the `script/` directory
