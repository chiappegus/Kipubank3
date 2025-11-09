// SPDX-License-Identifier: MIT
pragma solidity >0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title KipuBank
 * @notice A decentralized banking protocol supporting multi-asset deposits, token swaps, and secure withdrawals
 * @dev Implements comprehensive banking features with Uniswap V2 integration for decentralized price oracles and token conversions
 * @author KipuBank Team
 */
contract KipuBank is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address of the token used for price feed simulations (typically WETH)
    address public s_feeds;

    /// @notice USDC token contract instance for stablecoin operations
    IERC20 public immutable USDC;

    /// @notice Maximum amount of ETH that can be withdrawn in a single transaction
    uint256 public immutable WITHDRAWAL_LIMIT;

    /// @notice Maximum total capacity of the bank denominated in ETH equivalent
    uint256 public immutable BANK_CAPACITY;

    /// @notice Uniswap V2 Router interface for decentralized token swaps and price feeds
    IUniswapV2Router02 public immutable ROUTER;

    /// @notice Wrapped ETH address obtained from Uniswap Router
    address public WETH;

    /// @notice Mapping tracking each user's total balance in ETH equivalent across all deposited assets
    mapping(address => uint256) private personalVaults;

    /// @notice Total amount of native ETH held by the contract across all user deposits
    uint256 public totalContractETH;

    /**
     * @notice Structure representing a user's comprehensive token balances
     * @param eth Native ETH balance (18 decimals)
     * @param usdc USDC stablecoin balance (6 decimals)
     * @param total Aggregate balance across all assets denominated in ETH equivalent (18 decimals)
     */
    struct Balances {
        uint256 eth;
        uint256 usdc;
        uint256 total;
    }

    /// @notice Mapping storing comprehensive balance information for each user
    mapping(address => Balances) public balance;

    /// @notice Total amount deposited across all users denominated in ETH equivalent
    uint256 public totalDeposited;

    /// @notice Counter tracking the total number of successful deposit transactions
    uint256 private totalDepositsCount;

    /// @notice Counter tracking the total number of successful withdrawal transactions
    uint256 private totalWithdrawalsCount;

    // Events

    /**
     * @notice Emitted when a user successfully deposits native ETH
     * @param user The address of the depositing user
     * @param amount The amount of ETH deposited in wei
     * @param inETH Boolean flag indicating the deposit was in native ETH (always true)
     */
    event SuccessfulDepositEth(
        address indexed user,
        uint256 amount,
        bool inETH
    );

    /**
     * @notice Emitted when a user successfully deposits USDC tokens
     * @param user The address of the depositing user
     * @param amount The amount of USDC deposited (6 decimals)
     * @param Usdc Boolean flag indicating the deposit was in USDC (always true)
     */
    event SuccessfulDepositUsdc(
        address indexed user,
        uint256 amount,
        bool Usdc
    );

    /**
     * @notice Emitted when a user successfully withdraws native ETH
     * @param user The address of the withdrawing user
     * @param amount The amount of ETH withdrawn in wei
     */
    event SuccessfulWithdrawal(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user successfully withdraws USDC tokens
     * @param user The address of the withdrawing user
     * @param amount The amount equivalent in ETH of the withdrawn USDC (18 decimals)
     */
    event SuccessfulWithdrawalUSDC(address indexed user, uint256 amount);

    /**
     * @notice Emitted when the WETH contract address is updated by the owner
     * @param weth The new WETH contract address
     */
    event WETH_Updated(address weth);

    // Errors

    /// @notice Thrown when the price oracle returns an invalid or compromised price
    error KipuBank_OracleCompromised();

    /// @notice Thrown when the price oracle data is stale or outdated
    error KipuBank_StalePrice();

    /// @notice Thrown when an operation is attempted with a zero or invalid amount
    error InvalidAmount();

    /// @notice Thrown when a withdrawal amount exceeds the permitted limit
    error WithdrawalLimitExceeded();

    /// @notice Thrown when a user attempts to withdraw more than their available balance
    error InsufficientFunds();

    /// @notice Thrown when a deposit would exceed the bank's maximum capacity
    error BankCapacityExceeded();

    /// @notice Thrown when an ETH or token transfer fails
    error TransferFailed();

    /// @notice Thrown when a zero amount is provided where it's not allowed
    error KipuBank_ZeroAmount();

    /// @notice Thrown when the price oracle returns a zero price
    error KipuBank_ZeroPrice();

    /// @notice Thrown when a calculated amount results in zero after conversion
    error KipuBank_InvalidAmount();

    /// @notice Thrown when an invalid contract address is provided
    error InvalidContract();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided to a function that requires positive amount
    error ZeroAmount();

    // Modifiers

    /**
     * @notice Validates that the provided amount is not zero
     * @param amount The amount to validate
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /**
     * @notice Ensures the withdrawal amount does not exceed the permitted limit
     * @param amount The withdrawal amount to check
     */
    modifier withinWithdrawalLimit(uint256 amount) {
        if (amount > WITHDRAWAL_LIMIT) revert WithdrawalLimitExceeded();
        _;
    }

    /**
     * @notice Verifies the user has sufficient total balance for the requested operation
     * @param user The user address to check balance for
     * @param amount The required amount in ETH equivalent
     */
    modifier sufficientBalance(address user, uint256 amount) {
        if (personalVaults[user] < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Verifies the user has sufficient ETH balance for the requested operation
     * @param user The user address to check ETH balance for
     * @param amount The required ETH amount
     */
    modifier sufficientBalanceETH(address user, uint256 amount) {
        if (balance[user].eth < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Verifies the user has sufficient USDC balance for the requested operation
     * @param user The user address to check USDC balance for
     * @param amount The required USDC amount
     */
    modifier sufficientBalanceUSDC(address user, uint256 amount) {
        if (balance[user].usdc < amount) revert InsufficientFunds();
        _;
    }

    /**
     * @notice Initializes the KipuBank contract with essential parameters
     * @param withdrawalLimit Maximum withdrawal limit per transaction in ETH
     * @param bankCapacity Total capacity of the bank in ETH equivalent
     * @param _token USDC token contract address for stablecoin operations
     * @param _ethUsdOracle Address of the token used for ETH/USD price simulations (typically WETH)
     * @param _router Uniswap V2 router address for decentralized swaps and price feeds
     * @dev All contract addresses are validated for non-zero values during construction
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
     * @notice Updates the WETH contract address used for token swaps
     * @dev Restricted to contract owner only
     * @param weth The new WETH contract address
     */
    function setWETH(address weth) external onlyOwner {
        WETH = weth;
        emit WETH_Updated(weth);
    }

    /**
     * @notice Retrieves the current ETH price in USDC using Uniswap V2 as price oracle
     * @return ethUSDPrice_ The current ETH price denominated in USDC with 6 decimals
     * @dev Uses Uniswap router's getAmountsOut to simulate swaps for accurate price feeds
     */
    function chainlinkFeed() public view returns (uint256 ethUSDPrice_) {
        ethUSDPrice_ = previewSwapToUsdcM2(s_feeds, 1000000000000000000);

        if (ethUSDPrice_ <= 0) revert KipuBank_OracleCompromised();
        return ethUSDPrice_;
    }

    /**
     * @notice Converts a specified amount of ETH to its USDC equivalent
     * @param _ethAmount Amount of ETH to convert (18 decimals)
     * @return convertedAmount_ Equivalent amount in USDC (6 decimals)
     * @dev Uses current market price from Uniswap V2 for conversion
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
     * @notice Converts a specified amount of USDC to its ETH equivalent
     * @param _usdcAmount Amount of USDC to convert (6 decimals)
     * @return ethAmount Equivalent amount in ETH (18 decimals)
     * @dev Uses current market price from Uniswap V2 for conversion
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
     * @notice Universal deposit function supporting both native ETH and USDC tokens
     * @dev For ETH deposits: send ETH as msg.value and use address(0) for _add
     * @dev For USDC deposits: approve tokens first and use USDC address for _add
     * @param _add Token address (address(0) for ETH, USDC address for USDC deposits)
     * @param amount Amount to deposit (for USDC: 6 decimals, for ETH: use msg.value)
     */
    function deposit(address _add, uint256 amount) external payable {
        Balances storage _balances = balance[msg.sender];
        uint256 _totalDeposited = totalDeposited;
        uint256 _totalDepositsCount = totalDepositsCount;

        if (_add == address(0)) {
            if (msg.value <= 0) revert InvalidAmount();

            if (_totalDeposited + msg.value > BANK_CAPACITY)
                revert BankCapacityExceeded();

            unchecked {
                personalVaults[msg.sender] += msg.value;
                totalContractETH += msg.value;
                _balances.eth += msg.value;
                _balances.total += msg.value;

                totalDepositsCount = _totalDepositsCount + 1;
                totalDeposited = _totalDeposited + msg.value;
            }

            emit SuccessfulDepositEth(msg.sender, amount, true);
        } else {
            if (amount < 0) revert InvalidAmount();
            uint256 Uscd_ETH = convertUsdcToEth(amount);

            if (_totalDeposited + Uscd_ETH > BANK_CAPACITY)
                revert BankCapacityExceeded();

            bool success = USDC.transferFrom(msg.sender, address(this), amount);
            if (!success) revert InvalidAmount();

            unchecked {
                _balances.usdc += amount;
                _balances.total += Uscd_ETH;
                personalVaults[msg.sender] += Uscd_ETH;

                totalDepositsCount = _totalDepositsCount + 1;
                totalDeposited = _totalDeposited + Uscd_ETH;
            }
            emit SuccessfulDepositUsdc(msg.sender, amount, true);
        }
    }

    /**
     * @notice Fallback function to receive native ETH deposits sent directly to contract
     * @dev Automatically processes ETH deposits without explicit function call
     */
    receive() external payable {
        if (msg.value == 0) revert InvalidAmount();

        uint256 _totalDeposited = totalDeposited;
        uint256 _totalDepositsCount = totalDepositsCount;

        if (_totalDeposited + msg.value > BANK_CAPACITY)
            revert BankCapacityExceeded();

        Balances storage _balances = balance[msg.sender];
        unchecked {
            personalVaults[msg.sender] += msg.value;
            totalContractETH += msg.value;
            _balances.eth += msg.value;
            _balances.total += msg.value;

            totalDepositsCount = _totalDepositsCount + 1;
            totalDeposited = _totalDeposited + msg.value;
        }

        emit SuccessfulDepositEth(msg.sender, msg.value, true);
    }

    /**
     * @notice Previews the expected output amount when swapping tokens to USDC
     * @param tokenIn Address of the input token to be swapped
     * @param amountIn Amount of input token to swap
     * @return amountOut Estimated amount of USDC that would be received (6 decimals)
     * @dev Uses Uniswap V2 Router's getAmountsOut for accurate price simulation
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
     * @notice Executes token swap to USDC and automatically deposits proceeds into bank
     * @dev For direct USDC deposits, tokens are deposited without swap
     * @dev For other tokens, executes swap via Uniswap and deposits resulting USDC
     * @param tokenIn Address of the input token to be swapped
     * @param amountIn Amount of input token to swap and deposit
     * @param amountOutMin Minimum amount of USDC to accept from swap (slippage protection)
     * @return amountOut Actual amount of USDC received and deposited (6 decimals)
     */
    function swapToUsdcGUSF(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {
        if (tokenIn == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Case 1: If already USDC, deposit directly without swap
        if (tokenIn == address(USDC)) {
            _updateBalances(msg.sender, amountIn);
            return amountIn;
        }

        // Case 2: For other tokens, execute swap to USDC then deposit
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

        // Deposit the received USDC into the bank
        _updateBalances(msg.sender, amountOut);

        emit SuccessfulDepositUsdc(msg.sender, amountOut, true);
        return amountOut;
    }

    /**
     * @notice Internal function to update user balances after USDC deposit
     * @param user Address of the user making the deposit
     * @param usdcAmount Amount of USDC being deposited (6 decimals)
     * @dev Converts USDC to ETH equivalent for unified balance tracking
     */
    function _updateBalances(address user, uint256 usdcAmount) internal {
        if (usdcAmount == 0) revert InvalidAmount();

        uint256 ethEquivalent = convertUsdcToEth(usdcAmount);
        uint256 _totalDeposited = totalDeposited;
        uint256 _totalDepositsCount = totalDepositsCount;

        if (_totalDeposited + ethEquivalent > BANK_CAPACITY) {
            revert BankCapacityExceeded();
        }

        Balances storage _balances = balance[user];
        unchecked {
            _balances.usdc += usdcAmount;
            _balances.total += ethEquivalent;
            personalVaults[user] += ethEquivalent;

            totalDepositsCount = _totalDepositsCount + 1;
            totalDeposited = _totalDeposited + ethEquivalent;
        }
    }

    /**
     * @notice Withdraws native ETH from the user's bank balance
     * @param amount Amount of ETH to withdraw (18 decimals)
     * @dev Includes comprehensive security checks and balance validations
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
        uint256 _totalDeposited = totalDeposited;
        uint256 _totalWithdrawalsCount = totalWithdrawalsCount;
        uint256 _totalContractETH = totalContractETH;

        unchecked {
            personalVaults[msg.sender] -= amount;
            totalContractETH = _totalContractETH - amount;
            _balances.eth -= amount;
            _balances.total -= amount;

            totalDeposited = _totalDeposited - amount;
            totalWithdrawalsCount = _totalWithdrawalsCount + 1;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit SuccessfulWithdrawal(msg.sender, amount);
    }

    /**
     * @notice Withdraws USDC tokens from the user's bank balance
     * @param amount Amount of USDC to withdraw (6 decimals)
     * @dev Converts USDC amount to ETH equivalent for balance validation
     */
    function withdrawUSDC(uint256 amount) external {
        uint256 Uscd_ETH = convertUsdcToEth(amount);

        if (!withdrawUSDC_CONV(amount, Uscd_ETH)) revert TransferFailed();

        emit SuccessfulWithdrawalUSDC(msg.sender, Uscd_ETH);
    }

    /**
     * @notice Internal function to process USDC withdrawal operations
     * @param amount Amount of USDC to withdraw (6 decimals)
     * @param usdc ETH equivalent of the USDC withdrawal amount (18 decimals)
     * @return success Boolean indicating whether the withdrawal transfer was successful
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
        uint256 _totalDeposited = totalDeposited;
        uint256 _totalWithdrawalsCount = totalWithdrawalsCount;

        unchecked {
            personalVaults[msg.sender] -= usdc;
            totalDeposited = _totalDeposited - usdc;
            totalWithdrawalsCount = _totalWithdrawalsCount + 1;
        }

        Balances storage _balances = balance[msg.sender];
        _balances.usdc -= amount;
        _balances.total -= usdc;

        return USDC.transfer(msg.sender, amount);
    }

    /**
     * @notice Retrieves comprehensive balance information for a specified user
     * @param user Address of the user to query balances for
     * @return balances Complete balance structure containing ETH, USDC, and total balances
     */
    function myBalanceS(
        address user
    ) external view returns (Balances memory balances) {
        return balance[user];
    }

    /**
     * @notice Calculates the available deposit capacity remaining in the bank
     * @return Available space for additional deposits denominated in ETH equivalent
     */
    function availableCapacity() external view returns (uint256) {
        return BANK_CAPACITY - totalDeposited;
    }

    /**
     * @notice Retrieves comprehensive bank operational statistics
     * @return withdrawalLimit Current withdrawal limit per transaction in ETH
     * @return maximumCapacity Maximum capacity of the bank in ETH equivalent
     * @return currentTotal Total amount currently deposited in ETH equivalent
     * @return availableSpace Available remaining capacity in ETH equivalent
     * @dev Restricted to contract owner only for operational monitoring
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
     * @notice Retrieves comprehensive transaction statistics for the bank
     * @return totalDeposits Total number of successful deposit transactions
     * @return totalWithdrawals Total number of successful withdrawal transactions
     * @return totalTransactions Aggregate count of all deposit and withdrawal transactions
     * @dev Restricted to contract owner only for operational analytics
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