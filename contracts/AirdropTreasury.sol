// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;
pragma abicoder v2;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Treasury
 *
 * @notice Holds an FX token. Allows the owner to transfer the token or set allowances.
 */
contract AirdropTreasury is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    event Received(address, uint);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function airdropFX(address[] calldata _airdropList,
        uint256[] calldata _safeAmount
    ) external nonReentrant onlyOwner {
        uint256 length = _airdropList.length;
        require(_airdropList.length == _safeAmount.length, "Length not match");
        for (uint i = 0; i < length; i++) {
            
            address recipient = payable(_airdropList[i]);
            (bool success, ) = recipient.call{value: _safeAmount[i]}("");
            require(success, "Failed to send FX");
        }
    }

    function recoverToken(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "Send to zero address");
        token.safeTransfer(recipient, amount);
    }

    function recoverFx(
        uint256 safeAmount,
        address _recipient
    ) external onlyOwner {
        address recipient = payable(_recipient);
        (bool success, ) = recipient.call{value: safeAmount}("");
        require(success, "Failed to send FX");
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }
}
