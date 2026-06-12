// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IReputationRegistry} from "../src/IReputationRegistry.sol";
import {ReputationAnalyzer} from "../src/ReputationAnalyzer.sol";

/// @title AnalyzeReputation
/// @notice Read-only forge script that prints a reputation report for an
///         address. Designed to be run with `cast`-style flags:
///         SUBJECT=0x... ANALYZER=0x... forge script script/AnalyzeReputation.s.sol:AnalyzeReputation
/// @dev This script only reads; no private key or --broadcast is needed.
contract AnalyzeReputation is Script {
    function run() external view {
        address subject = vm.envAddress("SUBJECT");
        address analyzerAddr = vm.envAddress("ANALYZER");

        ReputationAnalyzer analyzer = ReputationAnalyzer(analyzerAddr);
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject);

        console.log("=== Repulyser Report ===");
        console.log("Subject:           ", subject);
        console.log("Score (0-10000):   ", r.score);
        console.log("Score (percent):   ", r.score / 100);
        console.log("Tier:              ", analyzer.tierString(r.tier));
        console.log("Signals present:   ", r.signalsPresent, "/", r.signalsTotal);
        console.log("Generated at:      ", r.generatedAt);
        console.log("Breakdown (type, raw, decayed, weight, contribution, lastUpdate, used):");
        for (uint8 i = 0; i < 10; i++) {
            ReputationAnalyzer.SignalBreakdown memory b = r.breakdown[i];
            console.log("type:", uint8(b.signalType));
            console.log("  raw:", b.rawScore);
            console.log("  decayed:", b.decayedScore);
            console.log("  weight:", b.typeWeight);
            console.log("  contribution:", b.contribution);
            console.log("  lastUpdate:", b.lastUpdate);
            console.log("  used:", b.signalsUsed);
        }
    }
}
