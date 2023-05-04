// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract RaffleAccessControl is AccessControlUpgradeable {
    bytes32 public constant ROLL_CONTROLLER_ROLE =
        keccak256("ROLL_CONTROLLER_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
