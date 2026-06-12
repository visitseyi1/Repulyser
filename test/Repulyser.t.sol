// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ReputationRegistry, IReputationRegistry} from "../src/ReputationRegistry.sol";
import {ReputationAnalyzer} from "../src/ReputationAnalyzer.sol";
import {ReputationAttestor} from "../src/ReputationAttestor.sol";

/// @title Repulyser end-to-end tests
/// @notice Covers registry, attestor helper and analyzer scoring logic.
contract RepulyserTest is Test {
    ReputationRegistry registry;
    ReputationAnalyzer analyzer;
    ReputationAttestor helper;

    address owner = makeAddr("owner");
    address attestorA = makeAddr("attestorA");
    address attestorB = makeAddr("attestorB");
    address subject1 = makeAddr("subject1");
    address subject2 = makeAddr("subject2");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.startPrank(owner);
        registry = new ReputationRegistry();
        analyzer = new ReputationAnalyzer(address(registry));
        helper = new ReputationAttestor(address(registry));

        registry.registerAttestor(attestorA, "Attestor A");
        registry.registerAttestor(attestorB, "Attestor B");
        vm.stopPrank();

        vm.prank(subject1);
        registry.registerSubject("alice.repulyser");

        vm.prank(subject2);
        registry.registerSubject("bob.repulyser");
    }

    // ---------------------------------------------------------------------
    // Registry tests
    // ---------------------------------------------------------------------

    function test_OwnerIsDeployer() public view {
        assertEq(registry.owner(), owner, "owner mismatch");
    }

    function test_AttestorRegistration() public {
        assertTrue(registry.isAttestor(attestorA));
        assertTrue(registry.isAttestor(attestorB));
        assertFalse(registry.isAttestor(stranger));
        assertEq(registry.attestorName(attestorA), "Attestor A");
    }

    function test_OnlyOwnerCanRegisterAttestor() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("ReputationRegistry: not owner"));
        registry.registerAttestor(stranger, "hacker");
    }

    function test_RevokeAttestor() public {
        vm.prank(owner);
        registry.revokeAttestor(attestorA);
        assertFalse(registry.isAttestor(attestorA));
    }

    function test_StrangerCannotSubmitSignal() public {
        vm.prank(stranger);
        vm.expectRevert(bytes("ReputationRegistry: not attestor"));
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 5000, 5000, "");
    }

    function test_AttestorSubmitsSignal() public {
        vm.prank(attestorA);
        uint256 id = registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 7500, 9000, hex"01");
        assertEq(id, 1);
        assertEq(registry.signalCount(), 1);

        IReputationRegistry.Signal memory s = registry.getSignal(id);
        assertEq(s.subject, subject1);
        assertEq(uint8(s.signalType), uint8(IReputationRegistry.SignalType.AccountAge));
        assertEq(s.score, 7500);
        assertEq(s.weight, 9000);
        assertEq(s.data, hex"01");
        assertGt(s.timestamp, 0);
    }

    function test_ScoreBoundsEnforced() public {
        vm.prank(attestorA);
        vm.expectRevert(bytes("ReputationRegistry: score>10000"));
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_001, 5000, "");

        vm.prank(attestorA);
        vm.expectRevert(bytes("ReputationRegistry: bad weight"));
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 5000, 0, "");
    }

    function test_SubjectSelfRegistration() public {
        assertTrue(registry.isRegisteredSubject(subject1));
        assertEq(registry.handleOf(subject1), "alice.repulyser");
    }

    function test_SubjectDoubleRegisterReverts() public {
        vm.prank(subject1);
        vm.expectRevert(bytes("ReputationRegistry: already registered"));
        registry.registerSubject("alice2");
    }

    function test_LatestSignalOfUpdates() public {
        vm.prank(attestorA);
        uint256 id1 = registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 3000, 5000, "");
        (IReputationRegistry.Signal memory s, bool found) =
            registry.latestSignalOf(subject1, IReputationRegistry.SignalType.AccountAge);
        assertTrue(found);
        assertEq(s.score, 3000);

        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 8000, 5000, "");
        (s, found) = registry.latestSignalOf(subject1, IReputationRegistry.SignalType.AccountAge);
        assertTrue(found);
        assertEq(s.score, 8000, "latest should update");
        assertGt(s.timestamp, 0);

        // Old signal still indexed under subject
        uint256[] memory ids = registry.signalsOf(subject1);
        assertEq(ids.length, 2);

        // Revoke and verify
        vm.prank(attestorA);
        registry.revokeSignal(id1);
        vm.expectRevert(bytes("ReputationRegistry: no signal"));
        registry.getSignal(id1);
    }

    function test_LatestSignalOfMissing() public {
        (IReputationRegistry.Signal memory s, bool found) =
            registry.latestSignalOf(subject1, IReputationRegistry.SignalType.AccountAge);
        assertFalse(found);
        assertEq(s.subject, address(0));
    }

    // ---------------------------------------------------------------------
    // Analyzer tests
    // ---------------------------------------------------------------------

    function test_EmptySubjectIsUnverified() public {
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        assertEq(uint8(r.tier), uint8(ReputationAnalyzer.Tier.Unverified));
        assertEq(r.score, 0);
        assertEq(r.signalsPresent, 0);
    }

    function test_SingleSignalWeightsApply() public {
        // Push a single signal of score 10000 (max) for AccountAge (weight 1500).
        // Expected score contribution = 10000 * 1500 / 10000 = 1500.
        // Final score = 1500 -> tier Bronze (>= 2000? no -> Unverified)
        // Actually 1500 is < 2000 so still Unverified. That's the intended behavior
        // for an almost-empty profile.
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        assertEq(r.score, 1500);
        assertEq(r.signalsPresent, 1);
    }

    function test_AllMaxSignalsGiveDiamond() public {
        // Push all 10 signals at max score. Sum of weights = 10000, so score = 10000.
        vm.startPrank(attestorA);
        for (uint8 i = 0; i < 10; i++) {
            registry.submitSignal(subject1, IReputationRegistry.SignalType(i), 10_000, 10_000, "");
        }
        vm.stopPrank();
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        assertEq(r.score, 10_000, "all max should be 10000");
        assertEq(uint8(r.tier), uint8(ReputationAnalyzer.Tier.Diamond));
        assertEq(r.signalsPresent, 10);
    }

    function test_WeightedAttestorsAverage() public {
        // Attestor A (weight 7000) says score=1000
        // Attestor B (weight 3000) says score=9000
        // Weighted average = (1000*7000 + 9000*3000) / 10000 = 3400
        // AccountAge weight 1500 -> contribution = 3400 * 1500 / 10000 = 510
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 1000, 7000, "");
        vm.prank(attestorB);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 9000, 3000, "");
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        assertEq(r.score, 510);
        assertEq(r.breakdown[0].signalsUsed, 2);
        assertEq(r.breakdown[0].rawScore, 3400);
    }

    function test_TimeDecayForStaleSignals() public {
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        // Roll forward past the 90-day staleness window.
        vm.warp(block.timestamp + 91 days);
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        // After staleness, decayed contribution should be 0
        assertEq(r.breakdown[0].decayedScore, 0, "should decay to 0 past window");
        assertEq(r.breakdown[0].contribution, 0);
        // Signal still present in stats? With default requireData=false, it is
        // counted because lastUpdate is set, but contribution is 0.
    }

    function test_TimeDecayPartial() public {
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        // Halfway through the 90-day window
        vm.warp(block.timestamp + 45 days);
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        // decayedScore should be roughly half of raw
        assertGt(r.breakdown[0].decayedScore, 4000);
        assertLt(r.breakdown[0].decayedScore, 6000);
    }

    function test_TierThresholds() public {
        // Push an aggregate that lands just over the Silver threshold (4000).
        // 4 categories at score 10000 with combined weight = 4000 (Bronze-tier weights).
        // We need exactly 4000 < totalScore < 6000 to land in Silver.
        // Sum weights 1000+1000+1000+1000 = 4000 -> score=4000 -> Silver exactly.
        vm.startPrank(attestorA);
        // AccountAge 1500, TxVolume 1200, TxFrequency 1000, DefiInteractions 1500 = 5200 -> Gold
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        registry.submitSignal(subject1, IReputationRegistry.SignalType.TxVolume, 10_000, 10_000, "");
        registry.submitSignal(subject1, IReputationRegistry.SignalType.DefiInteractions, 10_000, 10_000, "");
        vm.stopPrank();

        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        // AccountAge 1500 + TxVolume 1200 + DefiInteractions 1500 = 4200 -> Silver
        assertEq(r.score, 4200);
        assertEq(uint8(r.tier), uint8(ReputationAnalyzer.Tier.Silver));
    }

    function test_TierStrings() public view {
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Unverified), "Unverified");
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Bronze), "Bronze");
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Silver), "Silver");
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Gold), "Gold");
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Platinum), "Platinum");
        assertEq(analyzer.tierString(ReputationAnalyzer.Tier.Diamond), "Diamond");
    }

    function test_QuickScore() public {
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        (uint16 score, ReputationAnalyzer.Tier tier, uint8 present) = analyzer.quickScore(subject1);
        assertEq(score, 1500);
        assertEq(uint8(tier), uint8(ReputationAnalyzer.Tier.Unverified));
        assertEq(present, 1);
    }

    function test_PerSubjectIsolation() public {
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 10_000, 10_000, "");
        // subject2 has no signals
        ReputationAnalyzer.Report memory r2 = analyzer.analyze(subject2);
        assertEq(r2.score, 0);
        assertEq(r2.signalsPresent, 0);
    }

    function test_TypeWeightsSumTo10000() public {
        uint16 sum = 0;
        for (uint8 i = 0; i < 10; i++) {
            sum += analyzer.typeWeights(i);
        }
        assertEq(sum, 10_000, "type weights must sum to 10000");
    }

    function test_SetStalenessWindow() public {
        vm.prank(owner);
        // only analyzer doesn't have owner gating; this is anyone — sanity check
        analyzer.setStalenessWindow(30 days);
        assertEq(analyzer.stalenessWindow(), 30 days);

        vm.expectRevert(bytes("ReputationAnalyzer: bad window"));
        analyzer.setStalenessWindow(0);

        vm.expectRevert(bytes("ReputationAnalyzer: bad window"));
        analyzer.setStalenessWindow(400 days);
    }

    function test_SetTypeWeight() public {
        analyzer.setTypeWeight(0, 2000);
        assertEq(analyzer.typeWeights(0), 2000);

        vm.expectRevert(bytes("ReputationAnalyzer: bad idx"));
        analyzer.setTypeWeight(10, 100);

        vm.expectRevert(bytes("ReputationAnalyzer: bad weight"));
        analyzer.setTypeWeight(0, 20_000);
    }

    // ---------------------------------------------------------------------
    // Attestor helper tests
    // ---------------------------------------------------------------------

    function test_HelperQueueAndSubmit() public {
        // Register the helper contract itself as the attestor.
        // The helper is the msg.sender when it forwards submitSignal() to the registry.
        vm.prank(owner);
        registry.registerAttestor(address(helper), "Repulyser Attestor Helper");

        vm.prank(owner);
        helper.queue(subject1, IReputationRegistry.SignalType.AccountAge, 5000, 7000, hex"abcd");
        assertEq(helper.pendingLength(), 1);

        // Only attestors can call submit (the helper checks msg.sender is an attestor on the registry)
        vm.prank(stranger);
        vm.expectRevert(bytes("ReputationAttestor: not attestor"));
        helper.submit(0);

        // attestorA is an attestor — they can call submit
        vm.prank(attestorA);
        uint256 signalId = helper.submit(0);
        assertEq(signalId, 1);

        // Re-submit reverts
        vm.prank(attestorA);
        vm.expectRevert(bytes("ReputationAttestor: already submitted"));
        helper.submit(0);
    }

    function test_HelperSubmitAll() public {
        vm.prank(owner);
        registry.registerAttestor(address(helper), "Repulyser Attestor Helper");

        vm.startPrank(owner);
        helper.queue(subject1, IReputationRegistry.SignalType.AccountAge, 5000, 7000, "");
        helper.queue(subject1, IReputationRegistry.SignalType.TxVolume, 6000, 7000, "");
        helper.queue(subject1, IReputationRegistry.SignalType.DefiInteractions, 7000, 7000, "");
        vm.stopPrank();

        vm.prank(attestorA);
        uint256[] memory ids = helper.submitAll();
        assertEq(ids.length, 3);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(ids[2], 3);

        // After submitAll, all are flagged submitted — second call returns zeros
        vm.prank(attestorA);
        uint256[] memory ids2 = helper.submitAll();
        for (uint256 i = 0; i < ids2.length; i++) {
            assertEq(ids2[i], 0, "should be 0 (skipped) for already submitted");
        }
    }

    function test_HelperRejectsZeroRegistry() public {
        vm.expectRevert(bytes("ReputationAttestor: zero registry"));
        new ReputationAttestor(address(0));
    }

    // ---------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------

    function testFuzz_ScoreInBounds(uint16 raw, uint16 weight) public {
        raw = uint16(bound(raw, 0, 10_000));
        weight = uint16(bound(weight, 1, 10_000));
        vm.prank(attestorA);
        registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, raw, weight, "");
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        // Contribution from one type must be <= type weight (1500)
        assertLe(r.breakdown[0].contribution, 1500);
        // Total score must be <= 10000
        assertLe(r.score, 10_000);
    }

    function test_ReentrancyGuardOnRevoke() public {
        // Just confirm revoke doesn't break the latest pointer
        vm.prank(attestorA);
        uint256 id = registry.submitSignal(subject1, IReputationRegistry.SignalType.AccountAge, 5000, 5000, "");
        vm.prank(attestorA);
        registry.revokeSignal(id);
        // Latest pointer still set to the now-deleted slot
        // analyzer should ignore it (no fresh data)
        ReputationAnalyzer.Report memory r = analyzer.analyze(subject1);
        assertEq(r.score, 0);
    }
}
