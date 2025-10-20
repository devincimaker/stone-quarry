// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { StoneQuarry } from "../src/StoneQuarry.sol";

contract StoneQuarryUpgradeableTest is Test {
    StoneQuarry public quarry;
    address public implementation;
    address public proxy;

    address private constant posm = address(0x1);
    address private constant permit2 = address(0x2);
    address private constant poolManager = address(0x3);
    address private constant dev = address(0x4);
    address private owner = address(this);

    function setUp() public {
        // Deploy implementation
        implementation = address(new StoneQuarry());
        
        // Deploy proxy with initialization
        proxy = address(new ERC1967Proxy(
            implementation,
            abi.encodeCall(StoneQuarry.initialize, (posm, permit2, poolManager, dev))
        ));
        
        // Cast proxy to StoneQuarry interface
        quarry = StoneQuarry(payable(proxy));
    }

    function test_Initialization() public view {
        // Verify initialization worked correctly
        assertEq(quarry.devAddress(), dev, "Dev address should match");
        assertEq(quarry.owner(), owner, "Owner should be deployer");
        assertNotEq(address(quarry.miniRock()), address(0), "MiniRock should be deployed");
        assertEq(quarry.rocksAcquired(), 0, "Should start with no rocks acquired");
        assertEq(quarry.waitPeriod(), 1 days, "Wait period should be 1 day");
    }

    function test_CannotReinitialize() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        quarry.initialize(posm, permit2, poolManager, dev);
    }

    function test_OwnerCanUpdateDevAddress() public {
        address newDev = address(0x5);
        
        quarry.updateDevAddress(newDev);
        assertEq(quarry.devAddress(), newDev, "Dev address should be updated");
    }

    function test_NonOwnerCannotUpdateDevAddress() public {
        address newDev = address(0x5);
        address nonOwner = address(0x6);
        
        vm.prank(nonOwner);
        vm.expectRevert();
        quarry.updateDevAddress(newDev);
    }

    function test_OwnerCanAuthorizeUpgrade() public {
        // Deploy new implementation
        address newImplementation = address(new StoneQuarry());
        
        // Owner can upgrade
        quarry.upgradeToAndCall(newImplementation, "");
        
        // Verify state is preserved after upgrade
        assertEq(quarry.devAddress(), dev, "Dev address should be preserved");
        assertEq(quarry.owner(), owner, "Owner should be preserved");
    }

    function test_NonOwnerCannotUpgrade() public {
        // Deploy new implementation
        address newImplementation = address(new StoneQuarry());
        address nonOwner = address(0x6);
        
        // Non-owner cannot upgrade
        vm.prank(nonOwner);
        vm.expectRevert();
        quarry.upgradeToAndCall(newImplementation, "");
    }

    function test_ProxyDelegatesCallsToImplementation() public view {
        // Verify calls to proxy are delegated to implementation
        assertEq(quarry.DEV_FEE_PERCENTAGE(), 10, "Constants should be accessible");
        assertEq(quarry.DEV_FEE_ROCK_LIMIT(), 10, "Constants should be accessible");
        assertEq(quarry.LOCK_PERIOD(), 30 days, "Constants should be accessible");
    }
}

