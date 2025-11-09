// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {KipuBank} from "../src/KipuBank.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DeploySwapWrapper
 * @notice Deployment script for KipuBank contract on ZetaChain
 * @dev Configures and deploys KipuBank with ZetaChain-specific addresses
 */
contract DeploySwapWrapper is Script {
    /// @notice USDC token contract on ZetaChain
    IERC20 public usdc = IERC20(0x96152E6180E085FA57c7708e18AF8F05e37B479D);
    
    /**
     * @notice Main deployment function
     * @return swapWrapper Deployed KipuBank contract instance
     * @dev Deploys KipuBank with configured parameters for ZetaChain
     */
    function run() external returns (KipuBank swapWrapper) {
        // Configuration parameters for ZetaChain deployment
        uint256 _withdrawalLimit = 1000000 * 10 ** 18; // 1,000,000 USDC equivalent
        uint256 _bankCapacity = 1000000 * 10 ** 18;    // 1,000,000 USDC equivalent
        
        // ZetaChain contract addresses
        address _ethUsdOracle = address(0x1de70f3e971B62A0707dA18100392af14f7fB677); // ETH.BASE price feed
        address _router = address(0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe);     // Uniswap V2 Router

        // Deployment execution
        vm.startBroadcast();
        swapWrapper = new KipuBank(
            _withdrawalLimit,
            _bankCapacity,
            usdc,
            _ethUsdOracle,
            _router
        );
        vm.stopBroadcast();
        
        return swapWrapper;
    }
}