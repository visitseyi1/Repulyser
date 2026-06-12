// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReputationRegistry} from "./IReputationRegistry.sol";

/// @title ReputationRegistry
/// @notice Stores onchain reputation signals for Pharos / EVM addresses.
/// @dev The registry is intentionally minimal — it stores signals, lets
///      approved attestors append, and lets the analyzer aggregate. No
///      scoring, decay, or access logic lives here; that is the
///      ReputationAnalyzer's job. This keeps the registry cheap to write to
///      and easy to audit.
contract ReputationRegistry is IReputationRegistry {
    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------

    /// @dev Owner = deployer. Can register / revoke attestors.
    address public owner;

    /// @dev attestor => registered?
    mapping(address => bool) public attestors;
    mapping(address => string) public attestorNames;

    /// @dev subject => handle
    mapping(address => string) public handles;
    mapping(address => bool) public registered;

    /// @dev signalId => Signal
    mapping(uint256 => Signal) internal _signals;
    uint256 public override signalCount;

    /// @dev subject => list of signalIds (append-only)
    mapping(address => uint256[]) internal _subjectSignals;

    /// @dev subject => signalType => latest signalId
    mapping(address => mapping(SignalType => uint256)) public latestSignalIdByType;

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "ReputationRegistry: not owner");
        _;
    }

    modifier onlyAttestor() {
        require(attestors[msg.sender], "ReputationRegistry: not attestor");
        _;
    }

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    // ---------------------------------------------------------------------
    // Owner functions
    // ---------------------------------------------------------------------

    function registerAttestor(address attestor, string calldata name) external onlyOwner {
        require(attestor != address(0), "ReputationRegistry: zero attestor");
        require(!attestors[attestor], "ReputationRegistry: already attestor");
        attestors[attestor] = true;
        attestorNames[attestor] = name;
        emit AttestorRegistered(attestor, name);
    }

    function revokeAttestor(address attestor) external onlyOwner {
        require(attestors[attestor], "ReputationRegistry: not attestor");
        attestors[attestor] = false;
        delete attestorNames[attestor];
        emit AttestorRevoked(attestor);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ReputationRegistry: zero owner");
        owner = newOwner;
    }

    // ---------------------------------------------------------------------
    // Subject self-registration
    // ---------------------------------------------------------------------

    function registerSubject(string calldata handle) external {
        require(!registered[msg.sender], "ReputationRegistry: already registered");
        require(bytes(handle).length > 0 && bytes(handle).length <= 64, "ReputationRegistry: bad handle");
        registered[msg.sender] = true;
        handles[msg.sender] = handle;
        emit SubjectRegistered(msg.sender, handle);
    }

    function isAttestor(address attestor) external view override returns (bool) {
        return attestors[attestor];
    }

    function isRegisteredSubject(address subject) external view override returns (bool) {
        return registered[subject];
    }

    function handleOf(address subject) external view override returns (string memory) {
        return handles[subject];
    }

    // ---------------------------------------------------------------------
    // Signal writes
    // ---------------------------------------------------------------------

    function submitSignal(address subject, SignalType signalType, uint16 score, uint16 weight, bytes calldata data)
        external
        onlyAttestor
        returns (uint256 signalId)
    {
        require(subject != address(0), "ReputationRegistry: zero subject");
        require(score <= 10_000, "ReputationRegistry: score>10000");
        require(weight > 0 && weight <= 10_000, "ReputationRegistry: bad weight");
        require(data.length <= 256, "ReputationRegistry: data too long");

        signalCount += 1;
        signalId = signalCount;

        _signals[signalId] = Signal({
            subject: subject,
            signalType: signalType,
            score: score,
            weight: weight,
            timestamp: uint64(block.timestamp),
            data: data
        });

        _subjectSignals[subject].push(signalId);
        latestSignalIdByType[subject][signalType] = signalId;

        emit SignalSubmitted(signalId, msg.sender, subject, signalType, score);
    }

    /// @notice Attestors can clear their own signals.
    function revokeSignal(uint256 signalId) external onlyAttestor {
        Signal memory s = _signals[signalId];
        require(s.subject != address(0), "ReputationRegistry: no signal");
        delete _signals[signalId];
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function signalsOf(address subject) external view override returns (uint256[] memory) {
        return _subjectSignals[subject];
    }

    function getSignal(uint256 signalId) external view override returns (Signal memory) {
        Signal memory s = _signals[signalId];
        require(s.subject != address(0), "ReputationRegistry: no signal");
        return s;
    }

    /// @notice Non-reverting variant of `getSignal` — returns zero struct if missing.
    function tryGetSignal(uint256 signalId) external view returns (Signal memory, bool) {
        Signal memory s = _signals[signalId];
        if (s.subject == address(0)) {
            return (s, false);
        }
        return (s, true);
    }

    function latestSignalOf(address subject, SignalType signalType)
        external
        view
        override
        returns (Signal memory, bool)
    {
        uint256 id = latestSignalIdByType[subject][signalType];
        if (id == 0) {
            return (_signals[0], false);
        }
        return (_signals[id], true);
    }

    // Convenience for off-chain indexers
    function attestorName(address attestor) external view returns (string memory) {
        return attestorNames[attestor];
    }
}
