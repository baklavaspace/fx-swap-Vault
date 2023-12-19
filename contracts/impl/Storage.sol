// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.2;
pragma abicoder v2;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {Types} from "../lib/Types.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import "../interfaces/IMasterChefV2.sol";

/**
 * @title LS1Storage
 * @author MarginX
 *
 * @dev Storage contract. Contains or inherits from all contract with storage.
 */
abstract contract Storage is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ Rewards Accounting ============

    /// @dev The fee treasury contract address.
    address public feeTreasury; 

    /// @dev The reward distributor contract address.
    address public distributor;

    /// @dev The cumulative rewards earned per staked token.
    uint256 public cumulativeRewardPerToken;

    /// @dev The user's rewards info
    mapping(address => Types.UserInfo) public userInfo; 
    

    // ============ Staking Strategy setting ============
    
    /// @dev The staking farm contract 
    IMasterChefV2 public stakingContract;

    /// @dev The fx swap router
    IRouter public router;

    /// @dev The staking farm reward token.
    IERC20Upgradeable public poolRewardToken;

    /// @dev The staking farm pool's bonus reward token.
    IERC20Upgradeable[] public bonusRewardTokens;

    /// @dev The staking farm poolId
    uint256 public stakingFarmID;

    /// @dev The minimum reward tokens to reinvest.
    uint256 public minTokensToReinvest;

    /// @dev Indicates whether a deposit is restricted.
    bool public depositsEnabled;

    /// @dev Indicates whether a restaking to farm is restricted.
    bool public restakingEnabled;


    // ============ Fee setting ============

    /// @dev The protocol fee for rewards.
    uint256 internal feeOnReward;

    /// @dev The compounder fee for rewards.
    uint256 internal feeOnCompounder;

    /// @dev The withdrawal fee for rewards.
    uint256 internal feeOnWithdrawal;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
