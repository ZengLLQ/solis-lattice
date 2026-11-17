// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ISolisDebtToken} from "../interfaces/ISolisDebtToken.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";

/// @title SolisDebtToken
/// @notice Scaled synthetic debt token (sUSD) tracking user debt balances against the global borrow index.
/// @dev Implements full ERC20 transfers for sUSD by transferring underlying scaled debt shares.
contract SolisDebtToken is ISolisDebtToken {
    using WadRayMath for uint256;

    string public constant name = "Solis USD Debt";
    string public constant symbol = "sUSD";
    uint8 public constant decimals = 18;
    uint256 internal constant RAY = 1e27;

    address public immutable override pool;

    uint256 private _scaledTotalSupply;
    mapping(address => uint256) private _scaledBalances;
    mapping(address => mapping(address => uint256)) private _allowances;

    error OnlyLendingPool();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

    modifier onlyPool() {
        if (msg.sender != pool) revert OnlyLendingPool();
        _;
    }

    constructor(address _pool) {
        if (_pool == address(0)) revert ZeroAddress();
        pool = _pool;
    }

    function _getBorrowIndex() internal view returns (uint256) {
        try ILendingPool(pool).borrowIndex() returns (uint256 idx) {
            return idx > 0 ? idx : RAY;
        } catch {
            return RAY;
        }
    }

    function scaledTotalSupply() external view override returns (uint256) {
        return _scaledTotalSupply;
    }

    function scaledBalanceOf(address user) external view override returns (uint256) {
        return _scaledBalances[user];
    }

    function totalSupply() external view override returns (uint256) {
        return (_scaledTotalSupply * _getBorrowIndex()) / RAY;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return (_scaledBalances[account] * _getBorrowIndex()) / RAY;
    }

    function mint(address to, uint256 amount, uint256 currentBorrowIndex) external override onlyPool returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) return false;

        uint256 idx = currentBorrowIndex > 0 ? currentBorrowIndex : RAY;
        uint256 scaledAmount = amount.rayDivUp(idx);
        _scaledBalances[to] += scaledAmount;
        _scaledTotalSupply += scaledAmount;

        emit MintScaled(msg.sender, to, amount, idx);
        emit Transfer(address(0), to, amount);
        return true;
    }

    function burn(address from, uint256 amount, uint256 currentBorrowIndex) external override onlyPool returns (bool) {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) return false;

        uint256 idx = currentBorrowIndex > 0 ? currentBorrowIndex : RAY;
        uint256 scaledAmount = amount.rayDiv(idx);
        uint256 userScaledBalance = _scaledBalances[from];

        if (scaledAmount > userScaledBalance) {
            scaledAmount = userScaledBalance;
        }

        _scaledBalances[from] = userScaledBalance - scaledAmount;
        _scaledTotalSupply -= scaledAmount;

        emit BurnScaled(from, from, amount, idx);
        emit Transfer(from, address(0), amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) return;

        uint256 idx = _getBorrowIndex();
        uint256 scaledAmount = amount.rayDiv(idx);
        uint256 fromScaled = _scaledBalances[from];

        if (fromScaled < scaledAmount) revert InsufficientBalance();

        _scaledBalances[from] = fromScaled - scaledAmount;
        _scaledBalances[to] += scaledAmount;

        emit Transfer(from, to, amount);
    }
}
