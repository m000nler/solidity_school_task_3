// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./RaffleAccessControl.sol";
import "./CustomVRFConsumerBaseV2.sol";

contract RaffleContract is
    Initializable,
    OwnableUpgradeable,
    RaffleAccessControl
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    AggregatorV3Interface private _priceFeed;
    IUniswapV2Router02 private _router;
    address private _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct Entry {
        address user;
        uint256 depositedAmount;
    }

    struct AllowedToken {
        IERC20 token;
        AggregatorV3Interface priceFeed;
    }

    uint256 public randomNumber;
    Entry[] private _participants;
    mapping(IERC20 => AggregatorV3Interface) private _allowedTokens;
    mapping(address => bool) private _depositedParticipants;
    uint256 private _totalDeposited;
    uint256 private _totalWethDeposited;
    uint256 private _currentRollId;
    bool private _rollStarted;

    CustomVRFConsumerBaseV2 _consumer;

    uint256[15] private __gap;

    event Deposit(address indexed user, IERC20 token, uint256 amount);
    event RollStarted(uint256 indexed rollId, uint256 timestamp);
    event RollEnded(
        uint256 indexed rollId,
        uint256 timestamp,
        address winner,
        uint256 winAmount
    );

    function initialize(
        AllowedToken[] memory allowedTokens,
        CustomVRFConsumerBaseV2 consumer,
        address rollController,
        address dexRouter
    ) public initializer {
        __init(allowedTokens, consumer, rollController, dexRouter);
    }

    // solhint-disable private-vars-leading-underscore
    function __init(
        AllowedToken[] memory allowedTokens,
        CustomVRFConsumerBaseV2 consumer,
        address rollController,
        address dexRouter
    ) public onlyInitializing {
        __Ownable_init();
        _router = IUniswapV2Router02(dexRouter);
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            _allowedTokens[allowedTokens[i].token] = allowedTokens[i].priceFeed;
        }
        _grantRole(ROLL_CONTROLLER_ROLE, rollController);
        _consumer = consumer;
    }

    function deposit(IERC20 token, uint256 amount) public {
        require(_rollStarted, "Roll hasn't started");
        require(
            _allowedTokens[token] != AggregatorV3Interface(address(0)),
            "This token is not allowed"
        );
        require(amount > 0, "Cannot deposit zero");
        require(
            !_depositedParticipants[msg.sender],
            "User has already deposited"
        );
        require(!_consumer.locked(), "Locked");

        _consumer.changeLock(true);

        (, int256 tokenInUsd, , , ) = _allowedTokens[token].latestRoundData();

        _depositedParticipants[msg.sender] = true;
        _totalDeposited += uint256(tokenInUsd);

        SafeERC20.safeTransferFrom(
            token,
            address(msg.sender),
            address(this),
            amount
        );

        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = _weth;

        uint256 amountInWeth = _router.swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp + 15
        )[1];

        _totalWethDeposited += amountInWeth;

        if (_participants[_participants.length].depositedAmount > 0) {
            _participants.push(
                Entry(
                    msg.sender,
                    amountInWeth +
                        1 +
                        _participants[_participants.length].depositedAmount
                )
            );
        } else {
            _participants.push(Entry(msg.sender, amountInWeth));
        }

        emit Deposit(msg.sender, token, amount);

        _consumer.changeLock(false);
    }

    function startRoll() public onlyRole(ROLL_CONTROLLER_ROLE) returns (bool) {
        require(!_rollStarted, "Roll has started");
        _rollStarted = true;
        _currentRollId = _currentRollId + 1;

        emit RollStarted(_currentRollId, block.timestamp);

        return true;
    }

    function endRoll() public onlyRole(ROLL_CONTROLLER_ROLE) returns (bool) {
        require(_rollStarted, "Roll hasn't started");
        require(_participants.length > 0, "No participants");
        require(!_consumer.locked(), "Locked");

        randomNumber = _consumer.randomNumber();
        _consumer.changeLock(true);

        Entry memory winner;

        for (uint256 i = 0; i < _participants.length; i++) {
            if (_participants[i].depositedAmount >= randomNumber) {
                winner = _participants[i];
                break;
            }
        }

        IERC20(_weth).transfer(winner.user, _totalWethDeposited);

        emit RollEnded(
            _currentRollId,
            block.timestamp,
            winner.user,
            _totalWethDeposited
        );

        _consumer.changeLock(false);

        return true;
    }

    function addAllowedTokens(IERC20 token, AggregatorV3Interface priceFeed)
        public
        onlyOwner
    {
        require(
            address(token) != address(0),
            "Cannot allow zero address token"
        );
        require(address(priceFeed) != address(0), "Price feed cannot be zero");
        _allowedTokens[token] = priceFeed;
    }
}
