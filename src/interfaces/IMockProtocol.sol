// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMockProtocol
 * @notice Interface untuk MockProtocol lending contract
 * @dev Interface ini dapat digunakan oleh contract lain untuk berinteraksi dengan MockProtocol
 */
interface IMockProtocol is IERC20 {
    // ============ Events ============

    event Supplied(address indexed user, uint256 amount, uint256 receiptTokens);
    event Withdrawn(
        address indexed user,
        uint256 amount,
        uint256 receiptTokensBurned
    );
    event APYUpdated(uint256 newAPY);
    event InterestAccrued(address indexed user, uint256 interest);

    // ============ Main Functions ============

    /**
     * @notice Supply USDC ke protocol dan mint receipt tokens
     * @param asset Address of asset (must be USDC)
     * @param amount Jumlah USDC yang akan di-supply
     * @param onBehalfOf Address yang akan menerima receipt tokens
     */
    function supply(address asset, uint256 amount, address onBehalfOf) external;

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
    ) external returns (uint256 amountWithdrawn);

    // ============ Interest Accrual Functions ============

    /**
     * @notice Manually trigger interest accrual untuk testing
     * @param user Address of user
     */
    function accrueInterest(address user) external;

    /**
     * @notice Batch accrue interest untuk multiple users
     * @param users Array of user addresses
     */
    function accrueInterestBatch(address[] calldata users) external;

    // ============ View Functions ============

    /**
     * @notice Get underlying USDC token address
     * @return USDC token address
     */
    function usdc() external view returns (IERC20);

    /**
     * @notice Get current APY in basis points
     * @return APY in basis points
     */
    function apyBasisPoints() external view returns (uint256);

    /**
     * @notice Get supplied amount (principal) for user
     * @param account User address
     * @return Principal amount
     */
    function suppliedAmount(address account) external view returns (uint256);

    /**
     * @notice Get last update timestamp for user
     * @param account User address
     * @return Last update timestamp
     */
    function lastUpdateTime(address account) external view returns (uint256);

    /**
     * @notice Get total USDC supplied to protocol
     * @return Total supplied amount
     */
    function totalSupplied() external view returns (uint256);

    /**
     * @notice Get supplied balance including accrued interest
     * @param account Address of user
     * @return balance Total USDC value (principal + pending interest)
     */
    function getSuppliedBalance(
        address account
    ) external view returns (uint256 balance);

    /**
     * @notice Get principal amount (tanpa interest)
     * @param account Address of user
     * @return principal Principal USDC amount
     */
    function getPrincipal(
        address account
    ) external view returns (uint256 principal);

    /**
     * @notice Get pending interest untuk user
     * @param account Address of user
     * @return interest Pending interest amount
     */
    function getPendingInterest(
        address account
    ) external view returns (uint256 interest);

    /**
     * @notice Get current APY
     * @return apy APY in basis points
     */
    function getAPY() external view returns (uint256 apy);

    /**
     * @notice Get total supplied USDC ke protocol
     * @return total Total USDC supplied
     */
    function getTotalSupplied() external view returns (uint256 total);

    /**
     * @notice Get available liquidity untuk withdrawals
     * @return liquidity Available USDC balance
     */
    function getAvailableLiquidity() external view returns (uint256 liquidity);

    /**
     * @notice Calculate projected balance setelah X days
     * @param account User address
     * @param daysAhead Number of days to project
     * @return projectedBalance Projected balance after X days
     */
    function projectBalance(
        address account,
        uint256 daysAhead
    ) external view returns (uint256 projectedBalance);

    /**
     * @notice Get time since last update untuk user
     * @param account User address
     * @return timeElapsed Seconds since last interaction
     */
    function getTimeSinceLastUpdate(
        address account
    ) external view returns (uint256 timeElapsed);

    /**
     * @notice Calculate APY untuk amount tertentu dalam USDC per year
     * @param amount Principal amount
     * @return yearlyYield Projected yearly yield in USDC
     */
    function calculateYearlyYield(
        uint256 amount
    ) external view returns (uint256 yearlyYield);

    /**
     * @notice Calculate APY untuk amount tertentu dalam USDC per day
     * @param amount Principal amount
     * @return dailyYield Projected daily yield in USDC
     */
    function calculateDailyYield(
        uint256 amount
    ) external view returns (uint256 dailyYield);

    // ============ Admin Functions ============

    /**
     * @notice Update APY
     * @param newAPY New APY in basis points (e.g., 1000 = 10%)
     */
    function setAPY(uint256 newAPY) external;

    /**
     * @notice Emergency withdraw untuk owner (hanya untuk testing)
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external;

    /**
     * @notice Simulate adding liquidity to protocol
     * @param amount Amount of USDC to add
     */
    function addLiquidity(uint256 amount) external;
}
