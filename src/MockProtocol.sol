// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMockProtocol.sol";

/**
 * @title MockProtocol
 * @notice Mock lending protocol untuk demo
 * @dev Simulate Aave/Compound dengan yield accrual sederhana
 */
contract MockProtocol is IMockProtocol, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    // Underlying asset (USDC)
    IERC20 public immutable usdc;

    // Protocol name
    string public name;

    // Protocol symbol
    string public symbol;

    // APY dalam basis points (800 = 8%, 1000 = 10%)
    uint256 public apy;

    // User balances - principal yang di-deposit
    mapping(address => uint256) private userPrincipal;

    // Last accrual timestamp per user
    mapping(address => uint256) private lastAccrualTime;

    // Total principal di protocol
    uint256 public totalPrincipal;

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // ============ Events ============

    event Supplied(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 amount, uint256 yield, uint256 timestamp);
    event InterestAccrued(address indexed user, uint256 yield, uint256 timestamp);
    event APYUpdated(uint256 newAPY);

    // ============ Constructor ============

    /**
     * @notice Initialize MockProtocol
     * @param _name Protocol name (e.g., "Mock Aave Protocol")
     * @param _symbol Protocol symbol (e.g., "mAAVE")
     * @param _usdc Address of USDC token
     * @param _apy Initial APY in basis points (e.g., 800 = 8%)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdc,
        uint256 _apy
    ) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_apy > 0 && _apy <= 5000, "APY must be between 0-50%");

        name = _name;
        symbol = _symbol;
        usdc = IERC20(_usdc);
        apy = _apy;
    }

    // ============ Main Functions ============

    /**
     * @notice Supply USDC ke protocol
     * @param amount Jumlah USDC yang akan di-supply
     * @return success True jika berhasil
     * @dev Accrue interest dulu sebelum update balance
     */
    function supply(uint256 amount) external override returns (bool) {
        require(amount > 0, "Cannot supply 0");

        // Accrue interest untuk existing balance
        if (userPrincipal[msg.sender] > 0) {
            _accrueInterest(msg.sender);
        }

        // Transfer USDC dari caller (Strategy) ke protocol
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Update balances
        userPrincipal[msg.sender] += amount;
        totalPrincipal += amount;

        // Set last accrual time
        lastAccrualTime[msg.sender] = block.timestamp;

        emit Supplied(msg.sender, amount, block.timestamp);

        return true;
    }

    /**
     * @notice Withdraw USDC dari protocol
     * @param amount Jumlah USDC yang akan di-withdraw (bisa include yield)
     * @return amountWithdrawn Actual USDC yang diterima
     * @dev Accrue interest dulu, lalu withdraw dari principal + yield
     */
    function withdraw(uint256 amount) external override returns (uint256) {
        require(amount > 0, "Cannot withdraw 0");

        // Accrue interest dulu
        _accrueInterest(msg.sender);

        // Get total balance (principal + yield)
        uint256 totalBalance = _calculateBalance(msg.sender);
        require(totalBalance >= amount, "Insufficient balance");

        // Calculate how much from principal vs yield
        uint256 principalToWithdraw = amount;
        uint256 yieldWithdrawn = 0;

        if (amount > userPrincipal[msg.sender]) {
            // Withdrawing principal + yield
            principalToWithdraw = userPrincipal[msg.sender];
            yieldWithdrawn = amount - principalToWithdraw;
        }

        // Update balances
        userPrincipal[msg.sender] -= principalToWithdraw;
        totalPrincipal -= principalToWithdraw;

        // Transfer USDC to caller
        usdc.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, yieldWithdrawn, block.timestamp);

        return amount;
    }

    /**
     * @notice Get balance dengan yield yang sudah terakumulasi
     * @param account Address yang akan dicek
     * @return balance Total USDC value (principal + accrued yield)
     */
    function balanceOf(address account) external view override returns (uint256) {
        return _calculateBalance(account);
    }

    /**
     * @notice Get principal balance tanpa yield
     * @param account Address yang akan dicek
     * @return principal Principal amount
     */
    function principalBalanceOf(address account) external view override returns (uint256) {
        return userPrincipal[account];
    }

    /**
     * @notice Get underlying asset address
     * @return asset USDC address
     */
    function asset() external view override returns (address) {
        return address(usdc);
    }

    /**
     * @notice Get current APY
     * @return Current APY in basis points
     */
    function getAPY() external view override returns (uint256) {
        return apy;
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate balance dengan accrued yield
     * @param account Address to calculate
     * @return balance Total balance (principal + yield)
     */
    function _calculateBalance(address account) internal view returns (uint256) {
        uint256 principal = userPrincipal[account];
        if (principal == 0) return 0;

        // Calculate time elapsed since last accrual
        uint256 timeElapsed = block.timestamp - lastAccrualTime[account];
        if (timeElapsed == 0) return principal;

        // Calculate yield: principal * APY * time / (BASIS_POINTS * SECONDS_PER_YEAR)
        uint256 yield = (principal * apy * timeElapsed) / (BASIS_POINTS * SECONDS_PER_YEAR);

        return principal + yield;
    }

    /**
     * @notice Accrue interest dan update principal
     * @param account Address to accrue interest for
     */
    function _accrueInterest(address account) internal {
        uint256 currentBalance = _calculateBalance(account);
        uint256 yield = currentBalance - userPrincipal[account];

        if (yield > 0) {
            // Add yield to principal (compound)
            userPrincipal[account] = currentBalance;
            totalPrincipal += yield;

            emit InterestAccrued(account, yield, block.timestamp);
        }

        // Update last accrual time
        lastAccrualTime[account] = block.timestamp;
    }

    // ============ Manual Functions (untuk Testing) ============

    /**
     * @notice Manually trigger interest accrual (untuk testing)
     * @dev Dalam real protocol, ini otomatis saat supply/withdraw
     */
    function accrueInterest() external override {
        _accrueInterest(msg.sender);
    }

    /**
     * @notice Accrue interest untuk specific user (owner only, untuk testing)
     * @param account Address to accrue interest for
     */
    function accrueInterestFor(address account) external onlyOwner {
        _accrueInterest(account);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update APY (owner only)
     * @param newAPY New APY in basis points
     */
    function setAPY(uint256 newAPY) external onlyOwner {
        require(newAPY > 0 && newAPY <= 5000, "APY must be between 0-50%");
        apy = newAPY;
        emit APYUpdated(newAPY);
    }

    /**
     * @notice Get total TVL di protocol
     * @return tvl Total USDC locked
     */
    function getTotalValueLocked() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}