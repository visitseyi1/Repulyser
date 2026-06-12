// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReputationRegistry
/// @notice Interface for the Repulyser onchain reputation registry.
/// @dev All reputation signals are written here by approved attestors. The
///      ReputationAnalyzer reads from this contract to compute composite scores.
interface IReputationRegistry {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum SignalType {
        AccountAge, // 0 - wallet age in days since first tx
        TxVolume, // 1 - lifetime native token volume (PHRS/PROS)
        TxFrequency, // 2 - tx count in last 30 days
        DefiInteractions, // 3 - distinct DeFi protocol interactions
        GovernanceVotes, // 4 - onchain DAO votes cast
        NftHoldings, // 5 - number of NFTs held
        SocialEndorsements, // 6 - peer endorsements received
        ContractDeploys, // 7 - contracts deployed by the address
        AssetDiversity, // 8 - count of distinct ERC20 tokens held (>0)
        LiquidStaking // 9 - active liquid staking positions
    }

    /// @notice One reputation signal write.
    /// @param subject     Address the signal is about.
    /// @param signalType  Which signal dimension.
    /// @param score       Normalised 0..10000 (basis points of a "perfect" score).
    /// @param weight      Attestor-supplied weight in basis points (sum across attestors
    ///                    for a subject is recomputed at read time; stale signals
    ///                    decay via `timestamp`).
    /// @param timestamp   Block timestamp of the attestation.
    /// @param data        Optional opaque payload (e.g. raw metric, attestation URI).
    struct Signal {
        address subject;
        SignalType signalType;
        uint16 score; // 0..10000
        uint16 weight; // 0..10000
        uint64 timestamp;
        bytes data; // optional, e.g. short uri or metric blob
    }

    event AttestorRegistered(address indexed attestor, string name);
    event AttestorRevoked(address indexed attestor);
    event SignalSubmitted(
        uint256 indexed signalId, address indexed attestor, address indexed subject, SignalType signalType, uint16 score
    );
    event SubjectRegistered(address indexed subject, string handle);

    // ---------------------------------------------------------------------
    // Attestor management
    // ---------------------------------------------------------------------

    function registerAttestor(address attestor, string calldata name) external;
    function revokeAttestor(address attestor) external;
    function isAttestor(address attestor) external view returns (bool);

    // ---------------------------------------------------------------------
    // Subject self-registration
    // ---------------------------------------------------------------------

    function registerSubject(string calldata handle) external;
    function isRegisteredSubject(address subject) external view returns (bool);
    function handleOf(address subject) external view returns (string memory);

    // ---------------------------------------------------------------------
    // Signal writes
    // ---------------------------------------------------------------------

    function submitSignal(address subject, SignalType signalType, uint16 score, uint16 weight, bytes calldata data)
        external
        returns (uint256 signalId);

    function revokeSignal(uint256 signalId) external;

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function signalCount() external view returns (uint256);
    function signalsOf(address subject) external view returns (uint256[] memory);
    function getSignal(uint256 signalId) external view returns (Signal memory);
    function tryGetSignal(uint256 signalId) external view returns (Signal memory, bool);
    function latestSignalOf(address subject, SignalType signalType) external view returns (Signal memory, bool);
}
