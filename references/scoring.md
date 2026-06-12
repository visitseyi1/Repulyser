# Scoring model

Repulyser returns a single composite score for a subject in `[0, 10000]` (interpret as percent × 100) plus a tier and a per-signal-type breakdown. The model is intentionally simple, fully onchain, and easy to reason about.

## Pipeline

```
                                  ┌────────────────────────────┐
                                  │ ReputationRegistry         │
                                  │  Signal{subject, type,     │
                                  │   score, weight, ts, data} │
                                  └────────────┬───────────────┘
                                               │ signalsOf(subject)
                                               ▼
       ┌──────────────────────────────────────────────────────────────────┐
       │ Per-type aggregator                                              │
       │   for each type t in [0..10):                                    │
       │     - filter signals to fresh ones (age < stalenessWindow)       │
       │     - weightedAvg(t) = Σ(signal.score * signal.weight) /         │
       │                         Σ(signal.weight)                          │
       │     - decayed(t) = weightedAvg(t) * (window - age) / window      │
       │     - contribution(t) = decayed(t) * typeWeight(t) / 10000       │
       └──────────────────────────────────────────────────────────────────┘
                                               │
                                               ▼
       ┌──────────────────────────────────────────────────────────────────┐
       │ score = Σ contribution(t)       (0..10000)                        │
       │ tier  = _tierOf(score)                                             │
       │ present = count of types with weightSum[t] > 0                   │
       └──────────────────────────────────────────────────────────────────┘
```

## Type weights (default, in basis points; sum = 10000)

| Index | Type | Weight | Rationale |
|---|---|---|---|
| 0 | AccountAge | 1500 | Older wallets with clean histories are stronger signals |
| 1 | TxVolume | 1200 | Direct measure of capital put at risk |
| 2 | TxFrequency | 1000 | Active wallets are easier to reason about |
| 3 | DefiInteractions | 1500 | Sophistication: how many protocols the user has touched |
| 4 | GovernanceVotes | 1500 | Civic participation is hard to fake |
| 5 | NftHoldings | 600 | Vanity, low signal |
| 6 | SocialEndorsements | 400 | Sybil-prone; weighted low |
| 7 | ContractDeploys | 800 | Indicates builder activity |
| 8 | AssetDiversity | 800 | Diversified portfolio, lower concentration risk |
| 9 | LiquidStaking | 700 | Long-term alignment with the chain |

To change weights, call `ReputationAnalyzer.setTypeWeight(idx, weight)` from any address. The analyzer does not gate this; the assumption is that the analyzer is controlled by the same operator as the registry.

## Staleness window

Default 90 days. A signal with `age >= window` contributes 0 to the score (but is still recorded in `lastUpdate` and `signalsUsed`). Linear decay between `age=0` and `age=window`.

## Tier thresholds

| Score range | Tier |
|---|---|
| `0..1999` | Unverified |
| `2000..3999` | Bronze |
| `4000..5999` | Silver |
| `6000..7999` | Gold |
| `8000..9499` | Platinum |
| `9500..10000` | Diamond |

## Worked example

Subject has two attestors:

- `attestorA` (weight 7000) says `AccountAge` score = `1000`
- `attestorB` (weight 3000) says `AccountAge` score = `9000`

Weighted average: `(1000 * 7000 + 9000 * 3000) / 10000 = 3400`.
AccountAge type weight: 1500.
Contribution: `3400 * 1500 / 10000 = 510`.

If `AccountAge` is the only type with data and the signal is fresh, the final score is `510` → `Unverified` (below 2000).

If the same subject also has max-score (10000) signals for `TxVolume` (1200) and `DefiInteractions` (1500), the contributions are `1200` and `1500` respectively. Total score = `510 + 1200 + 1500 = 3210` → `Bronze`.

## Trust model

- The registry owner can add or revoke attestors at will. Choose a trustworthy owner (multisig, DAO, or a single operator with a public reputation).
- Attestors can write any score in `[0, 10000]` for any subject. The model assumes at least one well-behaved attestor per dimension. If a single attestor controls all writes, scores are meaningless.
- The analyzer is read-only and trusts the registry. Anyone can deploy a parallel analyzer with custom weights.

## Limitations and what the score does NOT tell you

- **Not an identity claim.** "Diamond" does not mean the address is owned by a real human; it means the address has accumulated a lot of the onchain behaviours we weight positively.
- **No privacy.** Signals are public. Subjects can read which attestors said what about them.
- **Front-running on attestor weight.** An attacker who controls an attestor can submit conflicting signals to skew a subject's score. Use a quorum model (multiple independent attestors per dimension) in production.
- **Stale-by-default.** If you stop updating signals, scores decay to 0 over `stalenessWindow`. Operate the attestor bots on a schedule.
