# Brief Proyek Growish - Stablecoin Yield Aggregator

## 1. Gambaran Umum Proyek

Growish adalah platform yield aggregator yang fokus pada stablecoin (USDC) dengan tujuan menyelesaikan tiga masalah utama di DeFi:

1. **Gas fees yang tinggi** - Diselesaikan dengan batching deposits/withdrawals
2. **Kompleksitas untuk pemula** - Interface sederhana dengan 3 pilihan risk level
3. **Lack of transparency** - Real-time breakdown alokasi dana dan strategi

### Konsep Dasar:

**Pooled Vault System:**
- User dengan risk level yang sama menaruh dana dalam 1 vault bersama
- Dana vault di-deploy ke multiple protokol DeFi (untuk demo: 2 mock protocols)
- User dapat "vault shares" sebagai bukti kepemilikan (seperti receipt token)
- Yield otomatis di-compound dan dibagikan proporsional sesuai shares

**3 Risk Levels:**
- **Conservative Vault**: 70% Protocol A (APY rendah) + 30% Protocol B (APY tinggi)
- **Balanced Vault**: 50% Protocol A + 50% Protocol B
- **Aggressive Vault**: 30% Protocol A + 70% Protocol B

---

## 2. Arsitektur Smart Contract

### Total Contracts: 5 Unique Contracts

```
User Wallet
    ↓
Router (entry point, batching)
    ↓
Vault (3 instances: Conservative/Balanced/Aggressive)
    ↓           ↓
Strategy A   Strategy B
    ↓           ↓
Protocol A   Protocol B (Mock DeFi protocols)
```

---

## 3. Smart Contract Details

### 3.1 MockUSDC.sol

**Peran:**
Token stablecoin ERC-20 untuk testing. Merepresentasikan USDC dalam environment testnet.

**Functions:**
- `mint(address to, uint256 amount)` - Mint USDC ke address tertentu untuk testing
- `burn(uint256 amount)` - Burn USDC
- `approve(address spender, uint256 amount)` - Standard ERC-20 approve
- `transfer(address to, uint256 amount)` - Standard ERC-20 transfer
- `transferFrom(address from, address to, uint256 amount)` - Standard ERC-20 transferFrom
- `balanceOf(address account)` - Check balance USDC
- `totalSupply()` - Total USDC yang beredar

**Interaksi dengan Contract Lain:**
- User → MockUSDC: Mint USDC untuk testing
- User → MockUSDC: Approve Router untuk spend USDC
- Router → MockUSDC: Transfer USDC dari user ke Router
- Router → MockUSDC: Transfer USDC dari Router ke Vault
- Vault → MockUSDC: Approve Strategy untuk spend USDC
- Strategy → MockUSDC: Approve MockProtocol untuk spend USDC
- MockProtocol → MockUSDC: Transfer USDC untuk withdraw

**Data yang Disimpan:**
- Balance setiap address
- Allowances (siapa boleh spend berapa dari account siapa)

---

### 3.2 MockProtocol.sol

**Peran:**
Simulate protokol DeFi lending (representasi Aave atau Compound). Terima USDC deposit, mint receipt token, simulate yield accrual, handle withdraw.

**Functions:**
- `constructor(string name, string symbol, uint256 apyBasisPoints)` - Initialize protocol dengan nama, symbol receipt token, dan APY
- `supply(address asset, uint256 amount, address onBehalfOf)` - Terima USDC deposit, mint receipt token ke depositor
- `withdraw(address asset, uint256 amount, address to)` - Burn receipt token, kembalikan USDC + yield
- `balanceOf(address account)` - Get balance receipt token (auto-increase dengan yield)
- `getSuppliedBalance(address account)` - Get USDC value yang di-supply termasuk yield
- `accrueInterest()` - Trigger perhitungan interest/yield (simulate time-based accrual)
- `getTotalSupply()` - Total USDC yang di-supply ke protocol
- `getAPY()` - Get current APY protocol
- `setAPY(uint256 newAPY)` - Owner bisa adjust APY untuk simulate market changes

**Interaksi dengan Contract Lain:**
- Strategy → MockProtocol: Call supply() untuk deposit USDC
- Strategy → MockProtocol: Call withdraw() untuk ambil USDC + yield
- Strategy → MockProtocol: Call balanceOf() untuk check balance
- MockProtocol → MockUSDC: Transfer USDC dari Strategy saat supply
- MockProtocol → MockUSDC: Transfer USDC ke Strategy saat withdraw

