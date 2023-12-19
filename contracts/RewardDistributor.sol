// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IBRTVault.sol";
import "./common/Governable.sol";

contract RewardDistributor is Initializable, UUPSUpgradeable, Governable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public rewardToken;
    uint256 public tokensPerInterval;
    uint256 public startDistributionTime;
    
    TrackerInfo[] public trackerInfo;
    mapping(address => uint256) public trackerId1;         // trackerId1 count from 1, subtraction 1 before using with trackerInfo
    uint256 public totalAllocPoint;

    event Distribute(uint256 amount);
    event TokensPerIntervalChange(uint256 amount);

    struct TrackerInfo {
        uint256 lastDistributionTime;
        address rewardTracker;
        uint256 allocPoint;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**************************************** Core Functions ****************************************/

    function distribute(address _rewardTracker) external returns (uint256) {
        require(msg.sender == _rewardTracker, "RewardDistributor: invalid msg.sender");
        uint256 tid = trackerId1[_rewardTracker];
        require(tid !=0, "!valid rewardTracker");
        
        // trackerId count from 1, need to subtract 1 to get trackerInfo data.
        tid -= 1;
        uint256 amount = pendingRewards(trackerInfo[tid].rewardTracker);
        if (amount == 0) { return 0; }

        trackerInfo[tid].lastDistributionTime = block.timestamp;

        uint256 balance = IERC20Upgradeable(rewardToken).balanceOf(address(this));
        if (amount > balance) { amount = balance; }

        IERC20Upgradeable(rewardToken).safeTransfer(trackerInfo[tid].rewardTracker, amount);

        emit Distribute(amount);
        return amount;
    }

    function massUpdateRewards() public {
        uint256 length = trackerInfo.length;
        for (uint256 tid = 0; tid < length; ++tid) {
            IBRTVault(trackerInfo[tid].rewardTracker).updateRewards();
        }
    }

    /**************************************** View Functions ****************************************/

    function pendingRewards(address _rewardTracker) public view returns (uint256) {
        uint256 tid = trackerId1[_rewardTracker];
        require(tid !=0, "!valid rewardTracker");
        
        // trackerId count from 1, need to subtract 1 to get trackerInfo data.
        tid -= 1;
        if (block.timestamp <= trackerInfo[tid].lastDistributionTime) {
            return 0;
        }

        uint256 timeDiff = block.timestamp.sub(trackerInfo[tid].lastDistributionTime);
        return tokensPerInterval.mul(timeDiff).mul(trackerInfo[tid].allocPoint).div(totalAllocPoint);
    }

    function getRewardTrackerLength() public view returns (uint256) {
        return trackerInfo.length;
    }

    /**************************************** Only Admin/Governor Functions ****************************************/

    function updateStartDistributionTime() external onlyRole(GOVERNOR_ROLE) {
        startDistributionTime = block.timestamp;
    }

    function massUpdateLastDistributionTime() public onlyRole(GOVERNOR_ROLE) {
        uint256 length = trackerInfo.length;
        for (uint256 tid = 0; tid < length; ++tid) {
            trackerInfo[tid].lastDistributionTime = block.timestamp;
        }
    }

    function setTokensPerInterval(uint256 _amount) external onlyRole(GOVERNOR_ROLE) {
        require(startDistributionTime != 0, "RewardDistributor: invalid startDistributionTime");
        massUpdateRewards();
        
        tokensPerInterval = _amount;
        emit TokensPerIntervalChange(_amount);
    }

    function add(
        uint256 _allocPoint,
        address _rewardTracker,
        bool _withUpdate
    ) external onlyRole(GOVERNOR_ROLE) {
        require(trackerId1[_rewardTracker] == 0, "pool Added");
        if (_withUpdate) {
            massUpdateRewards();
        }
        uint256 lastDistributionTime = block.timestamp > startDistributionTime ? block.timestamp : startDistributionTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        trackerInfo.push(
            TrackerInfo({rewardTracker : _rewardTracker, allocPoint : _allocPoint, lastDistributionTime : lastDistributionTime })
        );
        trackerId1[_rewardTracker] = trackerInfo.length;
    }

    function setAllocPoint(
        uint256 _tid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyRole(GOVERNOR_ROLE) {
        if (_withUpdate) {
            massUpdateRewards();
        }
        totalAllocPoint = totalAllocPoint.sub(trackerInfo[_tid].allocPoint).add(_allocPoint);
        trackerInfo[_tid].allocPoint = _allocPoint;
    }

    /**************************************** Only Owner Functions ****************************************/

    function recoverToken(
        address token,
        uint256 amount,
        address _recipient
    ) external onlyRole(OWNER_ROLE) {
        require(_recipient != address(0), "Send to zero address");
        IERC20Upgradeable(token).safeTransfer(_recipient, amount);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(OWNER_ROLE) {}

    /**************************************************************
     * @dev Initialize the states
     *************************************************************/    
    function initialize(
        address _rewardToken, address _owner, address _governor
    ) public initializer {
        rewardToken = _rewardToken;
        
        __Governable_init(_owner, _governor);
        __UUPSUpgradeable_init();
    }
}