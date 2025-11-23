// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockProtocol
 * @notice Mock lending protocol untuk simulate Aave/Compound
 * @dev Terima USDC deposit, mint receipt token, simulate yield accrual
 */
contract MockProtocol is ERC20, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    // Underlying asset (USDC)
    IERC20 public immutable usdc;

    // APY dalam basis points (1000 = 10%)
    uint256 public apyBasisPoints;

    // Mapping: user => supplied USDC amount (principal)
    mapping(address => uint256) public suppliedAmount;

    // Mapping: user => last interaction timestamp
    mapping(address => uint256) public lastUpdateTime;

    // Total USDC supplied ke protocol
    uint256 public totalSupplied;

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // ============ Events ============

    event Supplied(address indexed user, uint256 amount, uint256 receiptTokens);
    event Withdrawn(
        address indexed user,
        uint256 amount,
        uint256 receiptTokensBurned
    );
    event APYUpdated(uint256 newAPY);
    event InterestAccrued(address indexed user, uint256 interest);

    // ============ Constructor ============

    /**
     * @notice Initialize MockProtocol
     * @param _name Name of receipt token (e.g., "Mock Aave USDC")
     * @param _symbol Symbol of receipt token (e.g., "mAAVE")
     * @param _usdc Address of USDC token
     * @param _apyBasisPoints Initial APY in basis points (e.g., 800 = 8%)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdc,
        uint256 _apyBasisPoints
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_apyBasisPoints <= 5000, "APY too high (max 50%)");

        usdc = IERC20(_usdc);
        apyBasisPoints = _apyBasisPoints;
    }

    // ============ Main Functions ============

    /**
     * @notice Supply USDC ke protocol dan mint receipt tokens
     * @param asset Address of asset (must be USDC)
     * @param amount Jumlah USDC yang akan di-supply
     * @param onBehalfOf Address yang akan menerima receipt tokens
     * @dev Mengikuti interface Aave-style untuk consistency
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external {
        require(asset == address(usdc), "Invalid asset");
        require(amount > 0, "Cannot supply 0");
        require(onBehalfOf != address(0), "Invalid recipient");

        // Accrue interest untuk user sebelum update balance
        _accrueInterest(onBehalfOf);

        // Transfer USDC from caller (Strategy) to this contract
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update supplied amount
        suppliedAmount[onBehalfOf] += amount;
        totalSupplied += amount;

        // Mint receipt tokens 1:1 dengan USDC supplied
        // Dalam real protocol seperti Aave, ini lebih complex
        // Tapi untuk demo, kita pakai 1:1 untuk simplicity
        _mint(onBehalfOf, amount);

        // Update last interaction time
        lastUpdateTime[onBehalfOf] = block.timestamp;

        emit Supplied(onBehalfOf, amount, amount);
    }

    /**
     * @notice Withdraw USDC dari protocol dan burn receipt tokens
     * @param asset Address of asset (must be USDC)
     * @param amount Jumlah USDC yang akan di-withdraw (max = type(uint256).max untuk withdraw all)
     * @param to Address yang akan menerima USDC
     * @return amountWithdrawn Actual USDC amount yang di-withdraw (termasuk yield)
     */
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256 amountWithdrawn) {
        require(asset == address(usdc), "Invalid asset");
        require(to != address(0), "Invalid recipient");

        // Accrue interest dulu
        _accrueInterest(msg.sender);

        // Get current balance including yield
        uint256 currentBalance = getSuppliedBalance(msg.sender);
        require(currentBalance > 0, "No balance to withdraw");

        // Handle max withdraw
        if (amount == type(uint256).max) {
            amount = currentBalance;
        }

        require(amount <= currentBalance, "Insufficient balance");
        require(
            amount <= usdc.balanceOf(address(this)),
            "Insufficient liquidity"
        );

        // Calculate berapa receipt tokens yang harus di-burn
        // Karena kita pakai 1:1 mapping, burn sesuai principal + yield proportion
        uint256 tokensToBurn = (balanceOf(msg.sender) * amount) /
            currentBalance;

        // Update supplied amount (reduce proportionally)
        uint256 principalReduction = (suppliedAmount[msg.sender] * amount) /
            currentBalance;
        suppliedAmount[msg.sender] -= principalReduction;
        totalSupplied -= principalReduction;

        // Burn receipt tokens
        _burn(msg.sender, tokensToBurn);

        // Transfer USDC to recipient
        usdc.safeTransfer(to, amount);

        // Update last interaction time
        lastUpdateTime[msg.sender] = block.timestamp;

        emit Withdrawn(msg.sender, amount, tokensToBurn);

        return amount;
    }

    // ============ Interest Accrual ============

    /**
     * @notice Accrue interest untuk user tertentu
     * @param user Address of user
     * @dev Internal function yang dipanggil sebelum setiap balance update
     */
    function _accrueInterest(address user) internal {
        if (suppliedAmount[user] == 0) return;

        uint256 timeElapsed = block.timestamp - lastUpdateTime[user];
        if (timeElapsed == 0) return;

        // Calculate interest: principal × APY × timeElapsed / 365 days
        uint256 interest = (suppliedAmount[user] *
            apyBasisPoints *
            timeElapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);

        if (interest > 0) {
            // Add interest to supplied amount (compound)
            suppliedAmount[user] += interest;
            totalSupplied += interest;

            // Mint additional receipt tokens untuk represent yield
            _mint(user, interest);

            emit InterestAccrued(user, interest);
        }

        // Update timestamp
        lastUpdateTime[user] = block.timestamp;
    }

    /**
     * @notice Manually trigger interest accrual untuk testing
     * @param user Address of user
     * @dev Public function untuk demo/testing purposes
     */
    function accrueInterest(address user) external {
        _accrueInterest(user);
    }

    /**
     * @notice Batch accrue interest untuk multiple users
     * @param users Array of user addresses
     */
    function accrueInterestBatch(address[] calldata users) external {
        for (uint256 i = 0; i < users.length; i++) {
            _accrueInterest(users[i]);
        }
    }

    // ============ View Functions ============

    /**
     * @notice Get supplied balance including accrued interest
     * @param account Address of user
     * @return balance Total USDC value (principal + pending interest)
     */
    function getSuppliedBalance(
        address account
    ) public view returns (uint256 balance) {
        if (suppliedAmount[account] == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastUpdateTime[account];

        // Calculate pending interest
        uint256 pendingInterest = (suppliedAmount[account] *
            apyBasisPoints *
            timeElapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);

        return suppliedAmount[account] + pendingInterest;
    }

    /**
     * @notice Get principal amount (tanpa interest)
     * @param account Address of user
     * @return principal Principal USDC amount
     */
    function getPrincipal(
        address account
    ) external view returns (uint256 principal) {
        return suppliedAmount[account];
    }

    /**
     * @notice Get pending interest untuk user
     * @param account Address of user
     * @return interest Pending interest amount
     */
    function getPendingInterest(
        address account
    ) external view returns (uint256 interest) {
        if (suppliedAmount[account] == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastUpdateTime[account];

        return
            (suppliedAmount[account] * apyBasisPoints * timeElapsed) /
            (BASIS_POINTS * SECONDS_PER_YEAR);
    }

    /**
     * @notice Get current APY
     * @return apy APY in basis points
     */
    function getAPY() external view returns (uint256 apy) {
        return apyBasisPoints;
    }

    /**
     * @notice Get total supplied USDC ke protocol
     * @return total Total USDC supplied
     */
    function getTotalSupplied() external view returns (uint256 total) {
        return totalSupplied;
    }

    /**
     * @notice Get available liquidity untuk withdrawals
     * @return liquidity Available USDC balance
     */
    function getAvailableLiquidity() external view returns (uint256 liquidity) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @notice Calculate projected balance setelah X days
     * @param account User address
     * @param daysAhead Number of days to project
     * @return projectedBalance Projected balance after X days
     */
    function projectBalance(
        address account,
        uint256 daysAhead
    ) external view returns (uint256 projectedBalance) {
        uint256 currentBalance = getSuppliedBalance(account);
        if (currentBalance == 0) return 0;

        uint256 additionalInterest = (currentBalance *
            apyBasisPoints *
            (daysAhead * 1 days)) / (BASIS_POINTS * SECONDS_PER_YEAR);

        return currentBalance + additionalInterest;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update APY
     * @param newAPY New APY in basis points (e.g., 1000 = 10%)
     * @dev Only owner dapat update APY untuk simulate market changes
     */
    function setAPY(uint256 newAPY) external onlyOwner {
        require(newAPY <= 5000, "APY too high (max 50%)");
        apyBasisPoints = newAPY;
        emit APYUpdated(newAPY);
    }

    /**
     * @notice Emergency withdraw untuk owner (hanya untuk testing)
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     * @dev Untuk rescue stuck tokens, jangan dipakai di production
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Simulate adding liquidity to protocol
     * @param amount Amount of USDC to add
     * @dev Untuk testing scenarios dengan liquidity pool
     */
    function addLiquidity(uint256 amount) external onlyOwner {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
    }

    // ============ Helper Functions ============

    /**
     * @notice Override decimals untuk match USDC (6 decimals)
     * @return decimals Token decimals
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Get time since last update untuk user
     * @param account User address
     * @return timeElapsed Seconds since last interaction
     */
    function getTimeSinceLastUpdate(
        address account
    ) external view returns (uint256 timeElapsed) {
        if (lastUpdateTime[account] == 0) return 0;
        return block.timestamp - lastUpdateTime[account];
    }

    /**
     * @notice Calculate APY untuk amount tertentu dalam USDC per year
     * @param amount Principal amount
     * @return yearlyYield Projected yearly yield in USDC
     */
    function calculateYearlyYield(
        uint256 amount
    ) external view returns (uint256 yearlyYield) {
        return (amount * apyBasisPoints) / BASIS_POINTS;
    }

    /**
     * @notice Calculate APY untuk amount tertentu dalam USDC per day
     * @param amount Principal amount
     * @return dailyYield Projected daily yield in USDC
     */
    function calculateDailyYield(
        uint256 amount
    ) external view returns (uint256 dailyYield) {
        return (amount * apyBasisPoints) / (BASIS_POINTS * 365);
    }
}
