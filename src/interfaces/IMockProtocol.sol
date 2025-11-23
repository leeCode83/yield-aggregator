// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMockProtocol
 * @notice Interface untuk berinteraksi dengan Mock Protocol
 */
interface IMockProtocol {
    /**
     * @notice Supply USDC ke protocol dan mint receipt tokens
     * @param amount Jumlah USDC yang akan di-supply
     * @return success True jika berhasil
     */
    function supply(uint256 amount) external returns (bool success);

    /**
     * @notice Withdraw USDC dari protocol dan burn receipt tokens
     * @param amount Jumlah USDC yang akan di-withdraw
     * @return amountWithdrawn Actual USDC yang diterima
     */
    function withdraw(uint256 amount) external returns (uint256 amountWithdrawn);

    /**
     * @notice Get balance dengan yield yang sudah terakumulasi
     * @param account Address yang akan dicek
     * @return balance Total USDC value (principal + yield)
     */
    function balanceOf(address account) external view returns (uint256 balance);

    /**
     * @notice Get principal balance tanpa yield
     * @param account Address yang akan dicek
     * @return principal Principal amount yang di-deposit
     */
    function principalBalanceOf(address account) external view returns (uint256 principal);

    /**
     * @notice Trigger yield accrual secara manual (untuk testing)
     */
    function accrueInterest() external;

    /**
     * @notice Get current APY
     * @return apy APY dalam basis points (800 = 8%)
     */
    function getAPY() external view returns (uint256 apy);

    /**
     * @notice Get underlying asset (USDC)
     * @return asset Address of USDC
     */
    function asset() external view returns (address asset);
}