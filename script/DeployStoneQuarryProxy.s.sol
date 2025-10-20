// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/StoneQuarry.sol";

contract DeployStoneQuarryProxy is Script {
    function run() external returns (address proxy, address implementation) {
        // Get deployment parameters from environment or use defaults
        address posm = vm.envOr("POSM_ADDRESS", address(0));
        address permit2 = vm.envOr("PERMIT2_ADDRESS", address(0));
        address poolManager = vm.envOr("POOL_MANAGER_ADDRESS", address(0));
        address devAddress = vm.envOr("DEV_ADDRESS", msg.sender);

        require(posm != address(0), "POSM_ADDRESS not set");
        require(permit2 != address(0), "PERMIT2_ADDRESS not set");
        require(poolManager != address(0), "POOL_MANAGER_ADDRESS not set");

        vm.startBroadcast();

        // Deploy the implementation contract
        implementation = address(new StoneQuarry());
        console.log("StoneQuarry implementation deployed at:", implementation);

        // Encode the initializer function call
        bytes memory initData = abi.encodeCall(
            StoneQuarry.initialize,
            (posm, permit2, poolManager, devAddress)
        );

        // Deploy the ERC1967 proxy
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("StoneQuarry proxy deployed at:", proxy);

        // Verify the proxy is properly initialized
        StoneQuarry quarry = StoneQuarry(payable(proxy));
        console.log("Quarry owner:", quarry.owner());
        console.log("Dev address:", quarry.devAddress());
        
        vm.stopBroadcast();

        return (proxy, implementation);
    }
}

