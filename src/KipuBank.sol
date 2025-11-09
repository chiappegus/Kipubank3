// SPDX-License-Identifier: MIT
pragma solidity >0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KipuBank
 * @notice A decentralized banking contract supporting multi-token deposits, swaps, and withdrawals
 * @dev Implements banking functionality with Uniswap V2 integration for token conversions
 */
contract KipuBank is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Timeout for oracle price freshness check
    uint16 constant ORACLE_HEARTBEAT = 3600;
    
    /// @notice Factor for decimal conversions between tokens
    uint256 constant DECIMAL_FACTOR = 1 * 10 ** 20;

    /// @notice Address of the price feed contract for ETH/USD conversions
    address public s_feeds;
    
    /// @notice USDC token contract interface
    IERC20 public immutable USDC;
    
    /// @notice Maximum amount that can be withdrawn in a single transaction
    uint256 public immutable WITHDRAWAL_LIMIT;
    
    /// @notice Maximum total capacity of the bank
    uint256 public immutable BANK_CAPACITY;
    
    /// @notice Uniswap V2 Router interface for token swaps
    IUniswapV2Router02 public immutable ROUTER;
    
    /// @notice Wrapped ETH address from Uniswap Router
    address public immutable WETH;

    /// @notice Reentrancy guard lock
    bool private _locked;
    
    /// @notice Mapping of user addresses to their vault balances in ETH equivalent
    mapping(address => uint256) private personalVaults;
    
    /// @notice Total ETH held by the contract across all users
    uint256 public totalContractETH;

    /**
     * @notice Structure representing a user's token balances
     * @param eth Balance in ETH
     * @param usdc Balance in USDC
     * @param total Total balance in ETH equivalent
     */
    struct Balances {
        uint256 eth;
        uint256 usdc;
        uint256 total;
    }

    /// @notice Mapping of user addresses to their balance structure
    mapping(address => Balances) public balance;
    
    /// @notice Total amount deposited across all users in ETH equivalent
    uint256 public totalDeposited;
    
    /// @notice Total number of deposit transactions
    uint256 private totalDepositsCount;
    
    /// @notice Total number of withdrawal transactions
    uint256 private totalWithdrawalsCount;

    // Events
    event SuccessfulDepositEth(address indexed user, uint256 amount, bool inETH);
    event SuccessfulDepositUsdc(address indexed user, uint256 amount, bool Usdc);
    event SuccessfulWithdrawal(address indexed user, uint256 amount);
    event SuccessfulWithdrawalUSDC(address indexed user, uint256 amount);
    event DonationsV2_ChainlinkFeedUpdated(address feed);

    // Errors
    error KipuBank_OracleCompromised();
    error KipuBank_StalePrice();
    error InvalidAmount();
    error WithdrawalLimitExceeded();
    error InsufficientFunds();
    error BankCapacityExceeded();
    error TransferFailed();
    error KipuBank_ZeroAmount();
    error KipuBank_ZeroPrice();
    error KipuBank_InvalidAmount();
    error InvalidContract();
    error ZeroAddress();
    error ZeroAmount();

    /**
     * @notice Modifier to validate amount is not zero
     * @param amount The amount to validate
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Modifier to check if amount is within withdrawal limit
     * @param amount The withdrawal amount to check
     */
    modifier withinWithdrawalLimit(uint256 amount) {
        if (amount > WITHDRAWAL_LIMIT) revert WithdrawalLimitExceeded();
        _;
    }

    /**
     * @notice Modifier to check if user has sufficient balance
     * @param user The user address to check balance for
     * @param amount The required amount
     */
    modifier sufficientBalance(address user, uint256 amount) {
        if (personalVaults[user] < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Modifier to check if user has sufficient ETH balance
     * @param user The user address to check ETH balance for
     * @param amount The required ETH amount
     */
    modifier sufficientBalanceETH(address user, uint256 amount) {
        if (balance[user].eth < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Modifier to check if user has sufficient USDC balance
     * @param user The user address to check USDC balance for
     * @param amount The required USDC amount
     */
    modifier sufficientBalanceUSDC(address user, uint256 amount) {
        if (balance[user].usdc < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Constructor to initialize the KipuBank contract
     * @param withdrawalLimit Maximum withdrawal limit per transaction
     * @param bankCapacity Total capacity of the bank in ETH equivalent
     * @param _token USDC token contract address
     * @param _ethUsdOracle ETH/USD price feed contract address
     * @param _router Uniswap V2 router address for token swaps
     */
    constructor(
        uint256 withdrawalLimit,
        uint256 bankCapacity,
        IERC20 _token,
        address _ethUsdOracle,
        address _router
    ) Ownable(msg.sender) {
        if (
            _router == address(0) ||
            _ethUsdOracle == (address(0)) ||
            _token == IERC20(address(0))
        ) revert InvalidContract();
        
        ROUTER = IUniswapV2Router02(_router);
        WITHDRAWAL_LIMIT = withdrawalLimit;
        BANK_CAPACITY = bankCapacity;
        USDC = _token;
        s_feeds = _ethUsdOracle;
        WETH = ROUTER.WETH();
    }

    /**
     * @notice Update the price feed contract address
     * @dev Only callable by the contract owner
     * @param _feed New price feed contract address
     */
    function setFeeds(address _feed) external onlyOwner {
        s_feeds = _feed;
        emit DonationsV2_ChainlinkFeedUpdated(_feed);
    }

    /**
     * @notice Get current ETH price in USDC using Uniswap
     * @return _precio Current ETH price in USDC with 6 decimals
     */
    function precioethUscd() public view returns (uint256 _precio) {
        return uint256(chainlinkFeed());
    }

    /**
     * @notice Get latest ETH price from Uniswap price feed
     * @return ethUSDPrice_ Current ETH price in USDC with 6 decimals
     * @dev Uses Uniswap router to get price via swap simulation
     */
    function chainlinkFeed() public view returns (uint256 ethUSDPrice_) {
        ethUSDPrice_ = previewSwapToUsdcM2(s_feeds, 1000000000000000000);

        if (ethUSDPrice_ <= 0) revert KipuBank_OracleCompromised();
        return ethUSDPrice_;
    }

    /**
     * @notice Convert ETH amount to USDC equivalent
     * @param _ethAmount Amount of ETH to convert (18 decimals)
     * @return convertedAmount_ Equivalent amount in USDC (6 decimals)
     */
    function convertEthInUSD(
        uint256 _ethAmount
    ) external view returns (uint256) {
        if (_ethAmount == 0) revert KipuBank_ZeroAmount();

        uint256 usdcPerEth = previewSwapToUsdcM2(s_feeds, 1000000000000000000);
        uint256 convertedAmount = (_ethAmount * usdcPerEth) / 1e18;

        if (convertedAmount == 0) revert KipuBank_InvalidAmount();
        return convertedAmount;
    }

    /**
     * @notice Convert USDC amount to ETH equivalent
     * @param _usdcAmount Amount of USDC to convert (6 decimals)
     * @return ethAmount Equivalent amount in ETH (18 decimals)
     */
    function convertUsdcToEth(
        uint256 _usdcAmount
    ) public view returns (uint256) {
        if (_usdcAmount == 0) revert KipuBank_ZeroAmount();

        uint256 price = previewSwapToUsdcM2(s_feeds, 1000000000000000000);
        if (price == 0) revert KipuBank_ZeroPrice();

        uint256 ethAmount = (_usdcAmount * 1e18) / price;

        if (ethAmount == 0) revert KipuBank_InvalidAmount();
        return ethAmount;
    }

    /**
     * @notice Universal deposit function for both ETH and USDC
     * @dev For ETH deposits: send ETH with transaction and use address(0) for _add
     * @dev For USDC deposits: approve tokens first and use USDC address for _add
     * @param _add Token address (address(0) for ETH, USDC address for USDC)
     * @param amount Amount to deposit (for USDC - 6 decimals, for ETH - sent as msg.value)
     */
    function deposit(address _add, uint256 amount) external payable {
        Balances storage _balances = balance[msg.sender];
        
        if (_add == address(0)) {
            // ETH deposit logic
            if (msg.value <= 0) revert InvalidAmount();
            if (totalDeposited + msg.value > BANK_CAPACITY)
                revert BankCapacityExceeded();

            unchecked {
                personalVaults[msg.sender] += msg.value;
                totalContractETH += msg.value;
                _balances.eth += msg.value;
                _balances.total += msg.value;
                totalDepositsCount++;
                totalDeposited += msg.value;
            }

            emit SuccessfulDepositEth(msg.sender, amount, true);
        } else {
            // USDC deposit logic
            if (amount < 0) revert InvalidAmount();
            uint256 Uscd_ETH = convertUsdcToEth(amount);
            
            if (totalDeposited + Uscd_ETH > BANK_CAPACITY)
                revert BankCapacityExceeded();
                
            bool success = USDC.transferFrom(msg.sender, address(this), amount);
            if (!success) revert InvalidAmount();

            unchecked {
                _balances.usdc += amount;
                _balances.total += Uscd_ETH;
                personalVaults[msg.sender] += Uscd_ETH;
                totalDepositsCount++;
                totalDeposited += Uscd_ETH;
            }
            emit SuccessfulDepositUsdc(msg.sender, amount, true);
        }
    }

    /**
     * @notice Fallback function to receive ETH deposits
     * @dev Automatically processes ETH deposits when sent directly to contract
     */
    receive() external payable {
        if (msg.value == 0) revert InvalidAmount();
        if (totalDeposited + msg.value > BANK_CAPACITY)
            revert BankCapacityExceeded();
            
        Balances storage _balances = balance[msg.sender];
        unchecked {
            personalVaults[msg.sender] += msg.value;
            totalContractETH += msg.value;
            _balances.eth += msg.value;
            _balances.total += msg.value;
            totalDepositsCount++;
            totalDeposited += msg.value;
        }

        emit SuccessfulDepositEth(msg.sender, msg.value, true);
    }

    /**
     * @notice Preview swap from any token to USDC using Uniswap V2 Router
     * @param tokenIn Address of the input token
     * @param amountIn Amount of input token to swap
     * @return amountOut Estimated amount of USDC received (6 decimals)
     */
    function previewSwapToUsdcM2(
        address tokenIn,
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (tokenIn == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        if (tokenIn == address(USDC)) {
            return amountIn;
        }
        
        address[] memory path;
        
        if (tokenIn == address(WETH)) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = address(USDC);
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = address(WETH);
            path[2] = address(USDC);
        }
        
        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[amounts.length - 1];
    }

    /**
     * @notice Swap from any token to USDC and deposit into bank
     * @dev For direct USDC deposits, tokens are deposited without swap
     * @dev For other tokens, swaps via Uniswap and deposits resulting USDC
     * @param tokenIn Address of the input token
     * @param amountIn Amount of input token to swap
     * @param amountOutMin Minimum amount of USDC to receive from swap
     * @return amountOut Actual amount of USDC received and deposited
     */
    function swapToUsdcGUSF(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {
        if (tokenIn == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Case 1: If already USDC, deposit directly
        if (tokenIn == address(USDC)) {
            _updateBalances(msg.sender, amountIn);
            return amountIn;
        }

        // Case 2: For other tokens, convert to USDC and deposit
        IERC20(tokenIn).safeIncreaseAllowance(address(ROUTER), amountIn);

        address[] memory path;
        if (tokenIn == address(WETH)) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = address(USDC);
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = address(WETH);
            path[2] = address(USDC);
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
        
        amountOut = amounts[amounts.length - 1];
        
        // Deposit the USDC into the bank
        _updateBalances(msg.sender, amountOut);
        
        emit SuccessfulDepositUsdc(msg.sender, amountOut, true);
        return amountOut;
    }

    /**
     * @notice Internal function to update user balances after USDC deposit
     * @param user Address of the user depositing
     * @param usdcAmount Amount of USDC being deposited (6 decimals)
     */
    function _updateBalances(address user, uint256 usdcAmount) internal {
        if (usdcAmount == 0) revert InvalidAmount();
        
        uint256 ethEquivalent = convertUsdcToEth(usdcAmount);
        if (totalDeposited + ethEquivalent > BANK_CAPACITY) {
            revert BankCapacityExceeded();
        }

        Balances storage _balances = balance[user];
        unchecked {
            _balances.usdc += usdcAmount;
            _balances.total += ethEquivalent;
            personalVaults[user] += ethEquivalent;
            totalDepositsCount++;
            totalDeposited += ethEquivalent;
        }
    }

    /**
     * @notice Withdraw ETH from the bank
     * @param amount Amount of ETH to withdraw (18 decimals)
     * @dev Includes multiple security checks and balance validations
     */
    function withdrawETH(
        uint256 amount
    )
        external
        validAmount(amount)
        withinWithdrawalLimit(amount)
        sufficientBalanceETH(msg.sender, amount)
        sufficientBalance(msg.sender, amount)
    {
        Balances storage _balances = balance[msg.sender];
        unchecked {
            personalVaults[msg.sender] -= amount;
            totalContractETH -= amount;
            _balances.eth -= amount;
            _balances.total -= amount;
            totalDeposited -= amount;
            totalWithdrawalsCount++;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit SuccessfulWithdrawal(msg.sender, amount);
    }

    /**
     * @notice Withdraw USDC from the bank
     * @param amount Amount of USDC to withdraw (6 decimals)
     */
    function withdrawUSDC(uint256 amount) external {
        uint256 Uscd_ETH = convertUsdcToEth(amount);

        if (!withdrawUSDC_CONV(amount, Uscd_ETH)) revert TransferFailed();

        emit SuccessfulWithdrawalUSDC(msg.sender, Uscd_ETH);
    }

    /**
     * @notice Internal function to process USDC withdrawals
     * @param amount Amount of USDC to withdraw (6 decimals)
     * @param usdc ETH equivalent of USDC amount (18 decimals)
     * @return success Whether the withdrawal was successful
     */
    function withdrawUSDC_CONV(
        uint256 amount,
        uint256 usdc
    )
        internal
        validAmount(usdc)
        withinWithdrawalLimit(usdc)
        sufficientBalanceUSDC(msg.sender, amount)
        returns (bool success)
    {
        unchecked {
            personalVaults[msg.sender] -= usdc;
            totalDeposited -= usdc;
            totalWithdrawalsCount++;
        }
        Balances storage _balances = balance[msg.sender];
        _balances.usdc -= amount;
        _balances.total -= usdc;

        return USDC.transfer(msg.sender, amount);
    }

    /**
     * @notice Get user's balance information
     * @param user Address of the user to query
     * @return eth ETH balance (18 decimals)
     * @return usdc USDC balance (6 decimals)
     * @return total Total balance in ETH equivalent (18 decimals)
     */
    function myBalanceS(address user) 
        external
        view
        returns (uint256 eth, uint256 usdc, uint256 total)
    {
        Balances storage _balances = balance[user];
        return (_balances.eth, _balances.usdc, _balances.total);
    }

    /**
     * @notice Get available capacity in the bank
     * @return Available space for additional deposits in ETH equivalent
     */
    function availableCapacity() external view returns (uint256) {
        return BANK_CAPACITY - totalDeposited;
    }

    /**
     * @notice Get comprehensive bank statistics
     * @return withdrawalLimit Current withdrawal limit per transaction
     * @return maximumCapacity Bank maximum capacity
     * @return currentTotal Total deposited amount in ETH equivalent
     * @return availableSpace Available remaining space in ETH equivalent
     * @dev Only callable by owner
     */
    function bankStatistics()
        external
        view
        onlyOwner
        returns (
            uint256 withdrawalLimit,
            uint256 maximumCapacity,
            uint256 currentTotal,
            uint256 availableSpace
        )
    {
        return (
            WITHDRAWAL_LIMIT,
            BANK_CAPACITY,
            totalDeposited,
            BANK_CAPACITY - totalDeposited
        );
    }

    /**
     * @notice Get transaction statistics
     * @return totalDeposits Total number of deposits
     * @return totalWithdrawals Total number of withdrawals
     * @return totalTransactions Total number of transactions
     * @dev Only callable by owner
     */
    function transactionStatistics()
        external
        view
        onlyOwner
        returns (
            uint256 totalDeposits,
            uint256 totalWithdrawals,
            uint256 totalTransactions
        )
    {
        return (
            totalDepositsCount,
            totalWithdrawalsCount,
            totalDepositsCount + totalWithdrawalsCount
        );
    }
}