**Data yang Disimpan:**
- Mapping: user address → supplied USDC amount
- Mapping: user address → timestamp last interaction (untuk calculate yield)
- APY rate (basis points)
- Total USDC supplied ke protocol
- Receipt token balances (ERC-20)

**Simulasi Yield:**
```
Yield = suppliedAmount × APY × timeElapsed / 365 days
```

---

### 3.3 Strategy.sol

**Peran:**
Jembatan antara Vault dan MockProtocol. Handle interaksi teknis dengan protocol (deposit, withdraw, harvest yield). Menyimpan receipt tokens dari protocol sebagai bukti kepemilikan.

**Functions:**
- `constructor(address _usdc, address _protocol)` - Initialize strategy dengan USDC address dan protocol target
- `deposit(uint256 amount)` - Terima USDC dari Vault, deploy ke MockProtocol
- `withdraw(uint256 amount)` - Ambil USDC dari MockProtocol, kirim ke Vault
- `harvest()` - Claim earned interest dari protocol, kirim ke Vault
- `balanceOf()` - Get total USDC value di protocol (principal + yield)
- `withdrawAll()` - Emergency function, withdraw semua dana dari protocol
- `asset()` - Return address USDC token

**Interaksi dengan Contract Lain:**
- Vault → Strategy: Call deposit() untuk deploy dana
- Vault → Strategy: Call withdraw() untuk ambil dana kembali
- Vault → Strategy: Call harvest() saat compound
- Vault → Strategy: Call balanceOf() untuk calculate total assets
- Strategy → MockUSDC: Transfer USDC dari Vault ke Strategy
- Strategy → MockUSDC: Approve MockProtocol untuk spend USDC
- Strategy → MockProtocol: Call supply() untuk deposit
- Strategy → MockProtocol: Call withdraw() untuk redeem
- Strategy → MockProtocol: Call balanceOf() untuk check balance

**Data yang Disimpan:**
- USDC token address
- MockProtocol address
- Receipt token balance (disimpan di MockProtocol, Strategy hanya holder)

**Flow Deposit:**
```
1. Vault transfer USDC ke Strategy
2. Strategy approve MockProtocol
3. Strategy call protocol.supply()
4. Protocol ambil USDC, kasih receipt token ke Strategy
5. Strategy sekarang hold receipt token
```

**Flow Withdraw:**
```
1. Vault call strategy.withdraw()
2. Strategy call protocol.withdraw()
3. Protocol burn receipt token, return USDC ke Strategy
4. Strategy transfer USDC ke Vault
```

---

### 3.4 Vault.sol

**Peran:**
Pool dana dari multiple users dengan risk level yang sama. Mint shares (ERC-20) sebagai bukti kepemilikan. Deploy dana ke strategies sesuai allocation. Auto-compound yield. Handle rebalancing.

**Functions:**

**Core Functions (ERC-4626):**
- `constructor(string name, string symbol, address usdc, uint256 aaveAlloc, uint256 compoundAlloc, address feeRecipient)` - Initialize vault dengan nama shares, allocation, dan fee recipient
- `deposit(uint256 assets)` - Terima USDC dari Router, mint shares ke depositor, auto-deploy ke strategies
- `redeem(uint256 shares)` - Burn shares, kembalikan USDC ke user, withdraw dari strategies jika perlu
- `totalAssets()` - Calculate total USDC di vault + di semua strategies
- `previewDeposit(uint256 assets)` - Preview berapa shares untuk deposit amount tertentu
- `previewRedeem(uint256 shares)` - Preview berapa USDC untuk redeem shares tertentu
- `sharePrice()` - Get harga per share dalam USDC

**Strategy Management:**
- `_deployToStrategies()` - Internal function deploy USDC ke strategies sesuai allocation (e.g., 70% Strategy A, 30% Strategy B)
- `_withdrawFromStrategies(uint256 amount)` - Internal function withdraw USDC dari strategies secara proporsional
- `compound()` - Harvest yield dari semua strategies, potong performance fee, reinvest sisanya
- `rebalance(uint256 newAaveAlloc, uint256 newCompoundAlloc)` - Adjust allocation antara strategies (withdraw dari over-allocated, deposit ke under-allocated)

