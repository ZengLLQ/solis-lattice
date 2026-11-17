// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title LatticeAccessController
/// @notice Granular role-based capability governance controller for the SolisLattice protocol.
contract LatticeAccessController {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant EMERGENCY_GUARDIAN_ROLE = keccak256("EMERGENCY_GUARDIAN_ROLE");
    bytes32 public constant RATE_OPERATOR_ROLE = keccak256("RATE_OPERATOR_ROLE");
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");

    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => bytes32) private _adminRoles;

    bool public isPaused;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event ProtocolPaused(address indexed guardian);
    event ProtocolUnpaused(address indexed guardian);

    error Unauthorized(bytes32 role, address account);
    error ProtocolIsPaused();
    error ProtocolNotPaused();

    modifier onlyRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) revert Unauthorized(role, msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if (isPaused) revert ProtocolIsPaused();
        _;
    }

    modifier whenPaused() {
        if (!isPaused) revert ProtocolNotPaused();
        _;
    }

    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "Zero address admin");
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(TIMELOCK_ROLE, initialAdmin);
        _grantRole(EMERGENCY_GUARDIAN_ROLE, initialAdmin);
        _grantRole(RATE_OPERATOR_ROLE, initialAdmin);
        _grantRole(RISK_ADMIN_ROLE, initialAdmin);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function pause() external onlyRole(EMERGENCY_GUARDIAN_ROLE) {
        isPaused = true;
        emit ProtocolPaused(msg.sender);
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isPaused = false;
        emit ProtocolUnpaused(msg.sender);
    }

    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}
