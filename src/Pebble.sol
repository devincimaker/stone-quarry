// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "solady/tokens/ERC20.sol";

contract Pebble is ERC20 {
    string private constant _name = "Pebble";
    string private constant _symbol = "PEBBLE";

    /// @notice Token transfer not authorized
    error InvalidTransfer();
    /// @notice Caller is not the authorized hook contract
    error OnlyHook();

    /// @notice Emitted when transfer allowance is increased by the hook
    event AllowanceIncreased(uint256 amount);
    /// @notice Emitted when transfer allowance is spent
    event AllowanceSpent(address indexed from, address indexed to, uint256 amount);

    address public hookAddress;
    address public immutable poolManagerAddress;

    constructor(address _poolManager) {
        poolManagerAddress = _poolManager;
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }

    function setHookAddress(address _hookAddress) external {
        require(hookAddress == address(0), "Hook already set");
        hookAddress = _hookAddress;
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function _constantNameHash() internal pure override returns (bytes32 result) {
        return keccak256(bytes(name()));
    }

    function poolManager() public view returns (address) {
        return poolManagerAddress;
    }

    function _afterTokenTransfer(address from, address to, uint amount) internal override {
        if (from == address(0)) {
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

    /// @notice Gets the current transient transfer allowance
    /// @return transferAllowance The current allowance amount
    /// @dev Reads from transient storage slot 0
    function getTransferAllowance() public view returns (uint256 transferAllowance) {
        assembly {
            transferAllowance := tload(0)
        }
    }
}