// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { Currency} from "v4-core/src/types/Currency.sol";
import { IPositionManager } from "v4-periphery/src/interfaces/IPositionManager.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { IPoolInitializer_v4 } from "v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import { Actions } from "v4-periphery/src/libraries/Actions.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "v4-core/test/utils/LiquidityAmounts.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import "./Pebble.sol";
import "./StoneQuarryHook.sol";
import "./IEtherRockOG.sol";
import "./IEtherRock721.sol";
import "./MiniRock.sol";

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

contract StoneQuarry is Ownable, IERC721Receiver {
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /// @notice The strategy token contract
    Pebble public pebble;
    /// @notice The MiniRock NFT contract
    MiniRock public miniRock;
    /// @notice How much eth to send when deploying the pool
    uint256 private constant ethToPair = 2 wei;
    /// @notice The Uniswap position manager
    IPositionManager private immutable posm;
    /// @notice The Uniswap permit2 contract
    IAllowanceTransfer private immutable permit2;
    /// @notice The Uniswap pool manager
    IPoolManager private immutable poolManager;
    /// @notice The EtherRockOG contract
    IEtherRockOG public constant etherRockOG = IEtherRockOG(0x41f28833Be34e6EDe3c58D1f597bef429861c4E2);
    /// @notice The EtherRock ERC721 wrapper contract
    IEtherRock721 public constant etherRock721 = IEtherRock721(0xA3F5998047579334607c47a6a2889BF87A17Fc02);
    /// @notice The address to burn tokens
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    /// @notice Dev fee percentage (10 out of 100 MiniRocks)
    uint256 public constant DEV_FEE_PERCENTAGE = 10;
    /// @notice Only first 10 rocks get dev fee
    uint256 public constant DEV_FEE_ROCK_LIMIT = 10;
    /// @notice Lock period before dev can claim (30 days)
    uint256 public constant LOCK_PERIOD = 30 days;


    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice The address for the Uniswap hook
    address public hookAddress; 

    /// @notice The address that receives dev MiniRocks
    address public devAddress;
    /// @notice Gates the hook to only when we're loading a new token
    bool public loadingLiquidity;
    ///@notice Tracks if the stone quarry started working 
    bool public quarryStarted;
    /// @notice Counter for the number of rocks acquired by the contract
    uint256 public rocksAcquired;
    /// @notice Timestamp of the last MiniRock mint per rock (rockNumber => timestamp)
    mapping(uint256 => uint256) public lastMintTimestampPerRock;
    /// @notice Price to mint a MiniRock per rock (rockNumber => price)
    mapping(uint256 => uint256) public mintPricePerRock;
    /// @notice Wait period between mints (in seconds)
    uint256 public waitPeriod = 1 days;
    /// @notice Tracks allocated MiniRocks per user per rock (user => rockNumber => allocated amount)
    mapping(address => mapping(uint256 => uint256)) public miniRockAllocations;
    /// @notice Tracks which rocks have been acquired by the contract
    mapping(uint256 => bool) public rockAcquired;
    /// @notice Tracks how many MiniRocks have been minted per rock
    mapping(uint256 => uint256) public miniRocksMintedPerRock;
    /// @notice Tracks how many MiniRocks have been allocated per rock
    mapping(uint256 => uint256) public miniRocksAllocatedPerRock;
    /// @notice Tracks when each rock was acquired (for lock period calculation)
    mapping(uint256 => uint256) public rockAcquiredTimestamp;
    /// @notice Tracks acquisition order (1st, 2nd, 3rd rock acquired, etc.)
    mapping(uint256 => uint256) public rockAcquisitionOrder;
    /// @notice Tracks how many dev MiniRocks have been claimed per rock
    mapping(uint256 => uint256) public devMiniRocksClaimedPerRock;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Hook address has not been set
    error HookNotSet();
    /// @notice Incorrect ETH amount sent with launch transaction
    error WrongEthAmount();
    /// @notice Quarry already started working
    error AlreadyStarted();
    /// @notice Rock is not for sale
    error RockNotForSale();
    /// @notice Insufficient ETH sent
    error InsufficientEthForRockBuy();
    /// @notice Not the owner of the rock
    error NotOwnerOfRock();
    /// @notice Already the owner of the rock
    error AlreadyOwnerOfRock();
    /// @notice No more MiniRocks available to mint
    error MiniRockNotAvailable();
    /// @notice Must wait before minting next MiniRock
    error MintCooldownActive();
    /// @notice Insufficient payment for minting MiniRock
    error InsufficientPayment();
    /// @notice No allocations available to claim
    error NoAllocationsAvailable();
    /// @notice Contribution must be exact multiple of miniRockPrice
    error InvalidContributionAmount();
    /// @notice Cannot allocate more than 100 MiniRocks per rock
    error ExceedsMaxAllocation();
    /// @notice Rock has not been acquired yet
    error RockNotAcquired();
    /// @notice Dev MiniRocks are still locked
    error DevMiniRocksStillLocked(uint256 unlockTime);
    /// @notice Caller is not the dev address
    error NotDevAddress();
    /// @notice Exceeds dev allocation of MiniRocks
    error ExceedsDevAllocation();
    /// @notice No dev fee for this rock (only first 10 rocks)
    error NoDevFeeForThisRock();
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM EVENTS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /// 
    event QuarryOpen();
    event MiniRockMinted(address indexed minter, uint256 indexed tokenId, uint256 price);
    event WaitPeriodUpdated(uint256 newPeriod);
    event MiniRockAllocated(address indexed user, uint256 amount, uint256 contribution, uint256 rockNumber);
    event MiniRocksClaimed(address indexed user, uint256 amount);
    event MintPriceUpdated(uint256 rockNumber, uint256 newPrice);
    event DevMiniRocksClaimed(address indexed dev, uint256 rockNumber, uint256 amount);
    event DevAddressUpdated(address indexed oldAddress, address indexed newAddress);
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Constructor initializes the quarry with required dependencies
    /// @param _posm Uniswap V4 Position Manager address
    /// @param _permit2 Permit2 contract address
    /// @param _poolManager Uniswap V4 Pool Manager address
    /// @param _devAddress Address to receive dev MiniRocks
    constructor(address _posm, address _permit2, address _poolManager, address _devAddress) {
        posm = IPositionManager(_posm);
        permit2 = IAllowanceTransfer(_permit2);
        poolManager = IPoolManager(_poolManager);
        devAddress = _devAddress;
        miniRock = new MiniRock(address(this));
        
         _initializeOwner(msg.sender);
    }

    // Add function to acquire a rock if the contract has the money
    function acquireRock(uint256 rockNumber) external payable {
        (address owner, bool currentlyForSale, uint256 price,) = etherRockOG.rocks(rockNumber);

        if (owner == address(this)) revert AlreadyOwnerOfRock();
        if (!currentlyForSale) revert RockNotForSale();
        
        // Handle user contributions and MiniRock allocations
        if (msg.value > 0) {
            // Calculate price per MiniRock unit (each rock = 100 MiniRocks)
            uint256 miniRockPrice = price / 100;
            
            // Validate contribution is exact multiple of miniRockPrice
            if (msg.value % miniRockPrice != 0) revert InvalidContributionAmount();
            
            // Calculate number of MiniRocks to allocate
            uint256 allocatedAmount = msg.value / miniRockPrice;
            
            // Validate allocation doesn't exceed 100 per rock
            if (allocatedAmount > 100) revert ExceedsMaxAllocation();
            
            // Update per-rock allocations
            miniRockAllocations[msg.sender][rockNumber] += allocatedAmount;
            miniRocksAllocatedPerRock[rockNumber] += allocatedAmount;
            
            // Emit allocation event
            emit MiniRockAllocated(msg.sender, allocatedAmount, msg.value, rockNumber);
        }
        
        // Check we have sufficient funds (contract balance + contribution)
        if (price > address(this).balance) revert InsufficientEthForRockBuy();

        etherRockOG.buyRock{ value: price }(rockNumber);
        etherRockOG.setRockForSale(rockNumber, false);

        // require that we are the owner of the rock
        (address newOwner, , , ) = etherRockOG.rocks(rockNumber);
        if (newOwner != address(this)) revert NotOwnerOfRock();
        
        // Mark rock as acquired and increment counter
        rockAcquired[rockNumber] = true;
        rocksAcquired++;
        
        // Track acquisition timestamp and order for dev fee logic
        rockAcquiredTimestamp[rockNumber] = block.timestamp;
        rockAcquisitionOrder[rockNumber] = rocksAcquired;

        mintPricePerRock[rockNumber] = price / 100;

        // Wrap rock into ERC721 for proper display on block explorers
        etherRock721.update(rockNumber);  // Sync owner records to StoneQuarry
        etherRockOG.giftRock(rockNumber, address(etherRock721));  // Transfer to wrapper
        etherRock721.wrap(rockNumber);  // Mint ERC721 to this contract
    }

    /// @notice Claim allocated MiniRocks from contributing to rock purchases
    /// @dev No cooldown restrictions for allocated MiniRocks
    /// @param rockNumber The rock number to claim MiniRocks from
    /// @param amount Number of MiniRocks to claim (must be <= user's allocation for this rock)
    function claimAllocatedMiniRocks(uint256 rockNumber, uint256 amount) external {
        if (!rockAcquired[rockNumber]) revert RockNotAcquired();
        if (miniRockAllocations[msg.sender][rockNumber] == 0) revert NoAllocationsAvailable();
        if (amount > miniRockAllocations[msg.sender][rockNumber]) revert NoAllocationsAvailable();
        
        // Deduct from user's allocation for this rock
        miniRockAllocations[msg.sender][rockNumber] -= amount;
        
        // Mint the allocated MiniRocks from the specified source rock
        for (uint256 i = 0; i < amount; i++) {
            miniRock.mint(msg.sender, rockNumber);
            miniRocksMintedPerRock[rockNumber]++;
        }
        
        emit MiniRocksClaimed(msg.sender, amount);
    }

    /// @notice Mint a MiniRock NFT by paying the required price
    /// @dev Anyone can call this function as long as they pay the mint price
    /// @dev Must wait for the cooldown period between mints
    /// @dev Can only mint if there are available MiniRocks based on rocks acquired
    /// @param rockNumber The rock number to mint a MiniRock from
    function mintMiniRock(uint256 rockNumber) external payable {
        if (!rockAcquired[rockNumber]) revert RockNotAcquired();
        
        // Check if there are available MiniRocks to mint from this rock
        // First 10 rocks: 90 MiniRocks available (10 reserved for dev)
        // Rocks 11+: 100 MiniRocks available (no dev fee)
        uint256 totalAvailableForRock = isDevFeeApplicable(rockNumber) ? 90 : 100;
        uint256 maxSupplyForRock = totalAvailableForRock - miniRocksAllocatedPerRock[rockNumber];
        uint256 currentMintedForRock = miniRocksMintedPerRock[rockNumber];
        
        if (currentMintedForRock >= maxSupplyForRock) revert MiniRockNotAvailable();
        
        // Check wait period (first mint is allowed immediately)
        uint256 lastMintTimestamp = lastMintTimestampPerRock[rockNumber];
        if (lastMintTimestamp > 0 && block.timestamp < lastMintTimestamp + waitPeriod) {
            revert MintCooldownActive();
        }

        // Check payment
        if (msg.value < mintPricePerRock[rockNumber]) revert InsufficientPayment();
        
        // Update last mint timestamp
        lastMintTimestampPerRock[rockNumber] = block.timestamp;       

        // Mint the MiniRock NFT from the specified source rock
        uint256 tokenId = miniRock.mint(msg.sender, rockNumber);
        miniRocksMintedPerRock[rockNumber]++;
        
        emit MiniRockMinted(msg.sender, tokenId, msg.value);
    }

    /// @notice Claim dev MiniRocks after lock period
    /// @dev Only callable by dev address
    /// @dev Can only claim from first 10 rocks acquired
    /// @dev Must wait LOCK_PERIOD (30 days) from rock acquisition
    /// @param rockNumber The rock number to claim dev MiniRocks from
    /// @param amount Number of dev MiniRocks to claim (max 10 per rock)
    function claimDevMiniRocks(uint256 rockNumber, uint256 amount) external {
        if (msg.sender != devAddress) revert NotDevAddress();
        if (!rockAcquired[rockNumber]) revert RockNotAcquired();
        if (!isDevFeeApplicable(rockNumber)) revert NoDevFeeForThisRock();
        
        // Check lock period has passed
        uint256 unlockTime = rockAcquiredTimestamp[rockNumber] + LOCK_PERIOD;
        if (block.timestamp < unlockTime) revert DevMiniRocksStillLocked(unlockTime);
        
        // Check dev allocation limit (10 MiniRocks per rock)
        uint256 alreadyClaimed = devMiniRocksClaimedPerRock[rockNumber];
        if (alreadyClaimed + amount > DEV_FEE_PERCENTAGE) revert ExceedsDevAllocation();
        
        // Update tracking
        devMiniRocksClaimedPerRock[rockNumber] += amount;
        
        // Mint the dev MiniRocks
        for (uint256 i = 0; i < amount; i++) {
            miniRock.mint(devAddress, rockNumber);
            miniRocksMintedPerRock[rockNumber]++;
        }
        
        emit DevMiniRocksClaimed(devAddress, rockNumber, amount);
    }

    /// @notice Helper function to check if dev fee applies to a rock
    /// @param rockNumber The rock number to check
    /// @return True if rock is one of the first 10 acquired (dev fee applies)
    function isDevFeeApplicable(uint256 rockNumber) public view returns (bool) {
        return rockAcquisitionOrder[rockNumber] > 0 && rockAcquisitionOrder[rockNumber] <= DEV_FEE_ROCK_LIMIT;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    ADMIN FUNCTIONS                  */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Update the mint price per rock
    /// @param rockNumber The rock number to update the mint price for
    /// @param newPrice The new mint price in wei
    /// @dev Only callable by owner
    function updateMintPricePerRock(uint256 rockNumber, uint256 newPrice) external onlyOwner {
        mintPricePerRock[rockNumber] = newPrice;
        emit MintPriceUpdated(rockNumber, newPrice);
    }

    /// @notice Update the wait period between mints
    /// @param _newPeriod New wait period in seconds
    /// @dev Only callable by owner
    function updateWaitPeriod(uint256 _newPeriod) external onlyOwner {
        waitPeriod = _newPeriod;
        emit WaitPeriodUpdated(_newPeriod);
    }

    /// @notice Updates the hook attached to new pools
    /// @param _hookAddress New Uniswap v4 hook address
    /// @dev Only callable by owner
    function updateHookAddress(address _hookAddress) external onlyOwner {
        hookAddress = _hookAddress;
    }

    /// @notice Update the dev address that can claim dev MiniRocks
    /// @param _devAddress New dev address
    /// @dev Only callable by owner
    function updateDevAddress(address _devAddress) external onlyOwner {
        address oldAddress = devAddress;
        devAddress = _devAddress;
        emit DevAddressUpdated(oldAddress, _devAddress);
    }

    function startQuarry() external payable onlyOwner {
        if (hookAddress == address(0)) revert HookNotSet();
        if (quarryStarted) revert AlreadyStarted();

        // lanzar pebble
        pebble = new Pebble(address(poolManager), hookAddress, msg.sender);

        _loadLiquidity();
        quarryStarted = true;
    }

    function _loadLiquidity() internal {
        loadingLiquidity = true;
        
        Currency currency0 = Currency.wrap(address(0));
        Currency currency1 = Currency.wrap(address(pebble));

        uint24 lpFee = 0;
        int24 tickSpacing = 60;

        uint256 token0Amount = 1; // 1 wei
        uint256 token1Amount = 1_000_000_000 * 10 ** 18;

        uint160 startingPrice = 501082896750095888663770159906816;

        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = int24(175020);

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });
        bytes memory hookData = new bytes(0);

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;

        bytes[] memory params = new bytes[](2);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION),uint8(Actions.SETTLE_PAIR));
        bytes[] memory mintParams = new bytes[](2);
        
        mintParams[0] = abi.encode(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, DEAD_ADDRESS, hookData);
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);
        
        params[0] = abi.encodeWithSelector(
            IPoolInitializer_v4.initializePool.selector,
            pool,
            startingPrice,
            hookData
        );
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, 
            abi.encode(actions, mintParams), 
            block.timestamp + 3600
        );

        uint256 valueToPass = amount0Max;
        pebble.approve(address(permit2), type(uint256).max);
        permit2.approve(address(pebble), address(posm), type(uint160).max, type(uint48).max);
    
        posm.multicall{ value: valueToPass }(params);

        loadingLiquidity = false;
    }

    /// @notice Allows the contract to receive ETH fees from the hook
    receive() external payable {}

    /// @notice Implements ERC721 receiver to accept wrapped rock NFTs
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

