---
name: repulyser
description: >
  Use for any "reputation", "trust score", "credibility", or "analyze wallet"
  task on an EVM chain. This skill ships an onchain ReputationRegistry +
  ReputationAnalyzer pair: attestors write normalized 0–10000 signals across
  10 dimensions (account age, tx volume, DeFi, governance, NFTs, social,
  contract deploys, asset diversity, liquid staking, tx frequency), and the
  analyzer returns a composite score, tier (Unverified→Diamond), and per-type
  breakdown. Reads are pure `cast call`; writes use `forge script` and the
  deployer key. Built strictly with Foundry (forge / cast) — no Python, no
  JavaScript, no off-chain indexer required.
version: 0.1.0
requires:
  anyBins:
  - forge
  - cast
---

# Repulyser — Onchain Reputation Analyzer

A read-friendly, write-friendly onchain reputation stack for EVM chains. Drop the three contracts (`ReputationRegistry`, `ReputationAnalyzer`, `ReputationAttestor`) into any EVM environment, point the skill at the deployed addresses, and the agent can answer "what is the reputation of `0x...`" with a single `cast call`.

The system is intentionally minimal so that an AI agent — given only this `SKILL.md` and the `assets/` + `references/` bundle — can:

- deploy the stack in one `forge script` call,
- register attestors and queue signals,
- generate a tiered reputation report (`analyze(subject)`) via `cast call` or via the bundled `forge script`,
- reason about the report in natural language.

## Prerequisites

1. **Foundry is installed and `cast` / `forge` are on `PATH`.** If not:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   cast --version
   ```
2. **RPC endpoint** is configured in `assets/networks.json` (or passed as `--rpc-url` directly). The file is a generic config — replace the example entries with your chain's RPC, chain ID, and explorer URL.
3. **A `$PRIVATE_KEY` env var** is required only for write operations (deploy, register attestor, submit signal). Read-only `cast call` queries need no key.

## Network Configuration

`assets/networks.json` is the canonical network config. It uses a simple `{ networks: [...], defaultNetwork: "..." }` shape so the agent can switch with `jq`:

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="<your-network>") | .rpcUrl' assets/networks.json)
```

Pick the network you want, or add your own entry.

## Capability Index

| User Need | Skill Capability | Reference |
|---|---|---|
| "Deploy the reputation stack" | One-shot forge script: registry + analyzer + helper | → `references/deploy.md` |
| "What is the reputation of `0xabc...`?" | `cast call analyzer "analyze(address)"` | → `references/analyze.md` |
| "Just give me the score and tier" | `cast call analyzer "quickScore(address)"` | → `references/analyze.md#quickscore` |
| "Register a new attestor" | `cast send registry "registerAttestor(...)"` | → `references/registry.md#attestor-management` |
| "Push a signal for `0xabc...`" | `cast send registry "submitSignal(...)"` | → `references/registry.md#submit-signal` |
| "Batch-push a set of signals" | Use `ReputationAttestor` helper via `cast send` or `forge script` | → `references/helper.md` |
| "Run the analyzer in a forge script and pretty-print" | `script/AnalyzeReputation.s.sol` | → `references/analyze.md#forge-script` |
| "Understand the scoring model" | Read `references/scoring.md` | — |
| "Verify the analyzer on-chain" | `forge verify-contract` | → `references/deploy.md#verify` |

## High-level agent flow

Whenever a user asks anything about a wallet's reputation, follow this flow:

1. **Identify the network** the user wants. Read `assets/networks.json` (or ask).
2. **Resolve the deployed contract addresses**:
   - If the user provided them, use those.
   - Otherwise, look them up from `assets/deployments.json` if present, OR ask the user to deploy first via `references/deploy.md`.
3. **For read-only requests** (e.g. "analyze 0x..."), use `cast call`. See `references/analyze.md`.
4. **For write requests** (e.g. "register me as an attestor"), complete the standard pre-checks:
   - Confirm `$PRIVATE_KEY` is set.
   - Derive `cast wallet address --private-key $PRIVATE_KEY` and show the user.
   - Confirm the target network (testnet vs mainnet warning).
5. **For batch / scripted writes** (e.g. "score and submit 50 wallets"), prefer the `ReputationAttestor` helper, queue everything, then `submitAll` in one tx.

## General Error Handling

| Error Signature | Cause | Action |
|---|---|---|
| `ReputationRegistry: not attestor` | Caller is not a registered attestor | Prompt the user to register via the owner first |
| `ReputationRegistry: not owner` | Only owner can manage attestors | Inform the user they need the owner key |
| `ReputationRegistry: score>10000` / `bad weight` | Out-of-range signal | Reject input; both must be in `[0,10000]` |
| `ReputationAnalyzer: bad window` | Staleness window outside `[1d, 365d]` | Re-prompt with valid range |
| `ReputationRegistry: no signal` | Reading a non-existent or revoked signal id | Skip silently; treat as "no data" |
| `execution reverted` from analyzer | Either input error or analyzer misconfigured | Decode revert reason from `cast` stderr |

## Security Reminders

- **Private key**: never echoed into chat; always read from `$PRIVATE_KEY`.
- **Network confirmation**: always state "target = <network>" before writes.
- **Trust model**: the registry's owner is fully trusted to add/revoke attestors. For production deployments, consider deploying via a multisig and adding a timelock on `registerAttestor`.
- **Score interpretation**: a "Diamond" score does NOT mean the address is safe to transact with — it is a heuristic of historical onchain behaviour. Always combine with the user's own risk checks.

## Scoring Model (TL;DR)

- 10 signal types with fixed weights summing to 10000 bps (see `references/scoring.md`).
- For each type, the latest fresh signal per attestor is attestor-weighted-averaged.
- Time decay: linear from 100% at `age=0` to 0% at `age=stalenessWindow` (default 90 days).
- Score = Σ( decayedTypeScore × typeWeight ) / 10000, in `[0, 10000]` (interpret as percent × 100).
- Tier thresholds: Bronze ≥ 20, Silver ≥ 40, Gold ≥ 60, Platinum ≥ 80, Diamond ≥ 95.
- An address with zero signals = `Unverified`, score 0.

See `references/scoring.md` for the full table and worked example.
