// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract CustomVRFConsumerBaseV2 is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface private _vrfCoordinator;
    bytes32 private _keyHash;
    uint64 private _subscriptionId;
    uint256 public randomNumber;
    uint256 private _maxValue;

    bool private _locked;

    constructor(
        address vrfCoordinator,
        bytes32 keyHash,
        uint64 subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinator) {
        _vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        _keyHash = keyHash;
        _subscriptionId = subscriptionId;
    }

    function requestRandomWords(
        uint16 confirmations,
        uint32 maxGasLimit,
        uint256 maxValue
    ) public returns (uint256) {
        require(!_locked, "VRF is locked");
        _maxValue = maxValue;

        return
            _vrfCoordinator.requestRandomWords(
                _keyHash,
                _subscriptionId,
                confirmations,
                maxGasLimit,
                1
            );
    }

    // solhint-disable private-vars-leading-underscore
    function fulfillRandomWords(uint256, uint256[] memory _randomWords)
        internal
        override
    {
        randomNumber = ((_randomWords[0] % _maxValue) + 1);
    }

    function changeLock(bool newLock) public {
        _locked = newLock;
    }
}
