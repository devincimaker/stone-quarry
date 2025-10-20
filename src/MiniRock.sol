// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import { ERC721 } from "solady/tokens/ERC721.sol";

contract MiniRock is ERC721 {
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                      CONSTANTS                      */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice The address that can mint new MiniRocks (StoneQuarry)
    address public immutable stoneQuarry;
    
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   STATE VARIABLES                   */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice The total number of MiniRocks minted
    uint256 public totalSupply;
    /// @notice Maps tokenId to the source rock number it was derived from
    mapping(uint256 => uint256) public sourceRockNumber;
    
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                    CUSTOM ERRORS                    */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice Only the StoneQuarry contract can mint
    error OnlyQuarry();
    
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                     CONSTRUCTOR                     */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice Constructor sets the StoneQuarry address
    /// @param _stoneQuarry Address of the StoneQuarry contract
    constructor(address _stoneQuarry) {
        stoneQuarry = _stoneQuarry;
    }
    
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   MINTING FUNCTIONS                 */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    // TODO: Prevent maximium total supply to 10k mini rocks. That wouls happen if all 100 rocks are mined.
    /// @notice Mints a new MiniRock NFT
    /// @param to Address to mint the MiniRock to
    /// @param rockNumber The source rock number this MiniRock is derived from
    /// @return tokenId The ID of the newly minted token
    /// @dev Only callable by the StoneQuarry contract
    function mint(address to, uint256 rockNumber) external returns (uint256 tokenId) {
        if (msg.sender != stoneQuarry) revert OnlyQuarry();
        
        tokenId = ++totalSupply;
        sourceRockNumber[tokenId] = rockNumber;
        _mint(to, tokenId);
    }
    
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    /*                   METADATA FUNCTIONS                */
    /* ™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™™ */
    
    /// @notice Returns the name of the NFT collection
    function name() public pure override returns (string memory) {
        return "MiniRock";
    }
    
    /// @notice Returns the symbol of the NFT collection
    function symbol() public pure override returns (string memory) {
        return "MINIROCK";
    }
    
    /// @notice Returns the token URI for a given token ID
    /// @param tokenId The token ID to get the URI for
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Ensure the token exists
        ownerOf(tokenId);
        
        uint256 rockNum = sourceRockNumber[tokenId];
        
        // Create basic JSON metadata with rock number
        // In production, this would include actual SVG and more metadata
        return string(abi.encodePacked(
            "data:application/json;utf8,{\"name\":\"MiniRock #",
            _toString(tokenId),
            "\",\"description\":\"A fragment from EtherRock #",
            _toString(rockNum),
            "\",\"sourceRock\":",
            _toString(rockNum),
            "}"
        ));
    }
    
    /// @notice Converts uint256 to string
    /// @param value The value to convert
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

