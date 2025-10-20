// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/StoneQuarry.sol";

contract UpgradeStoneQuarry is Script {
    function run() external returns (address newImplementation) {
        // Get the proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        vm.startBroadcast();

        // Deploy the new implementation
        newImplementation = address(new StoneQuarry());
        console.log("New StoneQuarry implementation deployed at:", newImplementation);

        // Get the proxy as a StoneQuarry instance
        StoneQuarry quarry = StoneQuarry(payable(proxy));
        
        // Upgrade to the new implementation
        // Note: This calls upgradeToAndCall from UUPSUpgradeable
        // The empty bytes means no initialization function is called during upgrade
        quarry.upgradeToAndCall(newImplementation, "");
        console.log("Proxy upgraded to new implementation");

        // Verify the upgrade
        console.log("Quarry owner:", quarry.owner());
        console.log("Rocks acquired:", quarry.rocksAcquired());
        
        vm.stopBroadcast();

        return newImplementation;
    }
}

