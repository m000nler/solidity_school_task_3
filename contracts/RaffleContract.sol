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
import "./VRFConsumerBaseUpgradable.sol";

contract RaffleContract is
    Initializable,
    OwnableUpgradeable,
    RaffleAccessControl,
    VRFConsumerBaseUpgradable
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    AggregatorV3Interface private _priceFeed;
    IUniswapV2Router02 private _router;
    address private _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct Participant {
        address userAddress;
        uint256 depositAmount;
        uint256 depositAmountInUsd;
        uint256 winningChance;
        IERC20 depositedToken;
    }

    struct AllowedToken {
        IERC20 token;
        AggregatorV3Interface priceFeed;
    }

    Participant[] private _participants;
    mapping(IERC20 => AggregatorV3Interface) private _allowedTokens;
    mapping(address => bool) private _depositedParticipants;
    uint256 private _totalDeposited;
    uint256 private _totalWethDeposited;
    uint256 private _currentRollId;
    bool private _rollStarted;

    bytes32 public keyHash;
    uint256 public fee;
    uint256 public randomResult;

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
        address rollController,
        address _vrfCoordinator,
        address dexRouter,
        address _link,
        bytes32 _keyHash,
        uint256 _fee
    ) public initializer {
        __VRFConsumerBase_init(_vrfCoordinator, _link);
        __Ownable_init();
        _router = IUniswapV2Router02(dexRouter);
        keyHash = _keyHash;
        fee = _fee;
        for (uint256 i = 0; i < allowedTokens.length; i++) {
            _allowedTokens[allowedTokens[i].token] = allowedTokens[i].priceFeed;
        }
        _grantRole(ROLL_CONTROLLER_ROLE, rollController);
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

        (, int256 tokenInUsd, , , ) = _allowedTokens[token].latestRoundData();

        _depositedParticipants[msg.sender] = true;
        _totalDeposited += uint256(tokenInUsd);
        _participants.push(
            Participant(msg.sender, amount, uint256(tokenInUsd), 0, token)
        );

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

        emit Deposit(msg.sender, token, amount);
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

        _calculateWinningChances();
        _requestRandomness();

        uint256 firstRandom = randomResult;
        _requestRandomness();

        uint256 secondRandom = randomResult;
        Participant memory winner;

        for (uint256 i = 0; i < _participants.length; i++) {
            if (
                _participants[i].winningChance > firstRandom &&
                _participants[i].winningChance < secondRandom &&
                _participants[i].winningChance > winner.winningChance
            ) {
                winner = _participants[i];
            }
        }

        _rollStarted = false;
        _totalWethDeposited = 0;
        _totalDeposited = 0;
        delete _participants;

        IERC20(_weth).transfer(winner.userAddress, _totalWethDeposited);

        emit RollEnded(
            _currentRollId,
            block.timestamp,
            winner.userAddress,
            winner.depositAmount
        );

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

    function _calculateWinningChances() private {
        for (uint256 i = 0; i < _participants.length; i++) {
            uint256 chance = _participants[i].depositAmountInUsd.mul(100).div(
                _totalDeposited
            );
            _participants[i].winningChance = chance;
        }
    }

    // solhint-disable-next-line no-unused-vars, private-vars-leading-underscore
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness.mod(100).add(1);
    }

    function _requestRandomness() private returns (bytes32) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK to fulfill request"
        );

        return requestRandomness(keyHash, fee);
    }
}
