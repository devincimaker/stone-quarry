// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract GetInitialPrice is Script {
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function getSqrtPriceX96(uint256 token1Amount, uint256 token0Amount) internal pure returns (uint160) {
        // Calculate: sqrt(token1 / token0) * 2^96
        // To avoid precision loss, we do: sqrt(token1 * 2^192 / token0)
        // This is equivalent to: sqrt(token1/token0) * 2^96
        
        uint256 ratioX192 = (token1Amount << 192) / token0Amount;
        uint256 sqrtPriceX96 = sqrt(ratioX192);
        
        return uint160(sqrtPriceX96);
    }

    function run() external view {
        uint160 priceExample3 = getSqrtPriceX96(2 * 10 ** 18, 1_000_000_000 * 10 ** 18);
        console.log("sqrtPriceX96:", priceExample3);
    }
}