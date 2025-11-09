# KipuBank V3 - Advanced Multi-Token Decentralized Bank

## What is KipuBank V3?

KipuBank V3 is a significant upgrade to our decentralized banking protocol, now featuring **Uniswap V2 integration** for seamless multi-token support. This advanced version allows users to deposit **any ERC20 token** supported by Uniswap V2, which automatically converts to USDC while maintaining all the robust banking features from previous versions.

## 🚀 Key Upgrades from V2 to V3

### Major New Features:
- **✅ Universal Token Support** - Deposit any ERC20 token via Uniswap V2 integration
- **✅ Automated Token Swaps** - Automatic conversion of deposited tokens to USDC
- **✅ Enhanced Price Oracle** - Dual oracle system using both Chainlink and Uniswap for price feeds
- **✅ Improved Security** - Additional validation and reentrancy protection
- **✅ Advanced Testing Suite** - Comprehensive test coverage exceeding 50%

### Enhanced Capabilities:
- **Multi-token deposits** beyond just ETH and USDC
- **Real-time swap simulations** with `previewSwapToUsdcM2()`
- **Automatic balance management** with token conversions
- **Expanded price feed options** for better reliability

## 📊 Test Coverage Achievement
**Current Coverage: 54.55%** ✅ **Exceeds 50% Requirement**

| Component | Lines | Statements | Branches | Functions |
|-----------|-------|------------|----------|-----------|
| KipuBank.sol | 54.66% | 50.56% | 14.29% | 65.22% |
| Test Suite | 71.43% | 70.00% | 50.00% | 75.00% |
| **Total** | **54.55%** | **49.53%** | **17.95%** | **65.62%** |

## 🔧 Core Functionality

### Contract Architecture
```solidity
KipuBank V3 = KipuBank V2 + Uniswap V2 Integration + Multi-Token Support
```

## 📖 Function Reference

### 🏦 Deposit Functions

#### `deposit(address _add, uint256 amount)`
**Purpose**: Universal deposit function for ETH, USDC, and any ERC20 token  
**Parameters**:
- `_add`: Token address (address(0) for ETH, token address for ERC20)
- `amount`: Amount to deposit (for ERC20 tokens)

**How it works**:
- **ETH**: Direct deposit with native ETH
- **USDC**: Direct storage without conversion
- **Other ERC20**: Automatic swap to USDC via Uniswap V2

#### `swapToUsdcGUSF(address tokenIn, uint256 amountIn, uint256 amountOutMin)`
**Purpose**: Direct token-to-USDC conversion with deposit  
**Parameters**:
- `tokenIn`: Address of input token
- `amountIn`: Amount to swap
- `amountOutMin`: Minimum USDC amount to receive

**Returns**: Actual USDC amount received and deposited

**Process**:
1. Transfers tokens from user
2. Approves Uniswap router
3. Executes swap via optimal path
4. Deposits resulting USDC automatically

### 💰 Withdrawal Functions

#### `withdrawETH(uint256 amount)`
**Purpose**: Withdraw ETH from bank account  
**Security**: Multiple validation modifiers ensure safety

#### `withdrawUSDC(uint256 amount)`
**Purpose**: Withdraw USDC from bank account  
**Features**: Automatic ETH equivalent calculation for capacity management

### 🔄 Conversion & Price Functions

#### `previewSwapToUsdcM2(address tokenIn, uint256 amountIn)`
**Purpose**: Simulate token-to-USDC conversion without executing  
**Returns**: Estimated USDC output amount  
**Use Case**: Front-end integration for user previews

#### `convertEthInUSD(uint256 _ethAmount)`
**Purpose**: Convert ETH amount to USDC equivalent  
**Uses**: Uniswap V2 router for accurate pricing

#### `convertUsdcToEth(uint256 _usdcAmount)`
**Purpose**: Convert USDC amount to ETH equivalent  
**Uses**: Reverse calculation for capacity management

