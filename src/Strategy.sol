// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IMockProtocol.sol";

/**
 * @title Strategy
 * @notice Generic strategy untuk interact dengan MockProtocol
 * @dev Bisa dipakai untuk Protocol A maupun Protocol B
 */
contract Strategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    // Underlying asset (USDC)
    IERC20 public immutable usdc;

    // Protocol yang di-target (MockProtocol A atau B)
    IMockProtocol public immutable protocol;

    // Vault address yang authorized untuk call functions ini
    address public vault;

    // ============ Events ============

    event Deposited(uint256 amount, uint256 timestamp);
    event Withdrawn(uint256 amount, uint256 timestamp);
    event Harvested(uint256 earned, uint256 timestamp);
    event VaultSet(address indexed vault);

    // ============ Modifiers ============

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Initialize Strategy
     * @param _usdc Address of USDC token
     * @param _protocol Address of MockProtocol (A atau B)
     */
    constructor(address _usdc, address _protocol) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_protocol != address(0), "Invalid protocol address");

        usdc = IERC20(_usdc);
        protocol = IMockProtocol(_protocol);
    }

    // ============ Main Functions ============

    /**
     * @notice Deposit USDC ke protocol
     * @param amount Jumlah USDC yang akan di-deploy
     * @return success True jika berhasil
     * @dev Hanya vault yang bisa call
     */
    function deposit(uint256 amount)
        external
        override
        onlyVault
        returns (bool success)
    {
        require(amount > 0, "Cannot deposit 0");

        // Transfer USDC from vault to strategy
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Approve protocol to spend USDC
        usdc.safeApprove(address(protocol), amount);

        // Supply to protocol
        bool result = protocol.supply(amount);
        require(result, "Protocol supply failed");

        emit Deposited(amount, block.timestamp);

        return true;
    }

    /**
     * @notice Withdraw USDC dari protocol
     * @param amount Jumlah USDC yang akan di-withdraw
     * @return amountReceived Actual USDC yang diterima
     * @dev Hanya vault yang bisa call
     */
    function withdraw(uint256 amount)
        external
        override
        onlyVault
        returns (uint256 amountReceived)
    {
        require(amount > 0, "Cannot withdraw 0");

        // Get balance before
        uint256 balanceBefore = usdc.balanceOf(address(this));

        // Withdraw from protocol
        uint256 withdrawn = protocol.withdraw(amount);

        // Get balance after
        uint256 balanceAfter = usdc.balanceOf(address(this));
        amountReceived = balanceAfter - balanceBefore;

        // Transfer USDC to vault
        usdc.safeTransfer(msg.sender, amountReceived);

        emit Withdrawn(amountReceived, block.timestamp);

        return amountReceived;
    }

    /**
     * @notice Harvest earned yield dari protocol
     * @return earned Jumlah yield yang di-harvest
     * @dev Withdraw profit saja, principal tetap di protocol
     */
    function harvest() external override onlyVault returns (uint256 earned) {
        // Get current total balance (principal + yield)
        uint256 totalBalance = protocol.balanceOf(address(this));

        // Get principal balance
        uint256 principal = protocol.principalBalanceOf(address(this));

        // Calculate earned yield
        earned = totalBalance > principal ? totalBalance - principal : 0;

        if (earned > 0) {
            // Withdraw only the yield
            uint256 withdrawn = protocol.withdraw(earned);

            // Transfer yield to vault
            usdc.safeTransfer(msg.sender, withdrawn);

            emit Harvested(withdrawn, block.timestamp);

            return withdrawn;
        }

        return 0;
    }

    /**
     * @notice Get total balance di protocol (principal + yield)
     * @return balance Total USDC value
     */
    function balanceOf() external view override returns (uint256 balance) {
        return protocol.balanceOf(address(this));
    }

    /**
     * @notice Emergency withdraw all funds dari protocol
     * @return amount Total USDC yang di-withdraw
     * @dev Only owner bisa call (emergency situations)
     */
    function withdrawAll() external override onlyOwner returns (uint256 amount) {
        uint256 totalBalance = protocol.balanceOf(address(this));

        if (totalBalance > 0) {
            amount = protocol.withdraw(totalBalance);

            // Transfer semua USDC ke vault
            if (vault != address(0)) {
                usdc.safeTransfer(vault, amount);
            } else {
                // Jika vault belum set, kirim ke owner
                usdc.safeTransfer(owner(), amount);
            }

            emit Withdrawn(amount, block.timestamp);
        }

        return amount;
    }

    /**
     * @notice Get underlying asset address
     * @return asset USDC address
     */
    function asset() external view override returns (address) {
        return address(usdc);
    }

    // ============ View Functions ============

    /**
     * @notice Get principal balance (tanpa yield)
     * @return principal Principal amount di protocol
     */
    function principalBalance() external view returns (uint256) {
        return protocol.principalBalanceOf(address(this));
    }

    /**
     * @notice Get current earned yield (belum di-harvest)
     * @return yield Current accrued yield
     */
    function pendingYield() external view returns (uint256) {
        uint256 totalBalance = protocol.balanceOf(address(this));
        uint256 principal = protocol.principalBalanceOf(address(this));
        return totalBalance > principal ? totalBalance - principal : 0;
    }

    /**
     * @notice Get protocol APY
     * @return apy Current APY dari protocol
     */
    function getAPY() external view returns (uint256) {
        return protocol.getAPY();
    }

    // ============ Admin Functions ============

    /**
     * @notice Set vault address yang authorized
     * @param _vault Address of vault contract
     * @dev Only owner bisa set ini (saat deployment)
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault address");
        require(vault == address(0), "Vault already set"); // Can only set once
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @notice Emergency function untuk rescue stuck tokens
     * @param token Address of token to rescue
     * @param amount Amount to rescue
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(usdc), "Cannot rescue USDC");
        IERC20(token).safeTransfer(owner(), amount);
    }
}