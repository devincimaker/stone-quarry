// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

interface IEtherRockOG {
    function buyRock(uint256 rockNumber) external payable;
    function rocks(uint256 rockNumber) external view returns (address owner, bool currentlyForSale, uint256 price, uint256 timesSold);
    function setRockForSale(uint256 rockNumber, bool forSale) external;
    function giftRock(uint256 rockNumber, address receiver) external;
}