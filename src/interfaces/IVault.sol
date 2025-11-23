// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVault
 * @notice Interface untuk berinteraksi dengan Vault contracts
 */
interface IVault {
    /**
     * @notice Deposit USDC ke vault dan mint shares
     * @param assets Jumlah USDC yang akan di-deposit
     * @return shares Jumlah shares yang di-mint untuk depositor
     */
    function deposit(uint256 assets) external returns (uint256 shares);

    /**
     * @notice Redeem shares untuk withdraw USDC
     * @param shares Jumlah shares yang akan di-burn
     * @return assets Jumlah USDC yang dikembalikan
     */
    function redeem(uint256 shares) external returns (uint256 assets);

    /**
     * @notice Get total assets (USDC) dalam vault
     * @return totalAssets Total USDC value di vault termasuk yang deployed ke protocols
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Preview berapa shares yang akan diterima untuk deposit amount tertentu
     * @param assets Jumlah USDC yang akan di-deposit
     * @return shares Estimasi shares yang akan diterima
     */
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256 shares);

    /**
     * @notice Preview berapa assets yang akan diterima untuk redeem shares tertentu
     * @param shares Jumlah shares yang akan di-redeem
     * @return assets Estimasi USDC yang akan diterima
     */
    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets);
}
