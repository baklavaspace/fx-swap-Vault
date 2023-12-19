// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IBRTVault is IERC20Upgradeable {

    function updateRewards() external;

    function checkReward() external view returns (uint256);
    
    function totalSupply() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function asset() external view returns (address);
    
    function claimable(address user) external view returns (uint256);

    function userInfo(address account) external view returns (
        uint256 claimableReward,
        uint256 previousCumulatedRewardPerToken
    );
}