// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "solady/tokens/ERC20.sol";
import { Ownable } from "solady/auth/Ownable.sol";

contract Pebble is ERC20, Ownable {
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /// @notice The name of the ERC20 token
    string private constant _name = "Pebble";
    /// @notice The symbol of the ERC20 token
    string private constant _symbol = "PEBBLE";
    /// @notice Address of the Uniswap V4 hook contract
    address public hookAddress;
    /// @notice Maximum token supply (1 billion tokens)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    /// @notice Uniswap pool manager
    address public immutable poolManagerAddress;

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Token transfer not authorized
    error InvalidTransfer();
    /// @notice Caller is not the authorized hook contract
    error OnlyHook();

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM EVENTS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Emitted when transfer allowance is increased by the hook
    event AllowanceIncreased(uint256 amount);
    /// @notice Emitted when transfer allowance is spent
    event AllowanceSpent(address indexed from, address indexed to, uint256 amount);

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @param _poolManager Address of the Uniswap pool manager
    /// @param _hook Address of the NFTStrategyHook contract
    /// @param _owner Address to setup as owner
    constructor(address _poolManager, address _hook, address _owner) {
        poolManagerAddress = _poolManager;
        hookAddress = _hook;
        
        _initializeOwner(_owner);
        _mint(msg.sender, MAX_SUPPLY);
    }

    function _constantNameHash() internal pure override returns (bytes32 result) {
        return keccak256(bytes(name()));
    }


    function _afterTokenTransfer(address from, address to, uint amount) internal override {
        if (from == address(0)) {
            return;
        }

        if (to == address(0)) {
            return;
        }

        if ((from == poolManager() || to == poolManager())) {
            uint256 transferAllowance = getTransferAllowance();
            require(transferAllowance >= amount, InvalidTransfer());
            assembly {
                let newAllowance := sub(transferAllowance, amount)
                tstore(0, newAllowance)
            }
            emit AllowanceSpent(from, to, amount);
            return;
        }
        revert InvalidTransfer();
    }

    /// @notice Increases the transient transfer allowance for pool operations
    /// @param amountAllowed Amount to add to the current allowance
    /// @dev Only callable by the hook contract, uses transient storage
    function increaseTransferAllowance(uint256 amountAllowed) external {
        if (msg.sender != hookAddress) revert OnlyHook();
        uint256 currentAllowance = getTransferAllowance();
        assembly {
            tstore(0, add(currentAllowance, amountAllowed))
        }
        emit AllowanceIncreased(amountAllowed);
    }
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    BURN FUNCTIONS                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Burns tokens from the caller's balance
    /// @param amount Amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    ADMIN FUNCTIONS                  */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Updates the hook address
    /// @dev Can only be called by the owner
    /// @param _hookAddress New hook address
    function updateHookAddress(address _hookAddress) external onlyOwner {
        hookAddress = _hookAddress;
    }

    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   GETTER FUNCTIONS                  */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */

    /// @notice Gets the current transient transfer allowance
    /// @return transferAllowance The current allowance amount
    /// @dev Reads from transient storage slot 0
    function getTransferAllowance() public view returns (uint256 transferAllowance) {
        assembly {
            transferAllowance := tload(0)
        }
    }

    /// @notice Returns the name of the token
    /// @return The token name ("Pebble")
    function name() public pure override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    /// @return The token symbol ("PEBBLE")
    function symbol() public pure override returns (string memory) {
        return _symbol;
    }


    /// @notice Returns the address of the Uniswap V4 pool manager
    /// @return The pool manager contract address
    function poolManager() public view returns (address) {
        return poolManagerAddress;
    }
}