**Admin Functions:**
- `setAaveStrategy(address strategy)` - Set Strategy A address
- `setCompoundStrategy(address strategy)` - Set Strategy B address
- `setAllocations(uint256 aave, uint256 compound)` - Update allocation percentages
- `setPerformanceFee(uint256 fee)` - Update performance fee (default 10%)
- `setFeeRecipient(address recipient)` - Update fee recipient address
- `setHarvestInterval(uint256 interval)` - Update minimum interval between harvests
- `pause() / unpause()` - Emergency pause/unpause
- `emergencyWithdrawAll()` - Emergency withdraw dari semua strategies

**Interaksi dengan Contract Lain:**
- Router → Vault: Call deposit() saat executeBatch deposits
- Router → Vault: Call redeem() saat executeBatch withdraws
- User → Vault: Check balanceOf() untuk lihat shares
- Vault → MockUSDC: Transfer USDC dari Router
- Vault → MockUSDC: Approve Strategies untuk spend USDC
- Vault → Strategy A: Call deposit/withdraw/harvest/balanceOf
- Vault → Strategy B: Call deposit/withdraw/harvest/balanceOf

**Data yang Disimpan:**
- USDC token address
- Strategy A address
- Strategy B address
- Allocation percentages (basis points: 7000 = 70%)
- Performance fee (basis points)
- Fee recipient address
- Last harvest timestamp
- Harvest interval
- Shares balance per user (ERC-20)
- Total shares supply

**Share Calculation:**
```
First deposit: shares = assets (1:1)
Subsequent: shares = (assets × totalSupply) / totalAssets

Contoh:
- Vault punya 10,000 USDC total assets
- Total shares: 10,000 shares
- User deposit 1,000 USDC
- Shares minted: (1,000 × 10,000) / 10,000 = 1,000 shares

Setelah yield:
- Vault punya 11,000 USDC total assets
- Total shares: masih 10,000 shares
- Share price: 11,000 / 10,000 = 1.1 USDC per share
- User A (1,000 shares) value: 1,100 USDC (profit otomatis!)
```

---

### 3.5 Router.sol

**Peran:**
Entry point untuk semua user interactions. Mengelola batching deposits dan withdrawals untuk mengoptimalkan gas fees. Route deposits/withdrawals ke vault yang sesuai berdasarkan risk level.

**Functions:**

**User Functions:**
- `deposit(uint256 amount, RiskLevel risk)` - User deposit USDC, masuk pending queue
- `withdraw(uint256 shares, RiskLevel risk)` - User request withdraw shares, masuk pending queue
- `getPendingDeposit(address user, RiskLevel risk)` - Check pending deposit amount
- `getPendingWithdraw(address user, RiskLevel risk)` - Check pending withdraw shares
- `getNextBatchTime(RiskLevel risk)` - Check kapan batch berikutnya diproses
- `isBatchReady(RiskLevel risk)` - Check apakah batch sudah ready untuk execute

**Keeper Functions (dipanggil bot/automation):**
- `executeBatchDeposits(RiskLevel risk)` - Process semua pending deposits, kirim ke vault
- `executeBatchWithdraws(RiskLevel risk)` - Process semua pending withdraws dari vault
- `executeBatch(RiskLevel risk)` - Execute deposits dan withdraws sekaligus (gas efficient)

**Admin Functions:**
- `setVault(RiskLevel risk, address vault)` - Set vault address untuk risk level tertentu
- `setMinDepositAmount(uint256 amount)` - Set minimum deposit (default $10)
- `setBatchInterval(uint256 interval)` - Set batch interval (default 6 hours)
- `pause() / unpause()` - Emergency pause
- `emergencyWithdraw(address token, uint256 amount)` - Rescue stuck tokens

**Interaksi dengan Contract Lain:**
- User → Router: Call deposit() atau withdraw()
- Router → MockUSDC: TransferFrom user saat deposit
- Router → MockUSDC: Transfer ke Vault saat executeBatch
- Router → Vault (Conservative): Call deposit/redeem
- Router → Vault (Balanced): Call deposit/redeem
- Router → Vault (Aggressive): Call deposit/redeem
- Keeper/Bot → Router: Call executeBatch functions

**Data yang Disimpan:**
- USDC address
- Mapping: RiskLevel → Vault address
- Mapping: user → RiskLevel → pending deposit amount
- Mapping: user → RiskLevel → pending withdraw shares
- Mapping: RiskLevel → total pending deposits
- Mapping: RiskLevel → total pending withdraws
- Mapping: RiskLevel → last batch timestamp
- Batch interval (default 6 hours)
- Minimum deposit amount

