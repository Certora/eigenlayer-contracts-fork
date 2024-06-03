// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "../interfaces/IAVSDirectory.sol";
import "../interfaces/IStrategyManager.sol";
import "../interfaces/IDelegationManager.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenPodManager.sol";

abstract contract AVSDirectoryStorage is IAVSDirectory {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the `Registration` struct used by the contract
    bytes32 public constant OPERATOR_AVS_REGISTRATION_TYPEHASH =
        keccak256("OperatorAVSRegistration(address operator,address avs,bytes32 salt,uint256 expiry)");

    /// @notice The DelegationManager contract for EigenLayer
    IDelegationManager public immutable delegation;

    /// @notice The StrategyManager contract for EigenLayer
    IStrategyManager public immutable strategyManager;

    /**
     * @notice Original EIP-712 Domain separator for this contract.
     * @dev The domain separator may change in the event of a fork that modifies the ChainID.
     * Use the getter function `domainSeparator` to get the current domain separator for this contract.
     */
    bytes32 internal _DOMAIN_SEPARATOR;
    
    /// @notice Mapping: AVS => operator => enum of operator status to the AVS
    mapping(address => mapping(address => OperatorAVSRegistrationStatus)) public avsOperatorStatus;

    /// @notice Mapping: operator => 32-byte salt => whether or not the salt has already been used by the operator.
    /// @dev Salt is used in the `registerOperatorToAVS` function.
    mapping(address => mapping(bytes32 => bool)) public operatorSaltIsSpent;

    /// @notice Mapping: avs => whether or not the AVS has registered operators to operator set
    /// @dev Used to prevent legacy M2 registrations once the AVS has migrated to using operator sets
    mapping(address => bool) public isOperatorSetAVS;

    /// @notice Mapping: avs => operator => operatorSetId => whether the operator is registered for the operator set
    mapping(address => mapping(address => mapping(bytes4 => bool))) public operatorSetRegistrations;
    
    /// @notice Mapping: avs => operator => number of operator sets the operator is registered for the AVS
    mapping(address => mapping(address => uint256)) public operatorAVSOperatorSetCount;

    /// @notice Mapping: avs => operatorSetId => strategy => whether the strategy is in the operator set
    mapping(address => mapping(bytes4 => mapping(IStrategy => bool))) public avsOperatorSetStrategies;

    constructor(IDelegationManager _delegation, IStrategyManager _strategyManager) {
        delegation = _delegation;
        strategyManager = _strategyManager;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[44] private __gap;
}
