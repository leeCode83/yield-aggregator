// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVault.sol";

/**
 * @title Router
 * @notice Entry point untuk semua user interactions dengan StableYield protocol
 * @dev Mengelola batching deposits/withdrawals untuk gas optimization
 */
contract Router is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Enums ============

    enum RiskLevel {
        Conservative,
        Balanced,
        Aggressive
    }

    // ============ State Variables ============

    // USDC stablecoin address
    IERC20 public immutable usdc;

    // Vault addresses per risk level
    mapping(RiskLevel => address) public vaults;

    // Pending deposits: user => RiskLevel => amount
    mapping(address => mapping(RiskLevel => uint256)) public pendingDeposits;

    // Pending withdraws: user => RiskLevel => shares amount
    mapping(address => mapping(RiskLevel => uint256)) public pendingWithdraws;

    // Total pending per risk level untuk batching
    mapping(RiskLevel => uint256) public totalPendingDeposits;
    mapping(RiskLevel => uint256) public totalPendingWithdraws;

    // Batch timing - deposits/withdraws executed setiap X hours
    uint256 public batchInterval = 6 hours;
    mapping(RiskLevel => uint256) public lastBatchTime;

    // Minimum deposit amount (e.g., $10)
    uint256 public minDepositAmount = 10e6; // 10 USDC (6 decimals)

    // ============ Events ============

    event DepositQueued(
        address indexed user,
        RiskLevel indexed riskLevel,
        uint256 amount,
        uint256 nextBatchTime
    );

    event WithdrawQueued(
        address indexed user,
        RiskLevel indexed riskLevel,
        uint256 shares,
        uint256 nextBatchTime
    );

    event BatchExecuted(
        RiskLevel indexed riskLevel,
        uint256 totalDeposits,
        uint256 totalWithdraws,
        uint256 timestamp
    );

    event VaultSet(RiskLevel indexed riskLevel, address vaultAddress);

    event MinDepositAmountUpdated(uint256 newAmount);

    event BatchIntervalUpdated(uint256 newInterval);

    // ============ Constructor ============

    /**
     * @notice Initialize Router contract
     * @param _usdc Address of USDC stablecoin contract
     */
    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        usdc = IERC20(_usdc);
    }

    // ============ User Functions ============

    /**
     * @notice User deposit USDC ke batching queue
     * @param amount Jumlah USDC yang akan di-deposit (6 decimals)
     * @param riskLevel Risk level vault (Conservative/Balanced/Aggressive)
     * @dev USDC akan masuk pending queue sampai executeBatch() dipanggil
     * @dev User harus approve Router untuk spend USDC terlebih dahulu
     */
    function deposit(
        uint256 amount,
        RiskLevel riskLevel
    ) external nonReentrant whenNotPaused {
        require(amount >= minDepositAmount, "Amount below minimum");
        require(vaults[riskLevel] != address(0), "Vault not set");

        // Transfer USDC from user to Router
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        // Add to pending deposits
        pendingDeposits[msg.sender][riskLevel] += amount;
        totalPendingDeposits[riskLevel] += amount;

        // Calculate next batch time
        uint256 nextBatch = lastBatchTime[riskLevel] + batchInterval;

        emit DepositQueued(msg.sender, riskLevel, amount, nextBatch);
    }

    /**
     * @notice User request withdraw shares dari vault
     * @param shares Jumlah vault shares yang akan di-withdraw
     * @param riskLevel Risk level vault yang akan di-withdraw
     * @dev Shares akan masuk pending queue sampai executeBatch() dipanggil
     * @dev User harus memiliki shares di vault tersebut
     */
    function withdraw(
        uint256 shares,
        RiskLevel riskLevel
    ) external nonReentrant whenNotPaused {
        require(shares > 0, "Shares must be > 0");
        require(vaults[riskLevel] != address(0), "Vault not set");

        address vault = vaults[riskLevel];

        // Check user has enough shares
        uint256 userShares = IERC20(vault).balanceOf(msg.sender);
        require(userShares >= shares, "Insufficient shares");

        // Transfer shares from user to Router
        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        // Add to pending withdraws
        pendingWithdraws[msg.sender][riskLevel] += shares;
        totalPendingWithdraws[riskLevel] += shares;

        // Calculate next batch time
        uint256 nextBatch = lastBatchTime[riskLevel] + batchInterval;

        emit WithdrawQueued(msg.sender, riskLevel, shares, nextBatch);
    }

    /**
     * @notice Get user's pending deposit amount untuk risk level tertentu
     * @param user Address of user
     * @param riskLevel Risk level to check
     * @return amount Pending deposit amount dalam USDC
     */
    function getPendingDeposit(
        address user,
        RiskLevel riskLevel
    ) external view returns (uint256) {
        return pendingDeposits[user][riskLevel];
    }

    /**
     * @notice Get user's pending withdraw shares untuk risk level tertentu
     * @param user Address of user
     * @param riskLevel Risk level to check
     * @return shares Pending withdraw shares amount
     */
    function getPendingWithdraw(
        address user,
        RiskLevel riskLevel
    ) external view returns (uint256) {
        return pendingWithdraws[user][riskLevel];
    }

    /**
     * @notice Check kapan next batch akan di-execute untuk risk level tertentu
     * @param riskLevel Risk level to check
     * @return nextBatchTime Timestamp kapan batch bisa di-execute
     */
    function getNextBatchTime(
        RiskLevel riskLevel
    ) external view returns (uint256) {
        return lastBatchTime[riskLevel] + batchInterval;
    }

    /**
     * @notice Check apakah batch ready untuk di-execute
     * @param riskLevel Risk level to check
     * @return ready True jika batch interval sudah lewat
     */
    function isBatchReady(RiskLevel riskLevel) public view returns (bool) {
        return block.timestamp >= lastBatchTime[riskLevel] + batchInterval;
    }

    // ============ Keeper Functions ============

    /**
     * @notice Execute batch deposits untuk risk level tertentu
     * @param riskLevel Risk level vault yang akan diprocess
     * @dev Hanya bisa dipanggil setelah batch interval berlalu
     * @dev Function ini akan dipanggil oleh keeper bot atau Chainlink Automation
     */
    function executeBatchDeposits(
        RiskLevel riskLevel
    ) external nonReentrant whenNotPaused {
        require(isBatchReady(riskLevel), "Batch not ready yet");
        require(totalPendingDeposits[riskLevel] > 0, "No pending deposits");

        address vaultAddress = vaults[riskLevel];
        require(vaultAddress != address(0), "Vault not set");

        uint256 totalAmount = totalPendingDeposits[riskLevel];

        // Approve vault to spend USDC
        usdc.approve(vaultAddress, totalAmount);

        // Call vault's deposit function using interface
        IVault vault = IVault(vaultAddress);
        uint256 sharesMinted = vault.deposit(totalAmount);

        require(sharesMinted > 0, "No shares minted");

        // Reset pending deposits
        totalPendingDeposits[riskLevel] = 0;
        lastBatchTime[riskLevel] = block.timestamp;

        emit BatchExecuted(riskLevel, totalAmount, 0, block.timestamp);
    }

    /**
     * @notice Execute batch withdraws untuk risk level tertentu
     * @param riskLevel Risk level vault yang akan diprocess
     * @dev Hanya bisa dipanggil setelah batch interval berlalu
     */
    function executeBatchWithdraws(
        RiskLevel riskLevel
    ) external nonReentrant whenNotPaused {
        require(isBatchReady(riskLevel), "Batch not ready yet");
        require(totalPendingWithdraws[riskLevel] > 0, "No pending withdraws");

        address vaultAddress = vaults[riskLevel];
        require(vaultAddress != address(0), "Vault not set");

        uint256 totalShares = totalPendingWithdraws[riskLevel];

        // Call vault's redeem function using interface
        IVault vault = IVault(vaultAddress);
        uint256 usdcReceived = vault.redeem(totalShares);

        require(usdcReceived > 0, "No USDC received");

        // USDC will be distributed to users proportionally
        // (Implementation detail: bisa via separate claim function atau auto-transfer)

        // Reset pending withdraws
        totalPendingWithdraws[riskLevel] = 0;
        lastBatchTime[riskLevel] = block.timestamp;

        emit BatchExecuted(riskLevel, 0, usdcReceived, block.timestamp);
    }

    /**
     * @notice Execute both deposits and withdraws dalam satu transaction (gas efficient)
     * @param riskLevel Risk level to process
     */
    function executeBatch(
        RiskLevel riskLevel
    ) external nonReentrant whenNotPaused {
        require(isBatchReady(riskLevel), "Batch not ready yet");

        bool hasDeposits = totalPendingDeposits[riskLevel] > 0;
        bool hasWithdraws = totalPendingWithdraws[riskLevel] > 0;

        require(hasDeposits || hasWithdraws, "No pending transactions");

        if (hasDeposits) {
            this.executeBatchDeposits(riskLevel);
        }

        if (hasWithdraws) {
            this.executeBatchWithdraws(riskLevel);
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Set vault address untuk risk level tertentu
     * @param riskLevel Risk level (Conservative/Balanced/Aggressive)
     * @param vaultAddress Address of vault contract
     * @dev Only owner can call this
     */
    function setVault(
        RiskLevel riskLevel,
        address vaultAddress
    ) external onlyOwner {
        require(vaultAddress != address(0), "Invalid vault address");
        vaults[riskLevel] = vaultAddress;

        // Initialize last batch time
        if (lastBatchTime[riskLevel] == 0) {
            lastBatchTime[riskLevel] = block.timestamp;
        }

        emit VaultSet(riskLevel, vaultAddress);
    }

    /**
     * @notice Update minimum deposit amount
     * @param newAmount New minimum amount dalam USDC (6 decimals)
     */
    function setMinDepositAmount(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Amount must be > 0");
        minDepositAmount = newAmount;
        emit MinDepositAmountUpdated(newAmount);
    }

    /**
     * @notice Update batch interval
     * @param newInterval New interval in seconds
     */
    function setBatchInterval(uint256 newInterval) external onlyOwner {
        require(newInterval >= 1 hours, "Interval too short");
        require(newInterval <= 24 hours, "Interval too long");
        batchInterval = newInterval;
        emit BatchIntervalUpdated(newInterval);
    }

    /**
     * @notice Pause contract (emergency)
     * @dev Stops all deposits and withdraws
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Address of token to rescue
     * @param amount Amount to withdraw
     * @dev Only untuk emergency jika ada token yang stuck
     */
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Preview berapa shares yang akan user terima untuk deposit amount
     * @param amount Jumlah USDC yang akan di-deposit
     * @param riskLevel Risk level vault
     * @return shares Estimasi shares yang akan diterima
     */
    function previewDeposit(
        uint256 amount,
        RiskLevel riskLevel
    ) external view returns (uint256) {
        address vaultAddress = vaults[riskLevel];
        require(vaultAddress != address(0), "Vault not set");

        IVault vault = IVault(vaultAddress);
        return vault.previewDeposit(amount);
    }

    /**
     * @notice Preview berapa USDC yang akan user terima untuk redeem shares
     * @param shares Jumlah shares yang akan di-redeem
     * @param riskLevel Risk level vault
     * @return assets Estimasi USDC yang akan diterima
     */
    function previewWithdraw(
        uint256 shares,
        RiskLevel riskLevel
    ) external view returns (uint256) {
        address vaultAddress = vaults[riskLevel];
        require(vaultAddress != address(0), "Vault not set");

        IVault vault = IVault(vaultAddress);
        return vault.previewRedeem(shares);
    }

    /**
     * @notice Get total value of vault dalam USDC
     * @param riskLevel Risk level vault
     * @return totalValue Total USDC value di vault
     */
    function getVaultTotalValue(
        RiskLevel riskLevel
    ) external view returns (uint256) {
        address vaultAddress = vaults[riskLevel];
        require(vaultAddress != address(0), "Vault not set");

        IVault vault = IVault(vaultAddress);
        return vault.totalAssets();
    }
}
