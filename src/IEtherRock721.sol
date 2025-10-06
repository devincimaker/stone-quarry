// SPDX-License-Identifier: MIT

import "forge-std/interfaces/IERC721.sol";

pragma solidity ^0.8.28;

interface IEtherRock721 is IERC721 {
    function wrap(uint256 tokenId) external;
    function unwrap(uint256 tokenId) external;
    function getRockInfo(uint256 tokenId) external view returns (address, bool, uint256, uint256);
} 