### 📊 Information Functions

#### `myBalanceS(address user)`
**Returns**: 
- `eth`: ETH balance (18 decimals)
- `usdc`: USDC balance (6 decimals) 
- `total`: Total balance in ETH equivalent

#### `bankStatistics()`
**Owner Only**: Comprehensive bank status  
**Returns**: Withdrawal limits, capacity, current totals, available space

#### `transactionStatistics()`
**Owner Only**: Transaction analytics  
**Returns**: Deposit count, withdrawal count, total transactions

### ⚙️ Administrative Functions

#### `setFeeds(address _feed)`
**Owner Only**: Update price feed address  
**Security**: Restricted to contract owner

## 🛡️ Security Features

### Multi-Layer Protection:
- **Reentrancy Guard**: `_locked` modifier prevents reentrancy attacks
- **Amount Validation**: Zero amount checks across all functions
- **Balance Verification**: Sufficient balance checks before withdrawals
- **Capacity Limits**: Bank capacity enforcement with real-time checks
- **Owner Controls**: Restricted administrative functions

### Validation Modifiers:
```solidity
modifier validAmount(uint256 amount)        // Non-zero amount check
modifier withinWithdrawalLimit(uint256 amount) // Withdrawal limit enforcement
modifier sufficientBalance(address user, uint256 amount) // Balance verification
```

## 🔗 Uniswap V2 Integration

### Swap Path Optimization:
- **Direct Path**: Token → USDC (for direct pairs)
- **WETH Path**: Token → WETH → USDC (for tokens without direct USDC pairs)
- **Gas Efficiency**: Optimal path selection based on available liquidity

### Router Integration:
- **getAmountsOut()**: For price previews without execution
- **swapExactTokensForTokens()**: For actual token conversions
- **Automatic Approval**: SafeERC20 for secure token handling

## 💾 Storage Architecture

### Balance Management:
```solidity
struct Balances {
    uint256 eth;      // Native ETH balance
    uint256 usdc;     // USDC token balance  
    uint256 total;    // Total in ETH equivalent
}

mapping(address => Balances) public balance;
```

### Capacity Tracking:
- `totalDeposited`: Tracks overall bank usage in ETH equivalent
- `BANK_CAPACITY`: Maximum capacity limit
- Real-time capacity checks on every deposit

## 🧪 Testing Suite

### Comprehensive Test Coverage:
- **✅ Deposit Tests**: ETH, USDC, and token deposits
- **✅ Withdrawal Tests**: ETH and USDC withdrawals with limits
- **✅ Conversion Tests**: Price conversions and swap simulations
- **✅ Security Tests**: Owner controls and access restrictions
- **✅ Multi-User Tests**: Concurrent user operations
- **✅ Edge Cases**: Zero amounts, insufficient funds, capacity limits

### Test Results:
```
17/17 Tests PASSED
100% Test Success Rate
54.55% Overall Coverage ✅
```

## 🚀 Deployment

### Prerequisites:
- Uniswap V2 Router address
- USDC token contract address  
- Price feed contract address
- Sufficient gas for deployment

### Constructor Parameters:
```solidity
constructor(
    uint256 withdrawalLimit,    // Maximum per-withdrawal limit
    uint256 bankCapacity,       // Total bank capacity
    IERC20 _token,             // USDC token address
    address _ethUsdOracle,     // Price feed address
    address _router            // Uniswap V2 Router address
)
```

## 🌟 Use Cases

### For End Users:
- **Multi-asset savings** with automatic USDC conversion
- **Real-time balance tracking** with unified totals
- **Secure withdrawals** with multiple validation layers

### For Developers:
- **Comprehensive event logging** for transaction tracking
- **Modular architecture** for easy extensions
- **Well-tested codebase** with extensive coverage

KipuBank V3 represents the evolution of decentralized banking, combining the security of traditional finance with the flexibility and transparency of blockchain technology through advanced DeFi integrations.
