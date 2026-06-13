# Repulyser

**An onchain reputation analyzer for EVM chains, built with Foundry.**

Repulyser ships three Solidity contracts — `ReputationRegistry`, `ReputationAnalyzer`, and `ReputationAttestor` — that together let any AI agent answer the question *"what is the reputation of `0x...`?"* with a single `cast call`. The analyzer returns a composite `0..10000` score, a tier (Unverified → Bronze → Silver → Gold → Platinum → Diamond), and a per-signal-type breakdown across 10 dimensions: account age, tx volume, tx frequency, DeFi interactions, governance votes, NFT holdings, social endorsements, contract deploys, asset diversity, and liquid staking. Scores are attestor-weighted and decay linearly over a configurable staleness window (default 90 days).

Built strictly with Foundry (`forge` / `cast`). No Python, no JavaScript, no off-chain indexer.

---

## Why this exists

Most onchain tooling answers *what did this address do?* Repulyser answers *should I trust this address?*

The system has three pieces:

- **ReputationRegistry** — append-only signal storage. Approved attestors (bots, DAOs, multisigs) write normalized 0..10000 signals about any address.
- **ReputationAnalyzer** — pure view-only scoring. Consumes signals, applies attestor-weighted averaging and time decay, returns a composite score, tier, and breakdown.
- **ReputationAttestor** — a small helper contract that lets an attestor bot queue dozens of signals in memory and flush them in a single `forge script` transaction.

The result: an agent can say *"Wallet `0xAbc…` is Silver-tier with strong DeFi interactions but no governance history"* from one tuple.

---

## Layout

```
.
├── SKILL.md                 # AI-agent skill manifest
├── foundry.toml             # Foundry config (solc 0.8.24, via-ir, optimizer)
├── remappings.txt
├── src/
│   ├── IReputationRegistry.sol   # Interface
│   ├── ReputationRegistry.sol    # Signal storage + attestor management
│   ├── ReputationAnalyzer.sol    # View-only composite scoring + tier
│   └── ReputationAttestor.sol    # Batch helper for attestors
├── script/
│   ├── DeployRepulyser.s.sol     # One-shot deploy (3 contracts)
│   └── AnalyzeReputation.s.sol   # Pretty-print a reputation report
├── test/
│   └── Repulyser.t.sol           # 29 tests covering registry, helper, analyzer
├── references/                   # Skill reference docs the agent reads
│   ├── deploy.md
│   ├── analyze.md
│   ├── registry.md
│   ├── helper.md
│   └── scoring.md
└── assets/
    ├── networks.json             # Example RPC + chain IDs
    ├── deployments.example.json  # Template for tracking deployed addresses
    ├── scoring.example.json      # Type weights + tier thresholds
    ├── signal-types.json         # Enum + per-signal-type scoring hints
    └── templates/
        └── template_analyze.sh.tpl
```

---

## Quick start

### 1. Install Foundry (one-time)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
cast --version
```

### 2. Clone and build

```bash
git clone https://github.com/visitseyi1/Repulyser.git
cd Repulyser
forge build
forge test   # 29 tests, all green
```

### 3. Deploy to your chain of choice

Repulyser is chain-agnostic. `assets/networks.json` ships with example entries — edit it for your RPC, or pass `--rpc-url` directly:

```bash
export PRIVATE_KEY=0xyour...
forge script script/DeployRepulyser.s.sol:DeployRepulyser \
  --rpc-url $YOUR_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Copy the printed `ReputationRegistry`, `ReputationAnalyzer`, and `ReputationAttestor` addresses into `assets/deployments.json` and commit.

Set `DEMO=1` to also register the deployer as the first attestor and submit 10 demo signals. Useful for end-to-end smoke testing after deploy.

### 4. Query a wallet

```bash
SUBJECT=0xYourTarget
ANALYZER=0x...   # from the deploy output

# Quick: score + tier + coverage
cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" $SUBJECT --rpc-url $YOUR_RPC_URL

# Tier as a string
cast call $ANALYZER "tierString(uint8)(string)" 2 --rpc-url $YOUR_RPC_URL
# "Silver"

# Full breakdown
SUBJECT=$SUBJECT ANALYZER=$ANALYZER \
  forge script script/AnalyzeReputation.s.sol:AnalyzeReputation
```

