// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { Quarry } from "../src/Quarry.sol";
import { Pebble } from "../src/Pebble.sol";

contract QuarryTest is Test {
    Quarry public quarry;

    address private constant posm = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address private constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant poolManager = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant dev = address(0x02);

    function setUp() public {
        quarry = new Quarry(
            posm,
            permit2,
            poolManager,
            dev
        );
    }

    function test_Pebble() public view {
        uint256 expectedSupply = 1_000_000_000 * 10 ** 18;

        Pebble pebble = quarry.pebble();

        assertEq(pebble.totalSupply(), expectedSupply);
        assertEq(pebble.balanceOf(address(quarry)), expectedSupply);
    }
}