**Batching Logic:**
```
Scenario tanpa batching:
- User A deposit → 2 tx (Vault → Strategy A, Vault → Strategy B)
- User B deposit → 2 tx (Vault → Strategy A, Vault → Strategy B)
Total: 4 transactions

Scenario dengan batching:
- User A deposit → masuk queue
- User B deposit → masuk queue
- executeBatch() → 2 tx total untuk A+B (Vault → Strategy A, Vault → Strategy B)
Total: 2 transactions (50% gas saving!)
```

---

## 4. Flow End-to-End

### 4.1 User Deposit Flow

```
1. User call: mockUSDC.approve(Router, 1000 USDC)
2. User call: router.deposit(1000, Conservative)
   - Router transfer 1000 USDC dari User ke Router
   - Add ke pendingDeposits[user][Conservative] = 1000
   - totalPendingDeposits[Conservative] += 1000
   
3. [Wait 6 hours untuk batch atau bisa immediate untuk demo]

4. Keeper call: router.executeBatchDeposits(Conservative)
   - Router approve Vault untuk spend USDC
   - Router call conservativeVault.deposit(totalPendingAmount)
   
5. Di Vault:
   - Calculate shares untuk Router
   - Mint shares ke Router
   - Vault call _deployToStrategies()
   
6. Di _deployToStrategies():
   - Calculate: 70% → Strategy A, 30% → Strategy B
   - Vault approve Strategy A untuk 700 USDC
   - Vault call strategyA.deposit(700)
   - Vault approve Strategy B untuk 300 USDC
   - Vault call strategyB.deposit(300)
   
7. Di Strategy A:
   - Strategy approve MockProtocol A untuk 700 USDC
   - Strategy call protocolA.supply(USDC, 700, strategyA)
   - Protocol A mint receipt token ke Strategy A
   
8. Di Strategy B:
   - Strategy approve MockProtocol B untuk 300 USDC
   - Strategy call protocolB.supply(USDC, 300, strategyB)
   - Protocol B mint receipt token ke Strategy B

Result:
- User dapat vault shares
- USDC deployed ke 2 protocols
- Mulai earning yield
```

### 4.2 Auto-Compound Flow

```
1. Keeper call: vault.compound()

2. Vault check: harvestInterval sudah lewat?

3. Vault call: strategyA.harvest()
   - Strategy call protocolA.withdraw(earned interest only)
   - Protocol A return USDC interest ke Strategy
   - Strategy transfer USDC ke Vault
   - Return amount earned

4. Vault call: strategyB.harvest()
   - Strategy call protocolB.withdraw(earned interest only)
   - Protocol B return USDC interest ke Strategy
   - Strategy transfer USDC ke Vault
   - Return amount earned

5. Vault calculate:
   - totalEarned = earnedA + earnedB (misal 15 USDC)
   - performanceFee = 15 × 10% = 1.5 USDC
   - Vault transfer 1.5 USDC ke feeRecipient
   - reinvestAmount = 13.5 USDC

6. Vault call: _deployToStrategies() dengan 13.5 USDC
   - Deploy lagi ke strategies sesuai allocation

Result:
- Yield claimed dan reinvested
- Share price naik (dari 1.0 → 1.0013 USDC per share)
- User profit otomatis tanpa perlu claim manual
```

### 4.3 User Withdraw Flow

```
1. User call: vault.approve(Router, shares amount)
2. User call: router.withdraw(1000 shares, Conservative)
   - Router transfer shares dari User ke Router
   - Add ke pendingWithdraws[user][Conservative] = 1000
   
3. [Wait batch interval]

4. Keeper call: router.executeBatchWithdraws(Conservative)
   - Router call conservativeVault.redeem(totalPendingShares)
   
5. Di Vault:
   - Calculate USDC amount = shares × sharePrice
   - Burn shares
   - Check vault USDC balance
   - If insufficient: call _withdrawFromStrategies(neededAmount)
   
6. Di _withdrawFromStrategies():
   - Calculate proportional amounts (70% dari A, 30% dari B)
   - Call strategyA.withdraw(700)
   - Call strategyB.withdraw(300)
   
7. Di Strategy A:
   - Call protocolA.withdraw(USDC, 700, strategyA)
   - Protocol burn receipt token
   - Protocol transfer USDC ke Strategy
   - Strategy transfer USDC ke Vault
   
8. Di Strategy B:
   - Call protocolB.withdraw(USDC, 300, strategyB)
   - Protocol burn receipt token
   - Protocol transfer USDC ke Strategy
   - Strategy transfer USDC ke Vault

9. Vault transfer USDC ke Router
10. Router transfer USDC ke User

Result:
- User receive USDC (original + profit)
- Shares burned
- Allocation di vault tetap balanced
```

