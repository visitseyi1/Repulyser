// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReputationRegistry} from "./IReputationRegistry.sol";

/// @title ReputationAttestor
/// @notice Thin helper contract that lets a deployer pre-authorize a list of
///         signal payloads and submit them in one transaction. Useful for
///         bot attestors that batch-update a wallet's reputation after an
///         off-chain analytics job (e.g. scoring the user's tx history).
/// @dev This contract is OPTIONAL — attestors can also call
///      `ReputationRegistry.submitSignal` directly. The attestor helper
///      exists so agents can do "score and submit in one forge script" with
///      minimal boilerplate.
contract ReputationAttestor {
    /// @notice Single pre-baked signal ready to be submitted.
    struct PendingSignal {
        address subject;
        IReputationRegistry.SignalType signalType;
        uint16 score;
        uint16 weight;
        bytes data;
        bool submitted;
    }

    IReputationRegistry public immutable registry;
    address public immutable owner;

    PendingSignal[] public pending;

    event PendingQueued(uint256 indexed index, address indexed subject, IReputationRegistry.SignalType signalType);
    event PendingSubmitted(uint256 indexed index, uint256 indexed signalId);

    modifier onlyOwner() {
        require(msg.sender == owner, "ReputationAttestor: not owner");
        _;
    }

    constructor(address registry_) {
        require(registry_ != address(0), "ReputationAttestor: zero registry");
        registry = IReputationRegistry(registry_);
        owner = msg.sender;
    }

    /// @notice Queue one signal payload. Does not write on-chain.
    function queue(
        address subject,
        IReputationRegistry.SignalType signalType,
        uint16 score,
        uint16 weight,
        bytes calldata data
    ) external onlyOwner returns (uint256 index) {
        index = pending.length;
        pending.push(PendingSignal(subject, signalType, score, weight, data, false));
        emit PendingQueued(index, subject, signalType);
    }

    /// @notice Submit one queued signal to the registry. Caller must be a
    ///         registered attestor on the registry.
    function submit(uint256 index) external returns (uint256 signalId) {
        require(IReputationRegistry(registry).isAttestor(msg.sender), "ReputationAttestor: not attestor");
        PendingSignal storage p = pending[index];
        require(!p.submitted, "ReputationAttestor: already submitted");
        p.submitted = true;
        signalId = IReputationRegistry(registry).submitSignal(p.subject, p.signalType, p.score, p.weight, p.data);
        emit PendingSubmitted(index, signalId);
    }

    /// @notice Submit every queued signal in one call. Useful for forge scripts.
    function submitAll() external returns (uint256[] memory signalIds) {
        require(IReputationRegistry(registry).isAttestor(msg.sender), "ReputationAttestor: not attestor");
        uint256 n = pending.length;
        signalIds = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            if (pending[i].submitted) continue;
            pending[i].submitted = true;
            signalIds[i] = IReputationRegistry(registry)
                .submitSignal(
                    pending[i].subject, pending[i].signalType, pending[i].score, pending[i].weight, pending[i].data
                );
            emit PendingSubmitted(i, signalIds[i]);
        }
    }

    function pendingLength() external view returns (uint256) {
        return pending.length;
    }
}
