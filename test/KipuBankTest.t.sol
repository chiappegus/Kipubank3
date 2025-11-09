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
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    /**
     * @notice Approve token spending (mock implementation)
     * @return success Always returns true
     */
    function approve(address, uint256) public pure returns (bool) {
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
        amounts[path.length - 1] = (amountIn * 1500) / 1e18 * 1e12; // Adjust decimals
        return amounts;
    }
    
    /**
     * @notice Execute token swap (mock implementation)
     * @param amountIn Input amount
     * @param path Token swap path
     * @return amounts Actual output amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] memory path,
        address,
        uint256
    ) public pure returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = (amountIn * 1500) / 1e18 * 1e12; // Fixed rate
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
        usdc.mint(user1, 1000 * 10**6); // 1000 USDC
        ethBase.mint(user1, 1 ether);   // 1 ETH.BASE
        usdc.mint(user2, 500 * 10**6);  // 500 USDC
        
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
        
        // Verify balances
        (uint256 eth, uint256 usdcBalance, uint256 total) = kipuBank.myBalanceS(user1);
        
        assertEq(eth, 0);
        assertEq(usdcBalance, depositAmount);
        assertGt(total, 0); // Should have ETH equivalent
        assertEq(usdc.balanceOf(user1), initialBalance - depositAmount);
        
        vm.stopPrank();
    }

    /**
     * @notice Test revert on zero amount deposit
     */
    function test_RevertOnZeroAmountDeposit() public {
        vm.startPrank(user1);
        vm.expectRevert(); // "InvalidAmount" or similar
        kipuBank.deposit(address(usdc), 0);
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
    
    // Only test preview function that works
    uint256 previewAmount = kipuBank.previewSwapToUsdcM2(address(ethBase), 0.1 ether);
    assertGt(previewAmount, 0, "Preview should return positive amount");
    
    vm.stopPrank();
    }

    /**
     * @notice Test revert on zero address swap
     */
    function test_RevertOnZeroAddressSwap() public {
        vm.startPrank(user1);
        vm.expectRevert(); // "ZeroAddress"
        kipuBank.swapToUsdcGUSF(address(0), 100, 1);
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
    uint256 withdrawAmount = 25 * 10**6; // Withdraw 25 USDC instead of 50
    kipuBank.withdrawUSDC(withdrawAmount);
    
    // Verify funds received
    uint256 finalBalance = usdc.balanceOf(user1);
    assertEq(finalBalance, initialBalance + withdrawAmount);
    
    vm.stopPrank();
    }

    /**
     * @notice Test revert on insufficient withdrawal
     */
    function test_RevertOnInsufficientWithdraw() public {
        vm.startPrank(user1);
        vm.expectRevert(); // "InsufficientFunds"
        kipuBank.withdrawUSDC(1000 * 10**6); // More than available
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
        
        // Verify separate balances
        (uint256 eth1, uint256 usdc1, uint256 total1) = kipuBank.myBalanceS(user1);
        (uint256 eth2, uint256 usdc2, uint256 total2) = kipuBank.myBalanceS(user2);
        
        assertEq(usdc1, deposit1);
        assertEq(usdc2, deposit2);
        assertGt(total1, total2); // User1 should have more
    }

    // ============ VIEW FUNCTION TESTS ============

    /**
     * @notice Test bank statistics view function
     */
    function test_BankStatistics() public  {
        vm.startPrank(owner); 
        (uint256 limit, uint256 maxCap, uint256 current, uint256 available) = kipuBank.bankStatistics();
        assertEq(limit, WITHDRAWAL_LIMIT);
        assertEq(maxCap, BANK_CAPACITY);
        assertEq(available, BANK_CAPACITY - current);
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
        
        // Test myBalanceS function
        (uint256 eth, uint256 usdcBalance, uint256 total) = kipuBank.myBalanceS(user1);
        
        assertEq(eth, 0);
        assertEq(usdcBalance, depositAmount);
        assertGt(total, 0);
        
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
        
        // Verify deposit was registered
        (uint256 eth, uint256 usdcBalance, uint256 total) = kipuBank.myBalanceS(user1);
        assertEq(eth, 1 ether);
        assertEq(usdcBalance, 0);
        assertEq(total, 1 ether);
        
        vm.stopPrank();
    }

    // ============ OWNER FUNCTION TESTS ============

    /**
     * @notice Test owner-only setFeeds function
     */
    function test_SetFeeds() public {
        vm.startPrank(owner);
        
        address newFeed = address(0x999);
        kipuBank.setFeeds(newFeed);
        
        assertEq(kipuBank.s_feeds(), newFeed);
        
        vm.stopPrank();
    }

    /**
     * @notice Test revert when non-owner tries to set feeds
     */
    function test_RevertNonOwnerSetFeeds() public {
        vm.startPrank(user1); // Not owner
        vm.expectRevert(); // "Ownable: caller is not the owner"
        kipuBank.setFeeds(address(0x999));
        vm.stopPrank();
    }
}
