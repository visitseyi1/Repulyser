// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ReputationRegistry, IReputationRegistry} from "../src/ReputationRegistry.sol";
import {ReputationAnalyzer} from "../src/ReputationAnalyzer.sol";
import {ReputationAttestor} from "../src/ReputationAttestor.sol";

/// @title DeployRepulyser
/// @notice One-shot deployment script for the Repulyser stack:
///         1. ReputationRegistry
///         2. ReputationAnalyzer (bound to the registry)
///         3. ReputationAttestor helper (bound to the registry)
/// @dev Usage:
///         forge script script/DeployRepulyser.s.sol:DeployRepulyser \
///           --rpc-url $RPC_URL \
///           --private-key $PRIVATE_KEY \
///           --broadcast
contract DeployRepulyser is Script {
    function run() external {
        // Optional env-driven bootstrap: deployer becomes the first attestor
        // and pre-queues demo signals for itself. Set DEMO=1 to enable.
        bool demo = vm.envOr("DEMO", false);
        address deployer = msg.sender;

        vm.startBroadcast();

        ReputationRegistry registry = new ReputationRegistry();
        console.log("ReputationRegistry deployed at:", address(registry));

        ReputationAnalyzer analyzer = new ReputationAnalyzer(address(registry));
        console.log("ReputationAnalyzer deployed at:", address(analyzer));

        ReputationAttestor helper = new ReputationAttestor(address(registry));
        console.log("ReputationAttestor deployed at:", address(helper));

        if (demo) {
            // Register the deployer as the first attestor with a friendly name
            // and self-register a subject handle. This is enough to immediately
            // push some signals and call analyzer.analyze(deployer).
            registry.registerAttestor(deployer, "Repulyser Demo Attestor");
            registry.registerSubject("demo.repulyser");

            // Push a balanced "all categories" sample for the deployer.
            bytes memory empty = "";
            registry.submitSignal(deployer, IReputationRegistry.SignalType.AccountAge, 6500, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.TxVolume, 7200, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.TxFrequency, 5400, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.DefiInteractions, 4800, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.GovernanceVotes, 3500, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.NftHoldings, 2200, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.SocialEndorsements, 1800, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.ContractDeploys, 6000, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.AssetDiversity, 4700, 8000, empty);
            registry.submitSignal(deployer, IReputationRegistry.SignalType.LiquidStaking, 3000, 8000, empty);

            console.log("Demo mode: 10 signals submitted for deployer", deployer);
        }

        vm.stopBroadcast();
    }
}
