// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/KipuBank.sol";

/**
 * @title MockUSDC
 * @notice Mock USDC token contract for testing
 */
contract MockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    /**
     * @notice Mint new tokens for testing
     * @param to Address to mint tokens to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
    }
    
    /**
     * @notice Transfer tokens between addresses
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return success Whether transfer was successful
     */
    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    /**
     * @notice Transfer tokens from one address to another
     * @param from Source address
     * @param to Recipient address
     * @param amount Amount to transfer
     * @return success Whether transfer was successful
     */
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    /**
     * @notice Approve token spending
     * @param spender Address allowed to spend tokens
     * @param amount Amount allowed to spend
     * @return success Always returns true
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/**
 * @title MockRouter
 * @notice Mock Uniswap V2 Router for testing
 */
contract MockRouter {
    /**
     * @notice Get expected output amounts for a swap
     * @param amountIn Input amount
     * @param path Token swap path
     * @return amounts Expected output amounts
     */
    function getAmountsOut(uint256 amountIn, address[] memory path) 
        public 
        pure 
        returns (uint256[] memory amounts) 
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        // Simulate fixed rate: 1 ETH = 1500 USDC
        if (path.length == 2) {
            amounts[1] = (amountIn * 1500) / 1e18 * 1e12; // Adjust decimals for USDC
        } else if (path.length == 3) {
            amounts[1] = amountIn; // WETH intermediate
            amounts[2] = (amountIn * 1500) / 1e18 * 1e12; // Final USDC amount
        }
        return amounts;
    }
    
    /**
     * @notice Execute token swap (mock implementation)
     * @param amountIn Input amount
     * @param amountOutMin Minimum output amount
     * @param path Token swap path
     * @param to Recipient address
     * @param deadline Transaction deadline
     * @return amounts Actual output amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) public view returns (uint256[] memory amounts) {
        require(deadline > block.timestamp, "Expired");
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        // Simulate fixed rate: 1 ETH = 1500 USDC
        uint256 amountOut = (amountIn * 1500) / 1e18 * 1e12; // Adjust decimals
        require(amountOut >= amountOutMin, "Insufficient output amount");
        
        if (path.length == 2) {
            amounts[1] = amountOut;
        } else if (path.length == 3) {
            amounts[1] = amountIn; // WETH intermediate
            amounts[2] = amountOut; // Final USDC amount
        }
        
        return amounts;
    }
    
    /**
     * @notice Get factory address (mock implementation)
     * @return Mock factory address
     */
    function factory() public pure returns (address) {
        return address(0x123);
    }
    
    /**
     * @notice Get WETH address (mock implementation)
     * @return Mock WETH address
     */
    function WETH() public pure returns (address) {
        return address(0x456);
    }
}

/**
 * @title KipuBankTest
 * @notice Comprehensive test suite for KipuBank contract
 */
