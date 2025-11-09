# KipuBank V3 - Advanced Multi-Token Decentralized Banking Protocol

## 📋 Overview

KipuBank V3 is a sophisticated decentralized banking protocol featuring comprehensive multi-token support with Uniswap V2 integration. This advanced version enables seamless deposits of any ERC20 token supported by Uniswap V2, with automatic conversion to USDC while maintaining robust banking operations and security measures.

## 🚀 Major Upgrades from V2 to V3

### **Enhanced Features:**
- ✅ **Universal Token Support** - Deposit any ERC20 token via Uniswap V2 integration
- ✅ **Automated Token Swaps** - Automatic conversion of deposited tokens to USDC
- ✅ **Advanced Price Oracle** - Uniswap-based price feeds for accurate conversions
- ✅ **Enhanced Security** - Comprehensive validation and state management
- ✅ **Professional Test Suite** - Extensive test coverage with 100% pass rate
- ✅ **Dynamic WETH Management** - Configurable WETH contract address

### **Technical Improvements:**
- Multi-token deposits beyond ETH and USDC
- Real-time swap simulations with preview functionality
- Optimized balance management with token conversions
- Professional error handling with custom errors
- Gas-efficient state variable management

## 📊 Test Coverage & Quality

### **Current Test Results:**

28/28 Tests PASSED ✅
100% Test Success Rate
70.9% Line Coverage | 87.1% Function Coverage


### **Coverage Breakdown:**
| Component | Line Coverage | Function Coverage |
|-----------|---------------|-------------------|
| KipuBank.sol | 76.9% | 95.5% |
| Test Suite | 61.9% | 75.0% |
| **Overall** | **70.9%** | **87.1%** |

## 🔧 Core Functionality

