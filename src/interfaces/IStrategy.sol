// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStrategy
 * @notice Interface untuk berinteraksi dengan Strategy contracts (Aave, Compound, dll)
 */
interface IStrategy {
    /**
     * @notice Deploy USDC ke protocol (Aave/Compound)
     * @param amount Jumlah USDC yang akan di-deploy
     * @return success True jika berhasil
     */
    function deposit(uint256 amount) external returns (bool success);

    /**
     * @notice Withdraw USDC dari protocol
     * @param amount Jumlah USDC yang akan di-withdraw
     * @return amountReceived Actual USDC yang diterima
     */
    function withdraw(uint256 amount) external returns (uint256 amountReceived);

    /**
     * @notice Harvest earned interest dari protocol
     * @return earned Jumlah interest yang di-harvest
     */
    function harvest() external returns (uint256 earned);

    /**
     * @notice Get total balance USDC di strategy (principal + earned interest)
     * @return balance Total USDC value
     */
    function balanceOf() external view returns (uint256 balance);

    /**
     * @notice Emergency withdraw all funds dari protocol
     * @return amount Total USDC yang di-withdraw
     */
    function withdrawAll() external returns (uint256 amount);

    /**
     * @notice Get underlying asset address (USDC)
     * @return asset Address of USDC token
     */
    function asset() external view returns (address);
}
