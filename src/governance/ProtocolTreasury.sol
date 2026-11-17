// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {LatticeAccessController} from "./LatticeAccessController.sol";

/// @title ProtocolTreasury
/// @notice Treasury contract managing protocol reserve funds, liquidation fees, and insurance reserves.
contract ProtocolTreasury {
    LatticeAccessController public immutable accessController;

    uint256 public insuranceFundBps = 3000; // 30% of fees to insurance fund
    uint256 public treasuryReserveBps = 7000; // 70% to protocol development reserve

    mapping(address => uint256) public insuranceBalances;
    mapping(address => uint256) public reserveBalances;

    event FeeReceived(address indexed asset, uint256 totalAmount, uint256 insuranceAmount, uint256 reserveAmount);
    event FundsWithdrawn(address indexed asset, address indexed recipient, uint256 amount, string reason);
    event FeeDistributionUpdated(uint256 insuranceBps, uint256 reserveBps);

    error Unauthorized();
    error ZeroAddress();
    error InsufficientReserve();
    error InvalidBpsTotal();

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    constructor(address _accessController) {
        if (_accessController == address(0)) revert ZeroAddress();
        accessController = LatticeAccessController(_accessController);
    }

    /// @notice Records inbound protocol fees and splits them between insurance and treasury reserves.
    function recordFee(address asset, uint256 amount) external {
        if (amount == 0) return;
        uint256 insuranceShare = (amount * insuranceFundBps) / 10000;
        uint256 reserveShare = amount - insuranceShare;

        insuranceBalances[asset] += insuranceShare;
        reserveBalances[asset] += reserveShare;

        emit FeeReceived(asset, amount, insuranceShare, reserveShare);
    }

    /// @notice Withdraws treasury funds for protocol maintenance or buybacks.
    function withdrawReserves(address asset, address recipient, uint256 amount, string calldata reason)
        external
        onlyAdmin
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (reserveBalances[asset] < amount) revert InsufficientReserve();

        reserveBalances[asset] -= amount;
        bool success = IERC20(asset).transfer(recipient, amount);
        require(success, "Transfer failed");

        emit FundsWithdrawn(asset, recipient, amount, reason);
    }

    /// @notice Disburses insurance funds to cover bad debt socializations.
    function disburseInsurance(address asset, address recipient, uint256 amount, string calldata reason) external {
        if (!accessController.hasRole(accessController.RISK_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        if (recipient == address(0)) revert ZeroAddress();
        if (insuranceBalances[asset] < amount) revert InsufficientReserve();

        insuranceBalances[asset] -= amount;
        bool success = IERC20(asset).transfer(recipient, amount);
        require(success, "Transfer failed");

        emit FundsWithdrawn(asset, recipient, amount, reason);
    }

    function setFeeSplit(uint256 _insuranceBps, uint256 _reserveBps) external onlyAdmin {
        if (_insuranceBps + _reserveBps != 10000) revert InvalidBpsTotal();
        insuranceFundBps = _insuranceBps;
        treasuryReserveBps = _reserveBps;
        emit FeeDistributionUpdated(_insuranceBps, _reserveBps);
    }
}
