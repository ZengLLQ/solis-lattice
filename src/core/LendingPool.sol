// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";
import {IPIDRateController} from "../interfaces/IPIDRateController.sol";
import {ICompositeOracle} from "../interfaces/ICompositeOracle.sol";
import {IStabilityPool} from "../interfaces/IStabilityPool.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {ExpCompoundMath} from "../libraries/ExpCompoundMath.sol";
import {TransientSlot} from "../libraries/TransientSlot.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

/// @title LendingPool
/// @notice Core multi-asset collateral facility and synthetic debt engine for SolisLattice.
contract LendingPool is ILendingPool {
    using WadRayMath for uint256;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant WAD = 1e18;

    LatticeAccessController public immutable accessController;
    ISolisDebtToken public debtToken;
    IPIDRateController public rateController;
    ICompositeOracle public oracle;
    IStabilityPool public stabilityPool;
    address public treasury;

    uint256 public override borrowIndex = RAY;
    uint256 public lastUpdateTimestamp;
    uint256 public totalProtocolReserves;

    // asset => config
    mapping(address => CollateralConfig) private _collateralConfigs;
    address[] public supportedCollaterals;

    // user => asset => amount
    mapping(address => mapping(address => uint256)) private _userCollateral;

    error Unauthorized();
    error AssetNotSupported(address asset);
    error AssetFrozen(address asset);
    error ExceedsSupplyCap(address asset, uint256 cap);
    error InsufficientCollateral();
    error HealthFactorBelowOne(uint256 healthFactor);
    error HealthFactorSufficient(uint256 healthFactor);
    error ZeroAmount();
    error ZeroAddress();

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    modifier nonReentrant() {
        TransientSlot.lock();
        _;
        TransientSlot.unlock();
    }

    constructor(address _accessController) {
        if (_accessController == address(0)) revert ZeroAddress();
        accessController = LatticeAccessController(_accessController);
        lastUpdateTimestamp = block.timestamp;
    }

    function setDependencies(
        address _debtToken,
        address _rateController,
        address _oracle,
        address _stabilityPool,
        address _treasury
    ) external onlyAdmin {
        if (_debtToken != address(0)) debtToken = ISolisDebtToken(_debtToken);
        if (_rateController != address(0)) rateController = IPIDRateController(_rateController);
        if (_oracle != address(0)) oracle = ICompositeOracle(_oracle);
        if (_stabilityPool != address(0)) stabilityPool = IStabilityPool(_stabilityPool);
        if (_treasury != address(0)) treasury = _treasury;
    }

    function configureCollateral(
        address asset,
        uint256 ltvWad,
        uint256 liquidationThresholdWad,
        uint256 liquidationBonusWad,
        uint256 supplyCap,
        bool isEnabled
    ) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddress();
        if (ltvWad > liquidationThresholdWad || liquidationThresholdWad > WAD) revert InsufficientCollateral();

        CollateralConfig storage cfg = _collateralConfigs[asset];
        if (!cfg.isEnabled && isEnabled) {
            supportedCollaterals.push(asset);
        }

        cfg.ltvWad = ltvWad;
        cfg.liquidationThresholdWad = liquidationThresholdWad;
        cfg.liquidationBonusWad = liquidationBonusWad;
        cfg.supplyCap = supplyCap;
        cfg.isEnabled = isEnabled;
        cfg.isFrozen = false;
    }

    /// @notice Accrues interest on outstanding debt using the continuous compounding Taylor factor.
    function updateState() public {
        if (block.timestamp <= lastUpdateTimestamp) return;

        uint256 dt = block.timestamp - lastUpdateTimestamp;
        lastUpdateTimestamp = block.timestamp;

        uint256 totalBorrows = totalProtocolDebt();
        if (totalBorrows == 0 || address(rateController) == address(0)) return;

        uint256 borrowRateWad = rateController.computeBorrowRate(totalBorrows, totalProtocolReserves);
        uint256 compoundFactorRay = ExpCompoundMath.continuousCompoundFactorRay(borrowRateWad, dt);

        borrowIndex = borrowIndex.rayMul(compoundFactorRay);
    }

    /// @notice Deposits collateral asset into the pool on behalf of user.
    function deposit(address asset, uint256 amount, address onBehalfOf) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (onBehalfOf == address(0)) revert ZeroAddress();

        updateState();

        CollateralConfig storage cfg = _collateralConfigs[asset];
        if (!cfg.isEnabled) revert AssetNotSupported(asset);
        if (cfg.isFrozen) revert AssetFrozen(asset);

        if (cfg.totalSupplied + amount > cfg.supplyCap) {
            revert ExceedsSupplyCap(asset, cfg.supplyCap);
        }

        cfg.totalSupplied += amount;
        _userCollateral[onBehalfOf][asset] += amount;

        bool transferred = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(transferred, "Transfer failed");

        emit DepositCollateral(asset, msg.sender, onBehalfOf, amount);
    }

    /// @notice Withdraws deposited collateral asset to recipient.
    function withdraw(address asset, uint256 amount, address to) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        updateState();

        uint256 userBalance = _userCollateral[msg.sender][asset];
        if (amount > userBalance) revert InsufficientCollateral();

        _userCollateral[msg.sender][asset] = userBalance - amount;
        _collateralConfigs[asset].totalSupplied -= amount;

        // Verify solvency post-withdrawal
        UserAccountData memory accountData = getUserAccountData(msg.sender);
        if (accountData.totalDebtValueUsdWad > 0 && accountData.healthFactorWad < WAD) {
            revert HealthFactorBelowOne(accountData.healthFactorWad);
        }

        bool transferred = IERC20(asset).transfer(to, amount);
        require(transferred, "Transfer failed");

        emit WithdrawCollateral(asset, msg.sender, to, amount);
    }

    /// @notice Mints synthetic debt tokens (sUSD) to borrower.
    function borrow(uint256 amount, address to) external override {
        borrowOnBehalf(msg.sender, amount, to);
    }

    /// @notice Mints synthetic debt tokens (sUSD) against collateral of onBehalfOf to recipient.
    function borrowOnBehalf(address onBehalfOf, uint256 amount, address to) public override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0) || onBehalfOf == address(0)) revert ZeroAddress();

        updateState();

        UserAccountData memory accountData = getUserAccountData(onBehalfOf);
        if (amount > accountData.availableBorrowsUsdWad) {
            revert InsufficientCollateral();
        }

        debtToken.mint(to, amount, borrowIndex);

        emit BorrowDebt(onBehalfOf, to, amount, borrowIndex);
    }

    /// @notice Repays synthetic debt tokens on behalf of borrower.
    function repay(uint256 amount, address onBehalfOf) external override nonReentrant returns (uint256) {
        if (amount == 0) revert ZeroAmount();
        if (onBehalfOf == address(0)) revert ZeroAddress();

        updateState();

        uint256 userDebt = (debtToken.scaledBalanceOf(onBehalfOf) * borrowIndex) / RAY;
        uint256 actualRepay = amount > userDebt ? userDebt : amount;

        debtToken.burn(msg.sender, actualRepay, borrowIndex);

        emit RepayDebt(msg.sender, onBehalfOf, actualRepay, borrowIndex);
        return actualRepay;
    }

    /// @notice Seizes collateral during liquidation or stability pool absorption.
    function liquidateBadDebtDirect(address user, address collateralAsset, uint256 debtToCover)
        external
        override
        returns (uint256 collateralLiquidated)
    {
        updateState();

        UserAccountData memory accountData = getUserAccountData(user);
        if (accountData.healthFactorWad >= WAD) revert HealthFactorSufficient(accountData.healthFactorWad);

        uint256 assetPriceWad = oracle.getAssetPrice(collateralAsset);
        uint256 bonusWad = _collateralConfigs[collateralAsset].liquidationBonusWad;

        // Collateral needed = debtToCover * (1 + bonus) / price
        uint256 debtWithBonusWad = debtToCover.wadMul(WAD + bonusWad);
        collateralLiquidated = debtWithBonusWad.wadDiv(assetPriceWad);

        uint256 userCollateralBal = _userCollateral[user][collateralAsset];
        if (collateralLiquidated > userCollateralBal) {
            collateralLiquidated = userCollateralBal;
        }

        _userCollateral[user][collateralAsset] -= collateralLiquidated;
        _collateralConfigs[collateralAsset].totalSupplied -= collateralLiquidated;

        bool transferred = IERC20(collateralAsset).transfer(msg.sender, collateralLiquidated);
        require(transferred, "Collateral seizure transfer failed");
    }

    /// @notice Calculates composite account metrics, borrow power, and health factor.
    function getUserAccountData(address user) public view override returns (UserAccountData memory accountData) {
        uint256 totalCollateralUsdWad = 0;
        uint256 totalCollateralThreshUsdWad = 0;
        uint256 totalBorrowPowerUsdWad = 0;

        uint256 len = supportedCollaterals.length;
        for (uint256 i = 0; i < len; ++i) {
            address asset = supportedCollaterals[i];
            uint256 balance = _userCollateral[user][asset];
            if (balance > 0) {
                CollateralConfig memory cfg = _collateralConfigs[asset];
                if (cfg.isEnabled) {
                    uint256 priceWad = oracle.getAssetPrice(asset);
                    uint256 assetValueUsd = balance.wadMul(priceWad);

                    totalCollateralUsdWad += assetValueUsd;
                    totalBorrowPowerUsdWad += assetValueUsd.wadMul(cfg.ltvWad);
                    totalCollateralThreshUsdWad += assetValueUsd.wadMul(cfg.liquidationThresholdWad);
                }
            }
        }

        uint256 userDebt = (debtToken.scaledBalanceOf(user) * borrowIndex) / RAY;

        accountData.totalCollateralValueUsdWad = totalCollateralUsdWad;
        accountData.totalDebtValueUsdWad = userDebt;
        accountData.availableBorrowsUsdWad = totalBorrowPowerUsdWad > userDebt ? totalBorrowPowerUsdWad - userDebt : 0;
        accountData.currentLiquidationThresholdWad =
            totalCollateralUsdWad > 0 ? totalCollateralThreshUsdWad.wadDiv(totalCollateralUsdWad) : 0;

        if (userDebt == 0) {
            accountData.healthFactorWad = type(uint256).max;
        } else {
            accountData.healthFactorWad = totalCollateralThreshUsdWad.wadDiv(userDebt);
        }
    }

    function totalProtocolDebt() public view override returns (uint256) {
        return (debtToken.scaledTotalSupply() * borrowIndex) / RAY;
    }

    function getCollateralBalance(address user, address asset) external view override returns (uint256) {
        return _userCollateral[user][asset];
    }

    function getAssetConfig(address asset) external view override returns (CollateralConfig memory) {
        return _collateralConfigs[asset];
    }
}
