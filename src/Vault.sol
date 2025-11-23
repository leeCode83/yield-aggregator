// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IVault.sol";

/**
 * @title Vault
 * @notice ERC-4626 compliant vault untuk pooled stablecoin yield farming
 * @dev Base contract untuk Conservative, Balanced, dan Aggressive vaults
 * @dev Hanya perlu adjust allocation percentages untuk setiap risk level
 */
contract Vault is ERC20, IVault, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    // Underlying asset (USDC)
    IERC20 public immutable usdc;

    // Strategy contracts
    IStrategy public aaveStrategy;
    IStrategy public compoundStrategy;

    // Allocation percentages (basis points: 10000 = 100%)
    // Example Conservative: aaveAllocation = 7000 (70%), compoundAllocation = 3000 (30%)
    uint256 public aaveAllocation;
    uint256 public compoundAllocation;

    // Untuk track last harvest time
    uint256 public lastHarvestTime;

    // Minimum time between harvests (prevent spam)
    uint256 public harvestInterval = 1 days;

    // Performance fee (basis points: 1000 = 10%)
    uint256 public performanceFee = 1000; // 10%

    // Fee recipient (treasury)
    address public feeRecipient;

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant USDC_DECIMALS = 6;

    // ============ Events ============

    event Deposited(address indexed user, uint256 assets, uint256 shares);
    event Withdrawn(address indexed user, uint256 assets, uint256 shares);
    event FundsDeployed(uint256 aaveAmount, uint256 compoundAmount);
    event Harvested(uint256 totalEarned, uint256 feeAmount, uint256 timestamp);
    event Rebalanced(uint256 newAaveAllocation, uint256 newCompoundAllocation);
    event StrategyUpdated(address indexed strategy, bool isAave);
    event AllocationUpdated(uint256 aaveAllocation, uint256 compoundAllocation);
    event PerformanceFeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newRecipient);

    // ============ Constructor ============

    /**
     * @notice Initialize Vault
     * @param _name Name of vault share token (e.g., "StableYield Conservative Vault")
     * @param _symbol Symbol of vault share token (e.g., "syCONS")
     * @param _usdc Address of USDC stablecoin
     * @param _aaveAllocation Initial Aave allocation in basis points (e.g., 7000 = 70%)
     * @param _compoundAllocation Initial Compound allocation in basis points (e.g., 3000 = 30%)
     * @param _feeRecipient Address to receive performance fees
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdc,
        uint256 _aaveAllocation,
        uint256 _compoundAllocation,
        address _feeRecipient
    ) Ownable(msg.sender) ERC20(_name, _symbol) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(
            _aaveAllocation + _compoundAllocation == BASIS_POINTS,
            "Allocations must sum to 100%"
        );

        usdc = IERC20(_usdc);
        aaveAllocation = _aaveAllocation;
        compoundAllocation = _compoundAllocation;
        feeRecipient = _feeRecipient;
        lastHarvestTime = block.timestamp;
    }

    // ============ Main User Functions ============

    /**
     * @notice Deposit USDC dan mint shares (ERC-4626 standard)
     * @param assets Jumlah USDC yang akan di-deposit
     * @return shares Jumlah shares yang di-mint
     * @dev Dipanggil oleh Router saat executeBatch()
     */
    function deposit(uint256 assets)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        require(assets > 0, "Cannot deposit 0");

        // Calculate shares to mint
        shares = previewDeposit(assets);
        require(shares > 0, "Invalid share amount");

        // Transfer USDC from caller (Router) to vault
        usdc.safeTransferFrom(msg.sender, address(this), assets);

        // Mint shares to caller
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, assets, shares);

        // Auto-deploy funds ke strategies jika sudah set
        if (
            address(aaveStrategy) != address(0) &&
            address(compoundStrategy) != address(0)
        ) {
            _deployToStrategies();
        }

        return shares;
    }

    /**
     * @notice Redeem shares untuk withdraw USDC (ERC-4626 standard)
     * @param shares Jumlah shares yang akan di-burn
     * @return assets Jumlah USDC yang dikembalikan
     * @dev Dipanggil oleh Router saat executeBatch()
     */
    function redeem(uint256 shares)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        require(shares > 0, "Cannot redeem 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");

        // Calculate USDC amount to return
        assets = previewRedeem(shares);
        require(assets > 0, "Invalid asset amount");

        // Burn shares
        _burn(msg.sender, shares);

        // Withdraw from strategies if needed
        uint256 vaultBalance = usdc.balanceOf(address(this));
        if (vaultBalance < assets) {
            _withdrawFromStrategies(assets - vaultBalance);
        }

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, assets);

        emit Withdrawn(msg.sender, assets, shares);

        return assets;
    }

    // ============ Internal Strategy Management ============

    /**
     * @notice Deploy USDC dari vault ke strategies sesuai allocation
     * @dev Internal function called after deposits
     */
    function _deployToStrategies() internal {
        uint256 availableBalance = usdc.balanceOf(address(this));
        require(availableBalance > 0, "No balance to deploy");

        // Calculate amounts per strategy
        uint256 aaveAmount = (availableBalance * aaveAllocation) / BASIS_POINTS;
        uint256 compoundAmount = (availableBalance * compoundAllocation) /
            BASIS_POINTS;

        // Deploy to Aave
        if (aaveAmount > 0) {
            usdc.approve(address(aaveStrategy), aaveAmount);
            aaveStrategy.deposit(aaveAmount);
        }

        // Deploy to Compound
        if (compoundAmount > 0) {
            usdc.approve(address(compoundStrategy), compoundAmount);
            compoundStrategy.deposit(compoundAmount);
        }

        emit FundsDeployed(aaveAmount, compoundAmount);
    }

    /**
     * @notice Withdraw USDC dari strategies secara proporsional
     * @param amount Total amount yang perlu di-withdraw
     */
    function _withdrawFromStrategies(uint256 amount) internal {
        // Withdraw proportionally dari strategies
        uint256 aaveAmount = (amount * aaveAllocation) / BASIS_POINTS;
        uint256 compoundAmount = (amount * compoundAllocation) / BASIS_POINTS;

        // Withdraw dari Aave
        if (aaveAmount > 0 && address(aaveStrategy) != address(0)) {
            aaveStrategy.withdraw(aaveAmount);
        }

        // Withdraw dari Compound
        if (compoundAmount > 0 && address(compoundStrategy) != address(0)) {
            compoundStrategy.withdraw(compoundAmount);
        }
    }

    // ============ Harvest & Compound Functions ============

    /**
     * @notice Harvest earned yield dari strategies dan auto-compound
     * @dev Dapat dipanggil oleh siapa saja, tapi ada interval minimum
     * @return totalEarned Total yield yang di-harvest (sebelum fees)
     */
    function compound()
        external
        nonReentrant
        whenNotPaused
        returns (uint256 totalEarned)
    {
        require(
            block.timestamp >= lastHarvestTime + harvestInterval,
            "Too soon to harvest"
        );

        uint256 balanceBefore = usdc.balanceOf(address(this));

        // Harvest dari Aave
        uint256 aaveEarned = 0;
        if (address(aaveStrategy) != address(0)) {
            aaveEarned = aaveStrategy.harvest();
        }

        // Harvest dari Compound
        uint256 compoundEarned = 0;
        if (address(compoundStrategy) != address(0)) {
            compoundEarned = compoundStrategy.harvest();
        }

        uint256 balanceAfter = usdc.balanceOf(address(this));
        totalEarned = balanceAfter - balanceBefore;

        if (totalEarned > 0) {
            // Take performance fee
            uint256 feeAmount = (totalEarned * performanceFee) / BASIS_POINTS;
            if (feeAmount > 0) {
                usdc.safeTransfer(feeRecipient, feeAmount);
            }

            // Reinvest remaining yield
            uint256 reinvestAmount = totalEarned - feeAmount;
            if (reinvestAmount > 0) {
                _deployToStrategies();
            }

            emit Harvested(totalEarned, feeAmount, block.timestamp);
        }

        lastHarvestTime = block.timestamp;

        return totalEarned;
    }

    // ============ Rebalancing Functions ============

    /**
     * @notice Rebalance allocation antara Aave dan Compound
     * @param newAaveAllocation New allocation untuk Aave (basis points)
     * @param newCompoundAllocation New allocation untuk Compound (basis points)
     * @dev Only owner (atau keeper) yang bisa rebalance
     */
    function rebalance(
        uint256 newAaveAllocation,
        uint256 newCompoundAllocation
    ) external onlyOwner nonReentrant {
        require(
            newAaveAllocation + newCompoundAllocation == BASIS_POINTS,
            "Allocations must sum to 100%"
        );

        // Harvest dulu sebelum rebalance
        if (block.timestamp >= lastHarvestTime + harvestInterval) {
            this.compound();
        }

        // Calculate current balances
        uint256 aaveBalance = address(aaveStrategy) != address(0)
            ? aaveStrategy.balanceOf()
            : 0;
        uint256 compoundBalance = address(compoundStrategy) != address(0)
            ? compoundStrategy.balanceOf()
            : 0;
        uint256 totalInStrategies = aaveBalance + compoundBalance;

        // Calculate target balances
        uint256 targetAaveBalance = (totalInStrategies * newAaveAllocation) /
            BASIS_POINTS;
        uint256 targetCompoundBalance = (totalInStrategies *
            newCompoundAllocation) / BASIS_POINTS;

        // Rebalance: withdraw from over-allocated, deposit to under-allocated
        if (aaveBalance > targetAaveBalance) {
            // Withdraw excess from Aave
            uint256 excessAave = aaveBalance - targetAaveBalance;
            aaveStrategy.withdraw(excessAave);

            // Deposit to Compound
            usdc.approve(address(compoundStrategy), excessAave);
            compoundStrategy.deposit(excessAave);
        } else if (compoundBalance > targetCompoundBalance) {
            // Withdraw excess from Compound
            uint256 excessCompound = compoundBalance - targetCompoundBalance;
            compoundStrategy.withdraw(excessCompound);

            // Deposit to Aave
            usdc.approve(address(aaveStrategy), excessCompound);
            aaveStrategy.deposit(excessCompound);
        }

        // Update allocations
        aaveAllocation = newAaveAllocation;
        compoundAllocation = newCompoundAllocation;

        emit Rebalanced(newAaveAllocation, newCompoundAllocation);
    }

    // ============ View Functions (ERC-4626) ============

    /**
     * @notice Get total assets (USDC) dalam vault
     * @return Total USDC di vault + deployed di strategies
     */
    function totalAssets() public view override returns (uint256) {
        uint256 vaultBalance = usdc.balanceOf(address(this));

        uint256 aaveBalance = address(aaveStrategy) != address(0)
            ? aaveStrategy.balanceOf()
            : 0;

        uint256 compoundBalance = address(compoundStrategy) != address(0)
            ? compoundStrategy.balanceOf()
            : 0;

        return vaultBalance + aaveBalance + compoundBalance;
    }

    /**
     * @notice Preview shares yang akan diterima untuk deposit amount
     * @param assets Jumlah USDC yang akan di-deposit
     * @return shares Estimasi shares yang akan di-mint
     */
    function previewDeposit(uint256 assets)
        public
        view
        override
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();

        // First deposit: 1:1 ratio
        if (supply == 0) {
            return assets;
        }

        // Subsequent deposits: proportional to current share price
        return (assets * supply) / totalAssets();
    }

    /**
     * @notice Preview assets yang akan diterima untuk redeem shares
     * @param shares Jumlah shares yang akan di-burn
     * @return assets Estimasi USDC yang akan diterima
     */
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256 assets)
    {
        uint256 supply = totalSupply();
        if (supply == 0) return 0;

        return (shares * totalAssets()) / supply;
    }

    /**
     * @notice Get current share price dalam USDC
     * @return price Price per share (scaled to USDC decimals)
     */
    function sharePrice() external view returns (uint256 price) {
        uint256 supply = totalSupply();
        if (supply == 0) return 10**USDC_DECIMALS; // 1 USDC

        return (totalAssets() * 10**USDC_DECIMALS) / supply;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set Aave strategy contract
     * @param _aaveStrategy Address of AaveStrategy contract
     */
    function setAaveStrategy(address _aaveStrategy) external onlyOwner {
        require(_aaveStrategy != address(0), "Invalid strategy address");
        aaveStrategy = IStrategy(_aaveStrategy);
        emit StrategyUpdated(_aaveStrategy, true);
    }

    /**
     * @notice Set Compound strategy contract
     * @param _compoundStrategy Address of CompoundStrategy contract
     */
    function setCompoundStrategy(address _compoundStrategy) external onlyOwner {
        require(_compoundStrategy != address(0), "Invalid strategy address");
        compoundStrategy = IStrategy(_compoundStrategy);
        emit StrategyUpdated(_compoundStrategy, false);
    }

    /**
     * @notice Update allocation percentages (tanpa rebalance actual funds)
     * @param _aaveAllocation New Aave allocation (basis points)
     * @param _compoundAllocation New Compound allocation (basis points)
     */
    function setAllocations(
        uint256 _aaveAllocation,
        uint256 _compoundAllocation
    ) external onlyOwner {
        require(
            _aaveAllocation + _compoundAllocation == BASIS_POINTS,
            "Allocations must sum to 100%"
        );
        aaveAllocation = _aaveAllocation;
        compoundAllocation = _compoundAllocation;
        emit AllocationUpdated(_aaveAllocation, _compoundAllocation);
    }

    /**
     * @notice Update performance fee
     * @param _performanceFee New fee in basis points (max 20% = 2000)
     */
    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        require(_performanceFee <= 2000, "Fee too high (max 20%)");
        performanceFee = _performanceFee;
        emit PerformanceFeeUpdated(_performanceFee);
    }

    /**
     * @notice Update fee recipient address
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid address");
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @notice Update harvest interval
     * @param _harvestInterval New interval in seconds
     */
    function setHarvestInterval(uint256 _harvestInterval) external onlyOwner {
        require(_harvestInterval >= 6 hours, "Interval too short");
        harvestInterval = _harvestInterval;
    }

    /**
     * @notice Pause vault (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdraw all funds dari strategies
     * @dev Only untuk emergency situations
     */
    function emergencyWithdrawAll() external onlyOwner {
        if (address(aaveStrategy) != address(0)) {
            aaveStrategy.withdrawAll();
        }
        if (address(compoundStrategy) != address(0)) {
            compoundStrategy.withdrawAll();
        }
    }
}