### 4.4 Rebalancing Flow

```
Scenario: APY Protocol B naik drastis, owner mau rebalance dari 70-30 ke 50-50

1. Owner call: vault.rebalance(5000, 5000)
   - newAaveAllocation = 5000 (50%)
   - newCompoundAllocation = 5000 (50%)

2. Vault harvest dulu (auto-compound sebelum rebalance)

3. Vault calculate current balances:
   - strategyA.balanceOf() = 7,000 USDC
   - strategyB.balanceOf() = 3,000 USDC
   - total = 10,000 USDC

4. Calculate target balances:
   - targetA = 10,000 × 50% = 5,000 USDC
   - targetB = 10,000 × 50% = 5,000 USDC

5. Execute rebalancing:
   - Strategy A over-allocated: 7,000 - 5,000 = 2,000 USDC excess
   - Vault call strategyA.withdraw(2,000)
   - Strategy A return 2,000 USDC ke Vault
   
   - Strategy B under-allocated: need 5,000 - 3,000 = 2,000 USDC
   - Vault approve Strategy B untuk 2,000 USDC
   - Vault call strategyB.deposit(2,000)

6. Update allocations:
   - aaveAllocation = 5000
   - compoundAllocation = 5000

Result:
- Allocation adjusted dari 70-30 ke 50-50
- Total assets tetap sama
- Optimized untuk maximize yield
```

---

## 5. Gas Optimization melalui Batching

### Without Batching:
```
User A deposit 1000 USDC:
- Router → Vault: deposit()
- Vault → Strategy A: deposit(700)
- Vault → Strategy B: deposit(300)
Total: 3 transactions × gas price

User B deposit 2000 USDC:
- Router → Vault: deposit()
- Vault → Strategy A: deposit(1400)
- Vault → Strategy B: deposit(600)
Total: 3 transactions × gas price

Grand Total: 6 transactions
```

### With Batching:
```
User A deposit 1000 USDC → pending queue
User B deposit 2000 USDC → pending queue

executeBatchDeposits():
- Router → Vault: deposit(3000 total)
- Vault → Strategy A: deposit(2100) [combined 700+1400]
- Vault → Strategy B: deposit(900) [combined 300+600]
Total: 3 transactions × gas price

Grand Total: 3 transactions (50% gas saving!)
```

---

## 6. Security Features

### Access Control:
- Owner-only functions: setStrategy, rebalance, setFee, pause
- Keeper-only: executeBatch (dalam production pakai Chainlink Automation)
- User functions: deposit, withdraw (siapa saja)

### Reentrancy Protection:
- Semua external functions yang transfer funds pakai `nonReentrant` modifier
- Checks-Effects-Interactions pattern

### Pause Mechanism:
- Emergency pause untuk stop deposits/withdraws
- Owner bisa pause saat ada issue

### Validations:
- Minimum deposit amount
- Allocation must sum to 100%
- Performance fee max 20%
- Harvest interval minimum 6 hours (prevent spam)

---

## 7. Testing Scenarios untuk Demo

### Scenario 1: Basic Deposit & Withdraw
```
1. User mint 10,000 USDC
2. Approve Router
3. Deposit 1,000 USDC ke Conservative vault
4. executeBatch()
5. Check vault shares balance
6. Wait atau manual trigger yield accrual
7. Check share price increase
8. Withdraw semua shares
9. Verify USDC received > 1,000 (profit!)
```

### Scenario 2: Multiple Users & Batching
```
1. User A deposit 1,000 USDC Conservative
2. User B deposit 2,000 USDC Conservative
3. User C deposit 500 USDC Balanced
4. executeBatch untuk Conservative (A+B combined)
5. executeBatch untuk Balanced (C)
6. Verify semua dapat shares proporsional
```

