// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IEtherRock {
    function getRockInfo(uint rockNumber) external view returns (address, bool, uint, uint);
    function latestNewRockForSale() external view returns (uint);
}

contract CheckEtherRocks is Script {
    IEtherRock public etherRock = IEtherRock(0x41f28833Be34e6EDe3c58D1f597bef429861c4E2);
    
    function run() external view {
        console.log("=== Checking EtherRocks for Sale ===");
        console.log("");
        
        uint rocksForSaleCount = 0;
        
        // There are 100 rocks total (0-99)
        for (uint i = 0; i < 100; i++) {
            (address owner, bool currentlyForSale, uint price, uint timesSold) = etherRock.getRockInfo(i);
            
            if (currentlyForSale) {
                rocksForSaleCount++;
                
                // Convert wei to ETH with 4 decimal places
                uint ethWhole = price / 1e18;
                uint ethDecimal = (price % 1e18) / 1e14; // Get 4 decimal places
                
                console.log("Rock #%s", i);
                console.log("  Price: %s.%s ETH", ethWhole, ethDecimal);
                console.log("  Price (wei): %s", price);
                console.log("  Owner: %s", owner);
                console.log("  Times Sold: %s", timesSold);
                console.log("");
            }
        }
        
        console.log("=== Summary ===");
        console.log("Total Rocks For Sale: %s / 100", rocksForSaleCount);
    }
}