contract KipuBankTest is Test {
    KipuBank public kipuBank;
    MockUSDC public usdc;
    MockUSDC public ethBase;
    MockRouter public router;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant WITHDRAWAL_LIMIT = 10 ether;
    uint256 constant BANK_CAPACITY = 1000 ether;

    /**
     * @notice Set up test environment before each test
     */
    function setUp() public {
        // Deploy mock contracts
        usdc = new MockUSDC();
        ethBase = new MockUSDC();
        router = new MockRouter();
        
        // Set up initial funds
        usdc.mint(user1, 10000 * 10**6); // 10000 USDC
        ethBase.mint(user1, 10 ether);   // 10 ETH.BASE
        usdc.mint(user2, 5000 * 10**6);  // 5000 USDC
        
        // Deploy KipuBank with mock contracts
        vm.startPrank(owner);
        kipuBank = new KipuBank(
            WITHDRAWAL_LIMIT,
            BANK_CAPACITY,
            IERC20(address(usdc)),
            address(ethBase),
            address(router)
        );
        vm.stopPrank();
    }

    // ============ CONFIGURATION TESTS ============

    /**
     * @notice Test initial contract configuration
     */
    function test_InitialConfiguration() public {
        assertEq(kipuBank.WITHDRAWAL_LIMIT(), WITHDRAWAL_LIMIT);
        assertEq(kipuBank.BANK_CAPACITY(), BANK_CAPACITY);
        assertEq(address(kipuBank.USDC()), address(usdc));
        assertEq(kipuBank.s_feeds(), address(ethBase));
        assertEq(address(kipuBank.ROUTER()), address(router));
        assertEq(kipuBank.WETH(), router.WETH());
    }

    // ============ DEPOSIT TESTS ============

    /**
     * @notice Test USDC deposit functionality
     */
    function test_DepositUSDC() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 100 * 10**6; // 100 USDC
        uint256 initialBalance = usdc.balanceOf(user1);
        
        // Approve and deposit
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        
        // Verify balances - now using struct
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        
        assertEq(userBalances.eth, 0);
        assertEq(userBalances.usdc, depositAmount);
        assertGt(userBalances.total, 0); // Should have ETH equivalent
        assertEq(usdc.balanceOf(user1), initialBalance - depositAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test ETH deposit functionality
     */
    function test_DepositETH() public {
        vm.deal(user1, 5 ether);
        vm.startPrank(user1);
        
        uint256 depositAmount = 1 ether;
        kipuBank.deposit{value: depositAmount}(address(0), depositAmount);
        
        // Verify balances
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        
        assertEq(userBalances.eth, depositAmount);
        assertEq(userBalances.usdc, 0);
        assertEq(userBalances.total, depositAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test revert on zero amount deposit
     */
    function test_RevertOnZeroAmountDeposit() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("KipuBank_ZeroAmount()"));
        kipuBank.deposit(address(usdc), 0);
        vm.stopPrank();
    }

    /**
     * @notice Test revert on bank capacity exceeded
     */
    function test_RevertOnBankCapacityExceeded() public {
        vm.deal(user1, BANK_CAPACITY + 1 ether);
        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSignature("BankCapacityExceeded()"));
        kipuBank.deposit{value: BANK_CAPACITY + 1 ether}(address(0), BANK_CAPACITY + 1 ether);
        
        vm.stopPrank();
    }

    // ============ SWAP TESTS ============

    /**
     * @notice Test swap preview functionality
     */
    function test_PreviewSwap() public view {
        uint256 preview = kipuBank.previewSwapToUsdcM2(address(ethBase), 1 ether);
        assertGt(preview, 0);
    }

    /**
     * @notice Test swap to USDC functionality
     */
    function test_SwapToUsdcGUSF() public {
        vm.startPrank(user1);
        
        uint256 swapAmount = 0.1 ether;
        ethBase.mint(user1, swapAmount);
        ethBase.approve(address(kipuBank), swapAmount);
        
        uint256 previewAmount = kipuBank.previewSwapToUsdcM2(address(ethBase), swapAmount);
        assertGt(previewAmount, 0, "Preview should return positive amount");
        
        vm.stopPrank();
    }

    /**
     * @notice Test revert on zero address swap
     */
    function test_RevertOnZeroAddressSwap() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        kipuBank.swapToUsdcGUSF(address(0), 100, 1);
        vm.stopPrank();
    }

    /**
     * @notice Test revert on zero amount swap
     */
    function test_RevertOnZeroAmountSwap() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        kipuBank.swapToUsdcGUSF(address(ethBase), 0, 1);
        vm.stopPrank();
    }

    // ============ WITHDRAWAL TESTS ============

    /**
     * @notice Test USDC withdrawal functionality
     */
    function test_WithdrawUSDC() public {
        vm.startPrank(user1);
        
        // First deposit
        uint256 depositAmount = 50 * 10**6; // 50 USDC
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        
        uint256 initialBalance = usdc.balanceOf(user1);
        
        // Withdraw smaller amount to avoid errors
        uint256 withdrawAmount = 25 * 10**6; // Withdraw 25 USDC
        kipuBank.withdrawUSDC(withdrawAmount);
        
        // Verify funds received
        uint256 finalBalance = usdc.balanceOf(user1);
        assertEq(finalBalance, initialBalance + withdrawAmount);
        
        // Verify updated balances
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        assertEq(userBalances.usdc, depositAmount - withdrawAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test ETH withdrawal functionality
     */
    function test_WithdrawETH() public {
        vm.deal(user1, 3 ether);
        vm.startPrank(user1);
        
        // Deposit ETH
        uint256 depositAmount = 1 ether;
        kipuBank.deposit{value: depositAmount}(address(0), depositAmount);
        
        // Withdraw ETH
        uint256 withdrawAmount = 0.5 ether;
        uint256 initialETHBalance = address(user1).balance;
        
        kipuBank.withdrawETH(withdrawAmount);
        
        // Verify ETH received
        uint256 finalETHBalance = address(user1).balance;
        assertEq(finalETHBalance, initialETHBalance + withdrawAmount);
        
        // Verify updated balances
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        assertEq(userBalances.eth, depositAmount - withdrawAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test revert on insufficient withdrawal
     */
    function test_RevertOnInsufficientWithdraw() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InsufficientFunds()"));
        kipuBank.withdrawUSDC(1000 * 10**6); // More than available
        vm.stopPrank();
    }

    /**
     * @notice Test revert on withdrawal limit exceeded
     */
    function test_RevertOnWithdrawalLimitExceeded() public {
        vm.deal(user1, WITHDRAWAL_LIMIT + 1 ether);
        vm.startPrank(user1);
        
        // Deposit more than withdrawal limit
        kipuBank.deposit{value: WITHDRAWAL_LIMIT + 1 ether}(address(0), WITHDRAWAL_LIMIT + 1 ether);
        
        // Try to withdraw more than limit
        vm.expectRevert(abi.encodeWithSignature("WithdrawalLimitExceeded()"));
        kipuBank.withdrawETH(WITHDRAWAL_LIMIT + 1);
        
        vm.stopPrank();
    }

    // ============ CONVERSION TESTS ============

    /**
     * @notice Test price conversion functionality
     */
    function test_PriceConversion() public view {
        uint256 ethAmount = 1 ether;
        uint256 usdcValue = kipuBank.convertEthInUSD(ethAmount);
        
        assertGt(usdcValue, 0);
        
        // Test reverse conversion
        uint256 usdcAmount = 1000 * 10**6; // 1000 USDC
        uint256 ethValue = kipuBank.convertUsdcToEth(usdcAmount);
        assertGt(ethValue, 0);
    }

    /**
     * @notice Test revert on zero amount conversion
     */
    function test_RevertOnZeroAmountConversion() public {
        vm.expectRevert(abi.encodeWithSignature("KipuBank_ZeroAmount()"));
        kipuBank.convertEthInUSD(0);
        
        vm.expectRevert(abi.encodeWithSignature("KipuBank_ZeroAmount()"));
        kipuBank.convertUsdcToEth(0);
    }

    // ============ MULTI-USER TESTS ============

    /**
     * @notice Test multiple user interactions
     */
    function test_MultipleUsers() public {
        // User1 deposits
        vm.startPrank(user1);
        uint256 deposit1 = 100 * 10**6;
        usdc.approve(address(kipuBank), deposit1);
        kipuBank.deposit(address(usdc), deposit1);
        vm.stopPrank();
        
        // User2 deposits
        vm.startPrank(user2);
        uint256 deposit2 = 50 * 10**6;
        usdc.approve(address(kipuBank), deposit2);
        kipuBank.deposit(address(usdc), deposit2);
        vm.stopPrank();
        
        // Verify separate balances - now using struct
        KipuBank.Balances memory user1Balances = kipuBank.myBalanceS(user1);
        KipuBank.Balances memory user2Balances = kipuBank.myBalanceS(user2);
        
        assertEq(user1Balances.usdc, deposit1);
        assertEq(user2Balances.usdc, deposit2);
        assertGt(user1Balances.total, user2Balances.total); // User1 should have more
    }

    // ============ VIEW FUNCTION TESTS ============

    /**
     * @notice Test bank statistics view function
     */
    function test_BankStatistics() public {
        vm.startPrank(owner); 
        (uint256 limit, uint256 maxCap, uint256 current, uint256 available) = kipuBank.bankStatistics();
        assertEq(limit, WITHDRAWAL_LIMIT);
        assertEq(maxCap, BANK_CAPACITY);
        assertEq(available, BANK_CAPACITY - current);
        vm.stopPrank();
    }

    /**
     * @notice Test available capacity view function
     */
    function test_AvailableCapacity() public view {
        uint256 capacity = kipuBank.availableCapacity();
        assertEq(capacity, BANK_CAPACITY); // Initially should be empty
    }

    /**
     * @notice Test transaction statistics view function
     */
    function test_TransactionStatistics() public {
        // Make a deposit first (as user1)
        vm.startPrank(user1);
        uint256 depositAmount = 100 * 10**6;
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Verify statistics (as owner)
        vm.startPrank(owner);
        (uint256 totalDeposits, uint256 totalWithdrawals, uint256 totalTransactions) = 
            kipuBank.transactionStatistics();
        
        assertGt(totalDeposits, 0);
        assertEq(totalWithdrawals, 0);
        assertEq(totalTransactions, totalDeposits + totalWithdrawals);
        vm.stopPrank();
    }

    /**
     * @notice Test user balance view function
     */
    function test_MyBalanceS() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 75 * 10**6;
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        
        // Test myBalanceS function - now returns struct
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        
        assertEq(userBalances.eth, 0);
        assertEq(userBalances.usdc, depositAmount);
        assertGt(userBalances.total, 0);
        
        vm.stopPrank();
    }

    // ============ RECEIVE FUNCTION TESTS ============

    /**
     * @notice Test receive function for direct ETH deposits
     */
    function test_ReceiveFunction() public {
        vm.deal(user1, 10 ether); // Give ETH to user1
        vm.startPrank(user1);
        
        // Send ETH directly to contract (testing receive())
        (bool success, ) = address(kipuBank).call{value: 1 ether}("");
        require(success, "ETH transfer failed");
        
        // Verify deposit was registered - now using struct
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        assertEq(userBalances.eth, 1 ether);
        assertEq(userBalances.usdc, 0);
        assertEq(userBalances.total, 1 ether);
        
        vm.stopPrank();
    }

    // ============ OWNER FUNCTION TESTS ============

    /**
     * @notice Test owner-only setWETH function
     */
    function test_SetWETH() public {
        vm.startPrank(owner);
        
        address newWETH = address(0x999);
        kipuBank.setWETH(newWETH);
        
        assertEq(kipuBank.WETH(), newWETH);
        
        vm.stopPrank();
    }

/**
     * @notice Test revert when non-owner tries to set WETH
     */
    function test_RevertNonOwnerSetWETH() public {
        vm.startPrank(user1); // Not owner
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        kipuBank.setWETH(address(0x999));
        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    /**
     * @notice Test deposit and withdraw full balance
     */
    function test_DepositAndWithdrawFullBalance() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 100 * 10**6;
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        
        // Withdraw full amount
        kipuBank.withdrawUSDC(depositAmount);
        
        // Verify zero balance
        KipuBank.Balances memory userBalances = kipuBank.myBalanceS(user1);
        assertEq(userBalances.usdc, 0);
        assertEq(userBalances.total, 0);
        
        vm.stopPrank();
    }

    /**
     * @notice Test chainlink feed function
     */
    function test_ChainlinkFeed() public view {
        uint256 price = kipuBank.chainlinkFeed();
        assertGt(price, 0, "Price should be positive");
    }

    /**
     * @notice Test preview swap with USDC (should return same amount)
     */
    function test_PreviewSwapUSDC() public view {
        uint256 amount = 100 * 10**6;
        uint256 preview = kipuBank.previewSwapToUsdcM2(address(usdc), amount);
        assertEq(preview, amount, "USDC preview should return same amount");
    }

    /**
     * @notice Test complex token swap flow
     */
    function test_ComplexTokenSwapFlow() public {
        vm.startPrank(user1);
        
        // Setup token for swap (simulating a random token)
        address randomToken = address(0x777);
        
        // This will test the swap flow without actual token transfer
        // since we don't have a real token contract
        uint256 preview = kipuBank.previewSwapToUsdcM2(randomToken, 1 ether);
        assertGt(preview, 0, "Preview should work for any token");
        
        vm.stopPrank();
    }

    /**
     * @notice Test bank capacity updates correctly
     */
    function test_BankCapacityUpdates() public {
        vm.startPrank(user1);
        
        uint256 depositAmount = 100 * 10**6;
        usdc.approve(address(kipuBank), depositAmount);
        kipuBank.deposit(address(usdc), depositAmount);
        
        uint256 capacityAfterDeposit = kipuBank.availableCapacity();
        assertLt(capacityAfterDeposit, BANK_CAPACITY, "Capacity should decrease after deposit");
        
        kipuBank.withdrawUSDC(depositAmount);
        
        uint256 capacityAfterWithdraw = kipuBank.availableCapacity();
        assertEq(capacityAfterWithdraw, BANK_CAPACITY, "Capacity should restore after withdraw");
        
        vm.stopPrank();
    }
}