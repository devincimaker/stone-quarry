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
    
    /// @notice Mints a new MiniRock NFT
    /// @param to Address to mint the MiniRock to
    /// @return tokenId The ID of the newly minted token
    /// @dev Only callable by the StoneQuarry contract
    function mint(address to) external returns (uint256 tokenId) {
        if (msg.sender != stoneQuarry) revert OnlyQuarry();
        
        tokenId = ++totalSupply;
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
        
        // Simple placeholder implementation
        // In production, this would return actual metadata
        return "https://minirock.example/metadata.json";
    }
}

