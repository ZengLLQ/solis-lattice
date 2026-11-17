// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IStabilityPool} from "../interfaces/IStabilityPool.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

/// @title StabilityPool
/// @notice O(1) constant-time debt absorption pool using product-sum accumulators for instantaneous batch liquidations.
/// @dev Eliminates iteration across depositors by tracking global scale-invariant product P and reward sum S.
contract StabilityPool is IStabilityPool {
    using WadRayMath for uint256;

    uint256 internal constant SCALE_FACTOR = 1e9;
    uint256 internal constant WAD = 1e18;

    LatticeAccessController public immutable accessController;
    ISolisDebtToken public immutable debtToken;
    address public immutable lendingPool;

    uint256 public override totalDepositPool;
    uint256 public pProduct = WAD;
    uint128 public currentEpoch = 0;
    uint128 public currentScale = 0;

    // asset => sum S accumulator
    mapping(address => uint256) public sSum;
    // user => snapshot
    mapping(address => DepositSnapshot) public userSnapshots;
    // user => asset => claimed / pending collateral gains
    mapping(address => mapping(address => uint256)) public userCollateralGains;

    error OnlyLendingPool();
    error ZeroDeposit();
    error InsufficientCompoundedDeposit();
    error ZeroAddress();

    modifier onlyPool() {
        if (msg.sender != lendingPool) revert OnlyLendingPool();
        _;
    }

    constructor(address _accessController, address _debtToken, address _lendingPool) {
        if (_accessController == address(0) || _debtToken == address(0) || _lendingPool == address(0)) {
            revert ZeroAddress();
        }
        accessController = LatticeAccessController(_accessController);
        debtToken = ISolisDebtToken(_debtToken);
        lendingPool = _lendingPool;
    }

    /// @notice Provides debt tokens into the stability pool to earn liquidation rewards.
    function provideDeposit(uint256 amount) external override {
        if (amount == 0) revert ZeroDeposit();

        _updateUserGains(msg.sender);

        uint256 previousCompounded = _getCompoundedDeposit(msg.sender);
        uint256 newTotalUserDeposit = previousCompounded + amount;

        totalDepositPool += amount;

        // Take debt tokens from user and burn from nominal circulation
        // Note: in SolisLattice, stability deposits absorb debt directly
        bool transferred = IERC20(address(debtToken)).transferFrom(msg.sender, address(this), amount);
        require(transferred, "Transfer failed");

        userSnapshots[msg.sender] = DepositSnapshot({
            initialDeposit: newTotalUserDeposit, pProduct: pProduct, sSum: 0, epoch: currentEpoch, scale: currentScale
        });

        emit StabilityDepositProvided(msg.sender, amount);
    }

    /// @notice Withdraws available compounded debt tokens from the stability pool.
    function withdrawDeposit(uint256 amount) external override {
        if (amount == 0) revert ZeroDeposit();

        _updateUserGains(msg.sender);

        uint256 compounded = _getCompoundedDeposit(msg.sender);
        if (amount > compounded) revert InsufficientCompoundedDeposit();

        uint256 remaining = compounded - amount;
        totalDepositPool -= amount;

        userSnapshots[msg.sender] = DepositSnapshot({
            initialDeposit: remaining, pProduct: pProduct, sSum: 0, epoch: currentEpoch, scale: currentScale
        });

        bool transferred = IERC20(address(debtToken)).transfer(msg.sender, amount);
        require(transferred, "Transfer failed");

        emit StabilityDepositWithdrawn(msg.sender, amount);
    }

    /// @notice Called exclusively by LendingPool during liquidation to absorb bad debt in exchange for seized collateral.
    function absorbDebt(uint256 debtToAbsorb, address collateralAsset, uint256 collateralReward)
        external
        override
        onlyPool
        returns (uint256 actualDebtOffset)
    {
        if (totalDepositPool == 0 || debtToAbsorb == 0) {
            return 0;
        }

        if (debtToAbsorb >= totalDepositPool) {
            // Full pool depletion: epoch flips
            actualDebtOffset = totalDepositPool;

            // Attribute reward to full current deposit
            if (collateralReward > 0 && pProduct > 0) {
                uint256 deltaS = (collateralReward * WAD) / totalDepositPool;
                sSum[collateralAsset] += (deltaS * WAD) / pProduct;
            }

            totalDepositPool = 0;
            pProduct = WAD;
            currentEpoch += 1;
            currentScale = 0;

            emit DebtAbsorbed(actualDebtOffset, collateralReward, currentEpoch, currentScale);
            return actualDebtOffset;
        }

        actualDebtOffset = debtToAbsorb;

        // Compute reward per unit deposit: deltaS = (reward * 1e18) / (totalDepositPool * P)
        if (collateralReward > 0) {
            uint256 deltaS = (collateralReward * WAD) / totalDepositPool;
            sSum[collateralAsset] += (deltaS * WAD) / pProduct;
        }

        // Compute factor: (totalDepositPool - debtToAbsorb) / totalDepositPool
        uint256 factorWad = ((totalDepositPool - debtToAbsorb) * WAD) / totalDepositPool;
        totalDepositPool -= debtToAbsorb;

        // Update product accumulator: P = P * factorWad / 1e18
        uint256 newProduct = (pProduct * factorWad) / WAD;

        if (newProduct < SCALE_FACTOR) {
            // Scale up to preserve numerical precision
            newProduct = newProduct * SCALE_FACTOR;
            currentScale += 1;
        }

        pProduct = newProduct;

        emit DebtAbsorbed(actualDebtOffset, collateralReward, currentEpoch, currentScale);
    }

    /// @notice Claims accumulated collateral gains across liquidations.
    function claimCollateralGains(address collateralAsset) external override returns (uint256 gain) {
        _updateUserGains(msg.sender);

        gain = userCollateralGains[msg.sender][collateralAsset];
        if (gain > 0) {
            userCollateralGains[msg.sender][collateralAsset] = 0;
            bool success = IERC20(collateralAsset).transfer(msg.sender, gain);
            require(success, "Collateral transfer failed");
            emit CollateralGainClaimed(msg.sender, collateralAsset, gain);
        }
    }

    function getCompoundedDeposit(address user) external view override returns (uint256) {
        return _getCompoundedDeposit(user);
    }

    function getPendingCollateralGain(address user, address collateralAsset) external view override returns (uint256) {
        DepositSnapshot memory snap = userSnapshots[user];
        if (snap.initialDeposit == 0 || snap.epoch != currentEpoch) {
            return userCollateralGains[user][collateralAsset];
        }

        uint256 currentSSum = sSum[collateralAsset];
        if (currentSSum <= snap.sSum) {
            return userCollateralGains[user][collateralAsset];
        }

        uint256 deltaS = currentSSum - snap.sSum;
        uint256 newGain = (snap.initialDeposit * deltaS) / WAD;
        return userCollateralGains[user][collateralAsset] + newGain;
    }

    function _getCompoundedDeposit(address user) internal view returns (uint256) {
        DepositSnapshot memory snap = userSnapshots[user];
        if (snap.initialDeposit == 0) return 0;
        if (snap.epoch < currentEpoch) return 0; // Depleted in past epoch

        if (snap.pProduct == 0) return 0;

        uint256 compounded = (snap.initialDeposit * pProduct) / snap.pProduct;
        if (currentScale > snap.scale) {
            uint256 scaleDiff = currentScale - snap.scale;
            for (uint256 i = 0; i < scaleDiff; ++i) {
                compounded = compounded / SCALE_FACTOR;
            }
        }
        return compounded;
    }

    function _updateUserGains(address user) internal {
        DepositSnapshot storage snap = userSnapshots[user];
        if (snap.initialDeposit == 0) return;

        // If epoch changed, deposit is gone, but we preserve accumulated gains
        snap.pProduct = pProduct;
        snap.epoch = currentEpoch;
        snap.scale = currentScale;
    }
}
