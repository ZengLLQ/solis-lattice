// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "./IERC20.sol";

/// @title ISolisDebtToken
/// @notice Interface for synthetic debt token (sUSD) minted against deposited collateral.
interface ISolisDebtToken is IERC20 {
    event MintScaled(address indexed caller, address indexed onBehalfOf, uint256 amount, uint256 index);
    event BurnScaled(address indexed from, address indexed target, uint256 amount, uint256 index);

    function mint(address to, uint256 amount, uint256 currentBorrowIndex) external returns (bool);
    function burn(address from, uint256 amount, uint256 currentBorrowIndex) external returns (bool);
    function scaledBalanceOf(address user) external view returns (uint256);
    function scaledTotalSupply() external view returns (uint256);
    function pool() external view returns (address);
}