### Scenario 3: Yield Accrual & Compound
```
1. Deposit 10,000 USDC
2. Manual trigger protocolA.accrueInterest()
3. Manual trigger protocolB.accrueInterest()
4. Call vault.compound()
5. Verify share price increased
6. Verify fee recipient dapat performance fee
```

### Scenario 4: Rebalancing
```
1. Initial allocation: 70-30
2. Change Protocol B APY dari 10% → 20%
3. Call vault.rebalance(5000, 5000) → shift ke 50-50
4. Verify funds redistributed correctly
5. Verify total assets unchanged
```

### Scenario 5: Emergency Scenarios
```
1. Test pause functionality
2. Test emergency withdraw
3. Test recovery dari paused state
```

---

## 8. Frontend Integration Points

### Data yang Perlu Ditampilkan:

**Dashboard:**
- User total balance (USDC value dari shares)
- User shares balance per vault
- Share price per vault
- Total earnings
- Active positions (per vault)
- Pending deposits/withdraws
- Next batch time

**Staking Page:**
- Available USDC balance
- Risk level options dengan allocation breakdown
- APY estimates per vault
- Preview: deposit X USDC → get Y shares
- Projected earnings calculator

### Smart Contract Calls dari Frontend:

**Read Calls (view functions):**
```javascript
// Check balances
await mockUSDC.balanceOf(userAddress);
await vault.balanceOf(userAddress);
await vault.sharePrice();
await vault.totalAssets();

// Check pending
await router.getPendingDeposit(userAddress, riskLevel);
await router.getNextBatchTime(riskLevel);

// Preview
await vault.previewDeposit(amount);
await vault.previewRedeem(shares);
```

**Write Calls (transactions):**
```javascript
// Approve & Deposit
await mockUSDC.approve(routerAddress, amount);
await router.deposit(amount, riskLevel);

// Withdraw
await vault.approve(routerAddress, shares);
await router.withdraw(shares, riskLevel);

// Keeper actions (untuk demo bisa manual trigger)
await router.executeBatch(riskLevel);
await vault.compound();
```

---

## 9. Deployment Order

```
1. Deploy MockUSDC
2. Deploy MockProtocol A ("Mock Aave", "mAAVE", 800) // 8% APY
3. Deploy MockProtocol B ("Mock Compound", "mCOMP", 1000) // 10% APY
4. Deploy Strategy A (usdc, protocolA)
5. Deploy Strategy B (usdc, protocolB)
6. Deploy ConservativeVault (usdc, 7000, 3000, feeRecipient)
7. Deploy BalancedVault (usdc, 5000, 5000, feeRecipient)
8. Deploy AggressiveVault (usdc, 3000, 7000, feeRecipient)
9. Deploy Router (usdc)

Setup:
10. conservativeVault.setAaveStrategy(strategyA)
11. conservativeVault.setCompoundStrategy(strategyB)
12. balancedVault.setAaveStrategy(strategyA)
13. balancedVault.setCompoundStrategy(strategyB)
14. aggressiveVault.setAaveStrategy(strategyA)
15. aggressiveVault.setCompoundStrategy(strategyB)
16. router.setVault(Conservative, conservativeVault)
17. router.setVault(Balanced, balancedVault)
18. router.setVault(Aggressive, aggressiveVault)

Testing:
19. mockUSDC.mint(testAddress, 100000e6) // Mint test USDC
```

---

## 10. Key Concepts untuk Dipahami AI Agent

### Shares vs Assets:
- **Assets** = USDC (underlying token)
- **Shares** = Vault tokens (receipt/bukti kepemilikan)
- Share price naik seiring yield bertambah
- Formula: `sharePrice = totalAssets / totalShares`

### Batching:
- Pending deposits/withdraws dikumpulkan
- Execute dalam 1 transaction untuk hemat gas
- Interval default 6 hours (bisa di-adjust)

### Allocation:
- Percentage dana yang di-deploy ke setiap protocol
- Conservative: 70-30 (safety-focused)
- Balanced: 50-50 (balanced)
- Aggressive: 30-70 (yield-focused)

### Auto-Compound:
- Yield otomatis di-harvest
- Performance fee (10%) dipotong
- Sisanya di-reinvest
- Share price naik, profit otomatis untuk holders

### Proportional Withdrawal:
- Saat withdraw, ambil dari semua strategies
- Proporsional sesuai allocation
- Maintain balance allocation

---

Semoga brief ini cukup lengkap untuk AI agent memahami struktur dan flow proyek ini!