// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReputationRegistry} from "./IReputationRegistry.sol";

/// @title ReputationAnalyzer
/// @notice Pure view-only contract that consumes signals from a
///         `ReputationRegistry` and returns a composite reputation report.
/// @dev Scoring model:
///      - Each `SignalType` has a fixed weight (sums to 10000 bps).
///      - For each signal type, the analyzer picks the LATEST non-stale
///        signal per subject (configurable staleness window, default 90 days)
///        and applies a linear time-decay: fresh = 100%, after 2x window = 0%.
///      - Per-type score is the attestor-weighted average of fresh signals,
///        multiplied by the type weight, divided by 10000.
///      - Final score = sum(perTypeScore) / 100, in 0..100.
///      - Tier is derived from the final score: Unverified, Bronze, Silver,
///        Gold, Platinum, Diamond.
contract ReputationAnalyzer {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum Tier {
        Unverified, // 0
        Bronze, // 1   score >= 20
        Silver, // 2   score >= 40
        Gold, // 3   score >= 60
        Platinum, // 4   score >= 80
        Diamond // 5   score >= 95
    }

    /// @notice Per-signal-type report.
    struct SignalBreakdown {
        IReputationRegistry.SignalType signalType;
        uint16 rawScore; // attestor-weighted average (0..10000)
        uint16 decayedScore; // after time decay (0..10000)
        uint16 typeWeight; // fixed weight for this type (0..10000, sum=10000)
        uint16 contribution; // decayedScore * typeWeight / 10000
        uint64 lastUpdate; // 0 if no signal
        uint16 signalsUsed; // count of fresh signals aggregated
    }

    /// @notice Full reputation report for a subject.
    struct Report {
        address subject;
        uint16 score; // 0..10000 (i.e. percent * 100)
        Tier tier;
        uint8 signalsPresent; // how many signal types had fresh data
        uint8 signalsTotal; // total possible types (10)
        uint64 generatedAt;
        SignalBreakdown[10] breakdown;
    }

    // ---------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------

    /// @notice Type weight in bps. Index matches `SignalType`. Sum = 10000.
    /// @dev    Defaults reflect an onchain identity: governance, DeFi and
    ///         activity matter more than NFT/social vanity metrics.
    uint16[10] public typeWeights = [
        1500, // AccountAge
        1200, // TxVolume
        1000, // TxFrequency
        1500, // DefiInteractions
        1500, // GovernanceVotes
        600, // NftHoldings
        400, // SocialEndorsements
        800, // ContractDeploys
        800, // AssetDiversity
        700 // LiquidStaking
    ];

    /// @notice A signal older than `stalenessWindow` seconds contributes 0.
    uint64 public stalenessWindow = 90 days;

    /// @notice If true, signals with no data still count as "present" for
    ///         coverage stats. Off by default.
    bool public requireData = false;

    IReputationRegistry public immutable registry;

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address registry_) {
        require(registry_ != address(0), "ReputationAnalyzer: zero registry");
        registry = IReputationRegistry(registry_);
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    function setStalenessWindow(uint64 window_) external {
        require(window_ >= 1 days && window_ <= 365 days, "ReputationAnalyzer: bad window");
        stalenessWindow = window_;
    }

    function setTypeWeight(uint8 idx, uint16 weight) external {
        require(idx < 10, "ReputationAnalyzer: bad idx");
        require(weight <= 10_000, "ReputationAnalyzer: bad weight");
        typeWeights[idx] = weight;
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    /// @notice Return the composite reputation report for `subject`.
    /// @dev    All computation is read-only and O(types * signalsPerSubject).
    ///         Safe to call from a view context (cast call).
    function analyze(address subject) external view returns (Report memory report) {
        report.subject = subject;
        report.generatedAt = uint64(block.timestamp);
        report.signalsTotal = 10;
        uint16 totalScore = 0;
        uint8 present = 0;

        uint256[] memory ids = IReputationRegistry(registry).signalsOf(subject);
        // Build a per-type aggregation: skip stale, sum score*weight and weights.
        uint64[10] memory lastUpdate;
        uint256[10] memory weightedSum;
        uint256[10] memory weightSum;
        uint16[10] memory used;

        uint64 window = stalenessWindow;
        uint64 nowTs = uint64(block.timestamp);
        // A signal is "stale" when age >= window (factor=0), and "fresh" at age=0 (factor=10000).
        // For 0 < age < window, factor = (window - age) * 10000 / window, linear.
        // Stale signals still show up in lastUpdate/signalsUsed but contribute 0 to score.

        for (uint256 i = 0; i < ids.length; i++) {
            (IReputationRegistry.Signal memory s, bool found) = IReputationRegistry(registry).tryGetSignal(ids[i]);
            if (!found) continue;
            if (s.subject != subject) continue;
            uint8 t = uint8(s.signalType);
            // We do NOT skip stale signals here: we still want to record their
            // lastUpdate and signalsUsed. The decay calculation below will set
            // decayedScore=0 for fully stale ones.
            if (requireData && s.data.length == 0) continue;
            weightedSum[t] += uint256(s.score) * uint256(s.weight);
            weightSum[t] += uint256(s.weight);
            if (s.timestamp > lastUpdate[t]) lastUpdate[t] = s.timestamp;
            used[t] += 1;
        }

        for (uint8 t = 0; t < 10; t++) {
            uint16 w = typeWeights[t];
            uint16 raw = 0;
            uint16 decayed = 0;
            uint16 contrib = 0;
            if (weightSum[t] > 0) {
                raw = uint16(weightedSum[t] / weightSum[t]); // 0..10000
                // Apply linear time decay over [0, window]: full at age=0, zero at age>=window.
                uint64 ts = lastUpdate[t];
                uint64 age = (nowTs >= ts) ? (nowTs - ts) : 0;
                uint256 factor;
                if (age >= window) {
                    factor = 0;
                } else {
                    factor = uint256(window - age) * 10_000 / uint256(window);
                }
                decayed = uint16(uint256(raw) * factor / 10_000);
                contrib = uint16(uint256(decayed) * uint256(w) / 10_000);
                present += 1;
            }
            report.breakdown[t] = SignalBreakdown({
                signalType: IReputationRegistry.SignalType(t),
                rawScore: raw,
                decayedScore: decayed,
                typeWeight: w,
                contribution: contrib,
                lastUpdate: lastUpdate[t],
                signalsUsed: used[t]
            });
            totalScore += contrib;
        }

        report.signalsPresent = present;
        report.score = totalScore; // 0..10000 (i.e. percent * 100)
        report.tier = _tierOf(totalScore);
    }

    /// @notice Lightweight helper: just the score 0..10000 and tier enum.
    /// @dev    Cheaper to call when you don't need the full breakdown.
    function quickScore(address subject) external view returns (uint16 score, Tier tier, uint8 present) {
        Report memory r = this.analyze(subject);
        return (r.score, r.tier, r.signalsPresent);
    }

    function tierString(Tier t) public pure returns (string memory) {
        if (t == Tier.Bronze) return "Bronze";
        if (t == Tier.Silver) return "Silver";
        if (t == Tier.Gold) return "Gold";
        if (t == Tier.Platinum) return "Platinum";
        if (t == Tier.Diamond) return "Diamond";
        return "Unverified";
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _tierOf(uint16 score) internal pure returns (Tier) {
        // score is 0..10000 (i.e. 0.00..100.00 percent * 100).
        if (score >= 9500) return Tier.Diamond;
        if (score >= 8000) return Tier.Platinum;
        if (score >= 6000) return Tier.Gold;
        if (score >= 4000) return Tier.Silver;
        if (score >= 2000) return Tier.Bronze;
        return Tier.Unverified;
    }
}
