// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {IMasterChefV2} from "./interfaces/IMasterChefV2.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

import {Types} from './lib/Types.sol';
import {BaseVault} from "./vaults/BaseVault.sol";

// BavaCompoundVault is the compoundVault of FX-Swap Farm. It will autocompound user LP.
// Note that it's ownable and the owner wields tremendous power.

contract FXSwapStrategyVaultBavaBonus is
    Initializable,
    UUPSUpgradeable,
    BaseVault
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ============ Constants ============
    
    address internal constant WFX = 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd;     // WFX mainnet: 0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd; WFX testnet: 0x3452e23F9c4cC62c70B7ADAd699B264AF3549C19
    address internal constant BAVA = 0xc8B4d3e67238e38B20d38908646fF6F4F48De5EC;    // BAVA mainnet: 0xc8B4d3e67238e38B20d38908646fF6F4F48De5EC; BAVA testnet: 0xc7e56EEc629D3728fE41baCa2f6BFc502096f94E
    uint256 internal constant PRECISION = 1e30;

    // ============ Storage ============

    uint256 public bavaBonusReward;                // BAVA bonus reward token from restaking farm contract

    // ============ Events ============

    event Claim(address indexed account, uint256 tokenAmount);
    event EmergencyWithdraw(address indexed owner, uint256 assets, uint256 shares);
    event EmergencyWithdrawVault(address indexed owner, bool disableDeposits);
    event DepositsEnabled(bool newValue);
    event RestakingEnabled(bool newValue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /********************************* INITIAL SETUP *********************************/
    /**
     * @dev Init the vault. Support LP from Fx-Swap masterChef.
     */
    function initVault(
        address _stakingContract,
        uint256 _stakingFarmID,
        address _poolRewardToken,
        IERC20Upgradeable[] memory _bonusRewardTokens,
        address _router,
        address _feeTreasury,
        address _distributor,
        Types.StrategySettings memory _strategySettings
    ) external onlyRole(OWNER_ROLE) {
        require(address(_stakingContract) != address(0), "0 Add");

        stakingContract = IMasterChefV2(_stakingContract);
        stakingFarmID = _stakingFarmID;
        poolRewardToken = IERC20Upgradeable(_poolRewardToken);
        bonusRewardTokens = _bonusRewardTokens;
        router = IRouter(_router);
        feeTreasury = _feeTreasury;
        distributor = _distributor;

        minTokensToReinvest = _strategySettings.minTokensToReinvest;
        feeOnReward = _strategySettings.feeOnReward;
        feeOnCompounder = _strategySettings.feeOnCompounder;
        feeOnWithdrawal = _strategySettings.feeOnWithdrawal;
        
        depositsEnabled = true;
        restakingEnabled = true;
    }

    /**
     * @notice Approve tokens for use in Strategy, Restricted to avoid griefing attacks
     */
    function approveAllowances(uint256 _amount) external onlyRole(OWNER_ROLE) {
        address depositToken = asset();
        if (address(stakingContract) != address(0)) {
            IERC20Upgradeable(depositToken).approve(
                address(stakingContract),
                _amount
            );
        }

        if (address(router) != address(0)) {
            IERC20Upgradeable(WFX).approve(address(router), _amount);
            IERC20Upgradeable(IPair(depositToken).token0()).approve(address(router), _amount);
            IERC20Upgradeable(IPair(depositToken).token1()).approve(address(router), _amount);
            IERC20Upgradeable(depositToken).approve(address(router), _amount);
            poolRewardToken.approve(address(router), _amount);

            uint256 rewardLength = bonusRewardTokens.length;
            uint256 i = 0;
            for (i; i < rewardLength; i++) {
                bonusRewardTokens[i].approve(address(router), _amount);
            }
        }
    }

    /****************************************** FARMING CORE FUNCTION ******************************************/
    /**
     * @notice Deposit LP tokens to staking farm.
     */
    function deposit(uint256 _assets, address _receiver) public nonReentrant override returns (uint256) {
        require(depositsEnabled == true, "Deposit !enabled");

        address depositToken = asset();
        
        uint256 estimatedTotalReward = checkReward();
        if (estimatedTotalReward > minTokensToReinvest) {
            _compound();
        }

        _claim(msg.sender, _receiver);

        uint256 shares = super.deposit(_assets, _receiver);

        if (restakingEnabled == true) {
            uint256 stakeAmount = IERC20Upgradeable(depositToken).balanceOf(address(this));
            _depositTokens(stakeAmount);
        }

        return shares;
    }

    // Withdraw LP tokens from BavaMasterFarmer. argument "_shares" is receipt amount.
    function redeem(uint256 _shares, address _receiver, address _owner) public nonReentrant override returns (uint256) {
        uint256 depositTokenAmount = previewRedeem(_shares);
        uint256 assets;

        address depositToken = asset();
        uint256 estimatedTotalReward = checkReward();
        if (estimatedTotalReward > minTokensToReinvest) {
            _compound();
        }

        _claim(msg.sender, msg.sender);

        if (depositTokenAmount > 0) {
            _withdrawTokens(depositTokenAmount);
            assets = super.redeem(_shares, _receiver, _owner);
        }

        if (restakingEnabled == true) {
            uint256 stakeAmount = IERC20Upgradeable(depositToken).balanceOf(address(this));
            _depositTokens(stakeAmount);
        }

        return assets;
    }

    // EMERGENCY ONLY. Withdraw without caring about rewards.
    // This has the same 25% fee as same block withdrawals and ucer receipt record set to 0 to prevent abuse of thisfunction.
    function emergencyRedeem() external nonReentrant {
        Types.UserInfo storage user = userInfo[msg.sender];
        uint256 userBRTAmount = balanceOf(msg.sender);

        require(userBRTAmount > 0, "#>0");

        _updateRewards(msg.sender);
        user.claimableReward = 0;

        address depositToken = asset();

        // Reordered from Sushi function to prevent risk of reentrancy
        uint256 assets = _convertToAssets(userBRTAmount, MathUpgradeable.Rounding.Down);
        assets -= (assets * 2500) / BIPS_DIVISOR;

        _withdrawTokens(assets);

        _burn(msg.sender, userBRTAmount);
        IERC20Upgradeable(depositToken).safeTransfer(address(msg.sender), assets);

        emit EmergencyWithdraw(msg.sender, assets, userBRTAmount);
    }

    function compound() external nonReentrant {
        uint256 estimatedTotalReward = checkReward();
        require(estimatedTotalReward >= minTokensToReinvest, "#<MinInvest");

        uint256 liquidity = _compound();

        if (restakingEnabled == true) {
            _depositTokens(liquidity);
        }
    }

    // Update reward variables of the given vault to be up-to-date.
    function claimReward(address receiver) external nonReentrant returns (uint256) {
        return _claim(msg.sender, receiver);
    }

    function updateRewards() external nonReentrant {
        _updateRewards(address(0));
    }

    /**************************************** Internal FUNCTIONS ****************************************/
    // Deposit LP token to 3rd party restaking farm
    function _depositTokens(uint256 amount) internal {
        if(amount > 0) {
            uint256 rewardBalBefore = IERC20Upgradeable(BAVA).balanceOf(address(this));

            stakingContract.deposit(
                stakingFarmID,
                amount
            );

            _calRewardAfter(rewardBalBefore);
        }
    }

    // Withdraw LP token to 3rd party restaking farm
    function _withdrawTokens(uint256 amount) internal {
        if(amount > 0) {
            uint256 rewardBalBefore = IERC20Upgradeable(BAVA).balanceOf(address(this));

            (uint256 depositAmount, ) = stakingContract.userInfo(
                stakingFarmID,
                address(this)
            );

            if (depositAmount > 0) {
                uint256 pendingRewardAmount = stakingContract.pendingReward(stakingFarmID, address(this));

                if (pendingRewardAmount == 0) {
                    stakingContract.emergencyWithdraw(
                        stakingFarmID
                    );
                } else if (depositAmount >= amount) {
                    stakingContract.withdraw(
                        stakingFarmID,
                        amount
                    );
                } else {
                    stakingContract.withdraw(
                        stakingFarmID,
                        depositAmount
                    );
                }
            }
            _calRewardAfter(rewardBalBefore);
        }
    }

    // Claim LP restaking reward from 3rd party restaking contract
    function _getReinvestReward() internal {
        uint256 rewardBalBefore = IERC20Upgradeable(BAVA).balanceOf(address(this));
        uint256 pendingRewardAmount = stakingContract.pendingReward(stakingFarmID, address(this));

        if (pendingRewardAmount > 0) {
            stakingContract.withdraw(
                stakingFarmID,
                0
            );
        }
        _calRewardAfter(rewardBalBefore);
    }

    function _calRewardAfter(uint256 _rewardBalBefore) private {
        uint256 rewardBalAfter = 0;
        uint256 diffRewardBal = 0;

        rewardBalAfter = IERC20Upgradeable(BAVA).balanceOf(address(this));
        if (rewardBalAfter >= _rewardBalBefore) {
            diffRewardBal = rewardBalAfter - _rewardBalBefore;
            bavaBonusReward += diffRewardBal;
        } else {
            diffRewardBal = _rewardBalBefore - rewardBalAfter;
            bavaBonusReward -= diffRewardBal;
        }
    }

    // Claim bonus BAVA reward from Baklava
    function _claim(address account, address receiver) private returns (uint256) {
        _updateRewards(account);
        Types.UserInfo storage user = userInfo[account];
        uint256 tokenAmount = user.claimableReward;
        user.claimableReward = 0;

        if (tokenAmount > 0) {
            IERC20Upgradeable(rewardToken()).safeTransfer(receiver, tokenAmount);
            emit Claim(account, tokenAmount);
        }

        return tokenAmount;
    }

    function _updateRewards(address account) private {
        uint256 blockReward = IRewardDistributor(distributor).distribute(address(this));

        uint256 supply = totalSupply();
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken + (blockReward * (PRECISION) / (supply));
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (account != address(0)) {
            Types.UserInfo storage user = userInfo[account];
            uint256 stakedAmount = balanceOf(account);
            uint256 accountReward = stakedAmount * (_cumulativeRewardPerToken - (user.previousCumulatedRewardPerToken)) / (PRECISION);
            uint256 _claimableReward = user.claimableReward + (accountReward);

            user.claimableReward = _claimableReward;
            user.previousCumulatedRewardPerToken = _cumulativeRewardPerToken;
        }
    }

    /**************************************** VIEW FUNCTIONS ****************************************/
    function rewardToken() public view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    // View function to see pending Bavas on frontend.
    function claimable(address account) public view returns (uint256) {
        Types.UserInfo memory user = userInfo[account];
        uint256 stakedAmount = balanceOf(account);
        if (stakedAmount == 0) {
            return user.claimableReward;
        }
        uint256 supply = totalSupply();
        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards(address(this)) * (PRECISION);
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken + (pendingRewards / (supply));
        return user.claimableReward + (
            stakedAmount * (nextCumulativeRewardPerToken - (user.previousCumulatedRewardPerToken)) / (PRECISION));
    }

    // View function to see pending 3rd party reward. Ignore bonus reward view to reduce code error due to 3rd party contract changes
    function checkReward() public view returns (uint256) {
        uint256 pendingRewardAmount = stakingContract.pendingReward(
            stakingFarmID,
            address(this)
        );
        uint256 rewardBalance = poolRewardToken.balanceOf(address(this));

        return (pendingRewardAmount + rewardBalance);
    }

    // View function to see pending 3rd party reward. Ignore bonus reward view to reduce code error due to 3rd party contract changes
    function getFeesInfo() public view returns (uint256, uint256, uint256) {
        return (feeOnReward, feeOnCompounder, feeOnWithdrawal);
    }

    /**************************************** ONLY OWNER FUNCTIONS ****************************************/

    // @notice Rescue any token function, just in case if any user not able to withdraw token from the smart contract.
    function rescueDeployedFunds(
        address token,
        uint256 amount,
        address _to
    ) external onlyRole(OWNER_ROLE) {
        require(_to != address(0), "0Addr");
        IERC20Upgradeable(token).safeTransfer(_to, amount);
    }

    // @notice Emergency withdraw all LP tokens from staking farm contract
    function emergencyWithdrawVault(bool disableDeposits)
        external
        onlyRole(OWNER_ROLE)
    {
        stakingContract.emergencyWithdraw(stakingFarmID);

        if (depositsEnabled == true && disableDeposits == true) {
            updateDepositsEnabled(false);
            updateRestakingEnabled(false);
        }

        emit EmergencyWithdrawVault(msg.sender, disableDeposits);
    }

    // @notice Enable/disable deposits
    function updateDepositsEnabled(bool newValue) public onlyRole(OWNER_ROLE) {
        require(depositsEnabled != newValue);
        depositsEnabled = newValue;
        emit DepositsEnabled(newValue);
    }

    function updateRestakingEnabled(bool newValue) public onlyRole(OWNER_ROLE) {
        require(restakingEnabled != newValue);
        restakingEnabled = newValue;
        emit RestakingEnabled(newValue);
    }

    /**************************************** ONLY AUTHORIZED FUNCTIONS ****************************************/

    function updateMinReinvestToken(uint256 _minTokensToReinvest)
        public
        onlyRole(GOVERNOR_ROLE)
    {
        minTokensToReinvest = _minTokensToReinvest;
    }

    function updateFeeBips(uint256 _feeOnReward, uint256 _feeOnCompounder)
        public
        onlyRole(GOVERNOR_ROLE)
    {
        feeOnReward = _feeOnReward;
        feeOnCompounder = _feeOnCompounder;
    }

    function updateFeeTreasury(address _feeTreasury)
        public
        onlyRole(GOVERNOR_ROLE)
    {
        feeTreasury = _feeTreasury;
    }
    

    function updateDistributor(address _distributor)
        public
        onlyRole(GOVERNOR_ROLE)
    {
        distributor = _distributor;
    }

    /*********************** Compound Strategy ************************************************************************
     * Swap all reward tokens to WFX and swap half/half WFX token to both LP token0 & token1, Add liquidity to LP token
     ***********************************************************************************************************************/

    function _compound() private returns (uint256) {
        _getReinvestReward();
        _convertBonusRewardIntoWFX();

        uint256 wfxAmount = IERC20Upgradeable(WFX).balanceOf(address(this));
        uint256 protocolFee = (wfxAmount * (feeOnReward)) / (BIPS_DIVISOR);
        uint256 reinvestFee = (wfxAmount * (feeOnCompounder)) / (BIPS_DIVISOR);

        IERC20Upgradeable(WFX).safeTransfer(feeTreasury, protocolFee);
        IERC20Upgradeable(WFX).safeTransfer(msg.sender, reinvestFee);

        uint256 liquidity = _convertWFXToDepositToken(wfxAmount - reinvestFee - protocolFee);

        return liquidity;
    }

    function _convertBonusRewardIntoWFX() private {
        uint256 rewardLength = bonusRewardTokens.length;

        if (rewardLength > 0) {
            uint256 pathLength = 2;
            address[] memory path = new address[](pathLength);
            
            // BAVA-WFX Super farm strategy
            path[0] = address(BAVA);
            path[1] = address(WFX);
            uint256 rewardBal = bavaBonusReward;

            if (rewardBal > 0) {
                bavaBonusReward -= rewardBal;
                _convertExactTokentoToken(path, rewardBal);
            }
        }
    }

    function _convertWFXToDepositToken(uint256 amount)
        private
        returns (uint256)
    {
        require(amount > 0, "#<0");
        uint256 amountIn = amount / 2;
        address depositToken = asset();
        // swap to token0
        uint256 path0Length = 2;
        address[] memory path0 = new address[](path0Length);
        path0[0] = address(WFX);
        path0[1] = IPair(address(depositToken)).token0();

        uint256 amountOutToken0 = amountIn;
        // Check if path0[1] equal to WFX
        if (path0[0] != path0[path0Length - 1]) {
            amountOutToken0 = _convertExactTokentoToken(path0, amountIn);
        }

        // swap to token1
        uint256 path1Length = 2;
        address[] memory path1 = new address[](path1Length);
        path1[0] = path0[0];
        path1[1] = IPair(address(depositToken)).token1();

        uint256 amountOutToken1 = amountIn;
        if (path1[0] != path1[path1Length - 1]) {
            amountOutToken1 = _convertExactTokentoToken(path1, amountIn);
        }

        // swap to deposit(LP) Token
        (, , uint256 liquidity) = router.addLiquidity(
            path0[path0Length - 1],
            path1[path1Length - 1],
            amountOutToken0,
            amountOutToken1,
            0,
            0,
            address(this),
            block.timestamp + 3000
        );
        return liquidity;
    }

    function _convertExactTokentoToken(address[] memory path, uint256 amount)
        private
        returns (uint256)
    {
        uint256[] memory amountsOutToken = router.getAmountsOut(amount, path);
        uint256 amountOutToken = amountsOutToken[amountsOutToken.length - 1];
        uint256[] memory amountOut = router.swapExactTokensForTokens(
            amount,
            amountOutToken,
            path,
            address(this),
            block.timestamp + 1200
        );
        uint256 swapAmount = amountOut[amountOut.length - 1];

        return swapAmount;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        _updateRewards(from);
        _updateRewards(to);

        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyRole(OWNER_ROLE) {}

    /**************************************************************
     * @dev Initialize smart contract functions - only called once
     * @param symbol: BRT2LPSYMBOL
     *************************************************************/
    function initialize(
        address _asset,
        address _owner,
        address _governor,
        string memory name_,
        string memory symbol_
    ) public initializer {
        __BaseVaultInit(
            _asset,
            name_,
            symbol_,
            _owner,
            _governor
        );
        __UUPSUpgradeable_init();
    }
}