### **Contract Architecture**
```solidity
KipuBank V3 = Banking Core + Uniswap V2 Integration + Multi-Token Support + Professional Testing

📖 Comprehensive Function Reference
🏦 Deposit Operations
deposit(address _add, uint256 amount)

Purpose: Universal deposit function supporting ETH, USDC, and any ERC20 token

Parameters:

    _add: Token address (address(0) for ETH, token address for ERC20)

    amount: Amount to deposit (for ERC20 tokens)

Deposit Types:

    ETH: Direct native ETH deposit

    USDC: Direct storage without conversion

    Other ERC20: Automatic swap to USDC via Uniswap V2

swapToUsdcGUSF(address tokenIn, uint256 amountIn, uint256 amountOutMin)

Purpose: Direct token-to-USDC conversion with automatic deposit

Parameters:

    tokenIn: Address of input token

    amountIn: Amount to swap

    amountOutMin: Minimum USDC amount for slippage protection

Returns: Actual USDC amount received and deposited

Process Flow:

    Token transfer from user

    Uniswap router approval

    Optimal path swap execution

    Automatic USDC deposit

💰 Withdrawal Operations
withdrawETH(uint256 amount)

Purpose: Secure ETH withdrawal from bank balance

Security Features:

    Amount validation

    Withdrawal limit enforcement

    Balance verification

    Transfer success checking

withdrawUSDC(uint256 amount)

Purpose: USDC withdrawal with automatic ETH equivalent calculation

Features:

    Real-time conversion rate application

    Capacity management integration

    Comprehensive balance updates

🔄 Conversion & Price Operations
previewSwapToUsdcM2(address tokenIn, uint256 amountIn)

Purpose: Simulate token-to-USDC conversion without execution

Returns: Estimated USDC output amount

Use Case: Frontend integration for user transaction previews
convertEthInUSD(uint256 _ethAmount)

Purpose: Convert ETH amount to USDC equivalent

Technology: Uniswap V2 router for accurate market pricing
convertUsdcToEth(uint256 _usdcAmount)

Purpose: Convert USDC amount to ETH equivalent

Application: Capacity management and balance calculations
📊 Information & Analytics
myBalanceS(address user)

Returns: Complete balance structure
Balances {
    uint256 eth,      // Native ETH balance (18 decimals)
    uint256 usdc,     // USDC token balance (6 decimals)
    uint256 total     // Total balance in ETH equivalent
}
bankStatistics()

Access: Owner only

Returns: Comprehensive bank operational status

    Withdrawal limits

    Maximum capacity

    Current deposited total

    Available space

transactionStatistics()

Access: Owner only

Returns: Transaction analytics

    Total deposit count

    Total withdrawal count

    Aggregate transaction volume

⚙️ Administrative Functions
setWETH(address weth)

Access: Owner only

Purpose: Update WETH contract address for cross-chain compatibility

Events: Emits WETH_Updated(weth) on successful update
🛡️ Security Architecture
Multi-Layer Protection System:

    State Management: Professional storage variable handling

    Amount Validation: Comprehensive zero-amount checks

    Balance Verification: Pre-withdrawal balance confirmation

    Capacity Enforcement: Real-time bank capacity monitoring

    Access Control: Owner-restricted administrative functions

Validation Modifiers:
solidity

modifier validAmount(uint256 amount)        // Non-zero amount validation
modifier withinWithdrawalLimit(uint256 amount) // Withdrawal limit enforcement
modifier sufficientBalance(address user, uint256 amount) // Balance verification
modifier sufficientBalanceETH(address user, uint256 amount) // ETH-specific checks
modifier sufficientBalanceUSDC(address user, uint256 amount) // USDC-specific checks

🔗 Uniswap V2 Integration
Swap Path Optimization:

    Direct Route: Token → USDC (for established trading pairs)

    WETH Bridge: Token → WETH → USDC (for tokens without direct USDC pairs)

    Gas Efficiency: Automatic optimal path selection

Router Integration:

    getAmountsOut(): Price simulation without execution

    swapExactTokensForTokens(): Secure token conversion execution

    SafeERC20: Professional token approval and transfer handling

💾 Storage Architecture
Balance Management:
struct Balances {
    uint256 eth;      // Native ETH balance
    uint256 usdc;     // USDC token balance  
    uint256 total;    // Total in ETH equivalent
}

mapping(address => Balances) public balance;
Capacity Tracking:

    totalDeposited: Real-time bank utilization in ETH equivalent

    BANK_CAPACITY: Maximum protocol capacity limit

    Dynamic capacity validation on all deposit operations

🧪 Professional Testing Suite
Comprehensive Test Coverage:

    ✅ Deposit Testing: ETH, USDC, and ERC20 token deposits

    ✅ Withdrawal Testing: ETH and USDC withdrawals with limit enforcement

    ✅ Conversion Testing: Price conversions and swap simulations

    ✅ Security Testing: Access controls and permission validation

    ✅ Multi-User Testing: Concurrent operations and balance isolation

    ✅ Edge Case Testing: Zero amounts, insufficient funds, capacity limits

    ✅ Integration Testing: Uniswap router interactions and WETH management

Test Results Summary:
28/28 Tests PASSED ✅
0 Failed | 0 Skipped
100% Success Rate
Professional-grade test reliability
 Deployment Guide
Prerequisites:

    Uniswap V2 Router contract address

    USDC token contract address

    Price feed contract address

    Sufficient deployment gas

Constructor Parameters:
constructor(
    uint256 withdrawalLimit,    // Maximum per-transaction withdrawal limit
    uint256 bankCapacity,       // Total protocol capacity in ETH
    IERC20 _token,             // USDC token contract address
    address _ethUsdOracle,     // Price feed contract address  
    address _router            // Uniswap V2 Router address
)

🌟 Use Cases & Applications
For End Users:

    Multi-asset savings with automatic USDC conversion

    Real-time unified balance tracking across assets

    Secure withdrawal system with comprehensive validation

    Professional user experience with transaction previews

For Developers:

    Comprehensive event logging for transaction monitoring

    Modular architecture supporting easy extensions

    Well-tested, reliable codebase with professional coverage

    Flexible WETH configuration for cross-chain deployments

For Protocol Administrators:

    Dynamic WETH management for protocol upgrades

    Professional capacity controls for risk management

    Comprehensive analytics and monitoring capabilities

    Secure owner-controlled configuration updates



