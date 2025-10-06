// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import "./IEtherRockOG.sol";
import "./IEtherRock721.sol";

// TO-DO: How do you buy rocks? I know from opensea is an option.
// When there's enough funds, anyone should be able to call a function to buy a rock if it's possible from the contract
// Any rock should be able to sell itself into the contract.
// I could write a function to find the cheapest rock and buy that one

// Working on the most important thing. How do I get the contract to buy a rock.
// I can buy by hitting the buyRock() function in the OG contract.

// I should do a script now to check which rocks are for sale and at what price.

// I need to make it so that people can buy a rock from both the old one and the new one. 
// Also people should be able to sell whatever rock they have into the contract's work.

// Team reward: When I mint small rocks, a small amount goes to me. When I mint pebbles a small amount goes to me.

// Cada nueva roca da menos supply de pebble. Dentro de cada roca mientras antes entres mas pebble te da. (Y mas open editions)

// Should the person that calls the buy function get a small reward?

// Hacer la version inicial que es linear. La gente deposita y se puede intentar comprar en cualquier momento, mientras sea valido. 
// Se imprimen una cantidad de editions a la gente que participo de forma lineal. Puedo tal vez hacer que pongan un minimo? 
    // I would like to have a bonding curve with a small increase dictate how much tokens you get from the eventual split
    // I would like for people to start auctions and other people can propose their rock? 

contract Quarry {
    IEtherRockOG public constant OG_ETHERROCK = IEtherRockOG(0x41f28833Be34e6EDe3c58D1f597bef429861c4E2);
    IEtherRock721 public constant WRAPPED_ETHERROCK = IEtherRock721(0xA3F5998047579334607c47a6a2889BF87A17Fc02); 

    event RockBought(uint256 indexed rockNumber, uint256 price);

    error RockNotForSale(uint256 rockNumber);
    error InsufficientBalance(uint256 required, uint256 available);
    error RockNotOwned(uint256 rockNumber);

    function buyRockFromOG(uint256 rockNumber) external {
        (, bool currentlyForSale, uint256 price, ) = OG_ETHERROCK.rocks(rockNumber);

        if (!currentlyForSale) revert RockNotForSale(rockNumber);
        if (address(this).balance < price) revert InsufficientBalance(price, address(this).balance);
    
        OG_ETHERROCK.buyRock{value: price}(rockNumber);

        (address newOwner, , , ) = OG_ETHERROCK.rocks(rockNumber);
        if (newOwner != address(this)) {
            revert RockNotOwned(rockNumber);
        }

        emit RockBought(rockNumber, price);
    }

    // 


    // function startBreakingRock() {

    // }

    receive() external payable {}
}