Or use the bundled shell template:

```bash
SUBJECT=0xYourTarget bash assets/templates/template_analyze.sh.tpl
```

### 5. Push signals (attestor path)

```bash
# One-time: registry owner registers the bot as an attestor
cast send $REGISTRY "registerAttestor(address,string)" $BOT "Repulyser Bot" \
  --rpc-url $YOUR_RPC_URL --private-key $PRIVATE_KEY

# Then the bot can submit signals
cast send $REGISTRY "submitSignal(address,uint8,uint16,uint16,bytes)" \
  0xSubject 0 6500 8000 0x \
  --rpc-url $YOUR_RPC_URL --private-key $PRIVATE_KEY
```

See `references/registry.md` and `references/helper.md` for the full write flow including the batch helper.

---

## Scoring model (TL;DR)

- **10 signal types** with fixed weights (in basis points, sum = 10000):
  - AccountAge, TxVolume, TxFrequency, DefiInteractions, GovernanceVotes (1500 / 1200 / 1000 / 1500 / 1500)
  - NftHoldings, SocialEndorsements, ContractDeploys, AssetDiversity, LiquidStaking (600 / 400 / 800 / 800 / 700)
- For each type, the analyzer takes the **attestor-weighted average** of the latest fresh signals.
- Applies **linear time decay** over the staleness window (default 90 days): full credit at `age=0`, zero at `age≥window`.
- **Final score** = Σ(decayed × typeWeight) / 10000, in `[0, 10000]`.
- **Tier** thresholds: Bronze 20, Silver 40, Gold 60, Platinum 80, Diamond 95 (in percent).

See `references/scoring.md` for the full breakdown and a worked example.

---

## Tests

```
$ forge test
Ran 29 tests for test/Repulyser.t.sol:RepulyserTest
[PASS] testFuzz_ScoreInBounds(uint16,uint16) (runs: 256, μ: 200332, ~: 200244)
[PASS] test_AllMaxSignalsGiveDiamond()
[PASS] test_AttestorRegistration()
[PASS] test_AttestorSubmitsSignal()
[PASS] test_EmptySubjectIsUnverified()
[PASS] test_HelperQueueAndSubmit()
[PASS] test_HelperRejectsZeroRegistry()
[PASS] test_HelperSubmitAll()
[PASS] test_LatestSignalOfMissing()
[PASS] test_LatestSignalOfUpdates()
[PASS] test_OnlyOwnerCanRegisterAttestor()
[PASS] test_OwnerIsDeployer()
[PASS] test_PerSubjectIsolation()
[PASS] test_QuickScore()
[PASS] test_ReentrancyGuardOnRevoke()
[PASS] test_RevokeAttestor()
[PASS] test_ScoreBoundsEnforced()
[PASS] test_SetStalenessWindow()
[PASS] test_SetTypeWeight()
[PASS] test_SingleSignalWeightsApply()
[PASS] test_StrangerCannotSubmitSignal()
[PASS] test_SubjectDoubleRegisterReverts()
[PASS] test_SubjectSelfRegistration()
[PASS] test_TierStrings()
[PASS] test_TierThresholds()
[PASS] test_TimeDecayForStaleSignals()
[PASS] test_TimeDecayPartial()
[PASS] test_TypeWeightsSumTo10000()
[PASS] test_WeightedAttestorsAverage()
Suite result: ok. 29 passed; 0 failed; 0 skipped
```

Covers:
- **Registry**: owner gating, attestor management, subject self-registration, signal bounds, revoke flow, latest-pointer semantics, edge cases on missing/deleted signals.
- **Analyzer**: empty subjects, single signal, full-max (Diamond), attestor-weighted averaging, time decay (full and partial), tier thresholds, per-subject isolation, type-weight sum invariant, configuration setters.
- **Attestor helper**: queue, single submit, batch submitAll, double-submit reverts, non-attestor rejection.
- **Fuzz**: random score/weight inputs stay in `[0, 10000]`.

---

## License

MIT. See [`LICENSE`](./LICENSE).
