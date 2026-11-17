// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPIDRateController} from "../interfaces/IPIDRateController.sol";
import {PIDMath} from "../libraries/PIDMath.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {LatticeAccessController} from "../governance/LatticeAccessController.sol";

/// @title PIDRateController
/// @notice Continuous closed-loop Proportional-Integral-Derivative (PID) interest rate regulator for SolisLattice.
/// @dev Eliminates rigid piecewise kink curves by dynamically modulating borrow rate toward target utilization equilibrium.
contract PIDRateController is IPIDRateController {
    using WadRayMath for uint256;

    LatticeAccessController public immutable accessController;

    PIDParameters private _params;
    PIDMetrics private _metrics;

    error Unauthorized();
    error ZeroAddress();
    error InvalidPIDParameters();

    modifier onlyRateOperator() {
        if (!accessController.hasRole(accessController.RATE_OPERATOR_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        address _accessController,
        int256 _kpWad,
        int256 _kiWad,
        int256 _kdWad,
        uint256 _targetUtilWad,
        uint256 _baseRateWad,
        uint256 _minRateWad,
        uint256 _maxRateWad,
        int256 _integralClampWad
    ) {
        if (_accessController == address(0)) revert ZeroAddress();
        if (_minRateWad > _maxRateWad || _targetUtilWad > WadRayMath.WAD) revert InvalidPIDParameters();

        accessController = LatticeAccessController(_accessController);

        _params = PIDParameters({
            kpWad: _kpWad,
            kiWad: _kiWad,
            kdWad: _kdWad,
            targetUtilWad: _targetUtilWad,
            baseRateWad: _baseRateWad,
            minRateWad: _minRateWad,
            maxRateWad: _maxRateWad,
            integralClampWad: _integralClampWad
        });

        _metrics = PIDMetrics({
            lastErrorWad: 0,
            integralAccumulatorWad: 0,
            lastTimestamp: block.timestamp,
            currentRateWad: _baseRateWad,
            currentUtilizationWad: 0
        });
    }

    /// @notice Computes and commits the updated borrow interest rate based on current pool utilization.
    function computeBorrowRate(uint256 totalBorrows, uint256 totalReserves)
        external
        override
        returns (uint256 newRateWad)
    {
        uint256 currentUtilWad = _calculateUtilization(totalBorrows, totalReserves);
        uint256 dt = block.timestamp - _metrics.lastTimestamp;

        (int256 deltaRateWad, int256 newErrorWad, int256 newIntegralWad) = PIDMath.evaluatePID(
            currentUtilWad,
            _params.targetUtilWad,
            _metrics.lastErrorWad,
            _metrics.integralAccumulatorWad,
            dt,
            _params.kpWad,
            _params.kiWad,
            _params.kdWad,
            _params.integralClampWad
        );

        int256 candidateRate = int256(_params.baseRateWad) + deltaRateWad;

        // Apply hard safety clamps
        if (candidateRate < int256(_params.minRateWad)) {
            newRateWad = _params.minRateWad;
        } else if (candidateRate > int256(_params.maxRateWad)) {
            newRateWad = _params.maxRateWad;
        } else {
            newRateWad = uint256(candidateRate);
        }

        _metrics.lastErrorWad = newErrorWad;
        _metrics.integralAccumulatorWad = newIntegralWad;
        _metrics.lastTimestamp = block.timestamp;
        _metrics.currentRateWad = newRateWad;
        _metrics.currentUtilizationWad = currentUtilWad;

        emit PIDStateUpdated(newRateWad, currentUtilWad, newErrorWad, newIntegralWad);
    }

    /// @notice Read-only preview of what the borrow rate would be given current pool balances.
    function previewBorrowRate(uint256 totalBorrows, uint256 totalReserves)
        external
        view
        override
        returns (uint256 rateWad)
    {
        uint256 currentUtilWad = _calculateUtilization(totalBorrows, totalReserves);
        uint256 dt = block.timestamp > _metrics.lastTimestamp ? block.timestamp - _metrics.lastTimestamp : 0;

        (int256 deltaRateWad,,) = PIDMath.evaluatePID(
            currentUtilWad,
            _params.targetUtilWad,
            _metrics.lastErrorWad,
            _metrics.integralAccumulatorWad,
            dt,
            _params.kpWad,
            _params.kiWad,
            _params.kdWad,
            _params.integralClampWad
        );

        int256 candidateRate = int256(_params.baseRateWad) + deltaRateWad;
        if (candidateRate < int256(_params.minRateWad)) {
            return _params.minRateWad;
        } else if (candidateRate > int256(_params.maxRateWad)) {
            return _params.maxRateWad;
        } else {
            return uint256(candidateRate);
        }
    }

    function getPIDParameters() external view override returns (PIDParameters memory) {
        return _params;
    }

    function getPIDMetrics() external view override returns (PIDMetrics memory) {
        return _metrics;
    }

    function setPIDParameters(PIDParameters calldata newParams) external onlyRateOperator {
        if (newParams.minRateWad > newParams.maxRateWad || newParams.targetUtilWad > WadRayMath.WAD) {
            revert InvalidPIDParameters();
        }
        _params = newParams;
    }

    function _calculateUtilization(uint256 totalBorrows, uint256 totalReserves) internal pure returns (uint256) {
        uint256 totalLiquidity = totalBorrows + totalReserves;
        if (totalLiquidity == 0) return 0;
        return totalBorrows.wadDiv(totalLiquidity);
    }
}
