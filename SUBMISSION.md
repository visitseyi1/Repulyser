# Pharos Agent Center — Skill Builder Campaign Submission

> Copy the **Submission message** section into one message in the
> `#skill-submission` channel of the Pharos Discord
> (https://discord.com/invite/pharos). The campaign runs 25 May 2026 –
> 8 June 2026 with winners announced 15 June 2026.

---

## Skill name

**Repulyser — Onchain Reputation Analyzer**

## Short description

Repulyser is an onchain reputation analyzer for Pharos. It ships three Foundry-built contracts (ReputationRegistry + ReputationAnalyzer + ReputationAttestor) that let any AI agent answer *"what is the reputation of `0x…`?"* with a single `cast call`. The analyzer returns a composite 0..10000 score, a tier (Unverified → Bronze → Silver → Gold → Platinum → Diamond), and a per-signal-type breakdown across 10 dimensions (account age, tx volume, tx frequency, DeFi interactions, governance votes, NFT holdings, social endorsements, contract deploys, asset diversity, liquid staking). The score applies attestor-weighted averaging and linear time decay over a configurable staleness window (default 90 days).

## GitHub link

https://github.com/visitseyi1/Repulyser

## Email

`visitseyi1 [at] users.noreply.github.com` (use the GitHub-registered email associated with the repo owner)

## Demo

A live Atlantic testnet deployment is pending. For syntax / unit-test proof, the repository ships 29 passing Foundry tests (`forge test`) covering the registry, the helper, the analyzer, and the tier / decay logic. A runnable end-to-end demo is also possible locally:

```bash
git clone https://github.com/visitseyi1/Repulyser
cd Repulyser
forge build
forge test -vv            # 29 passing tests
DEMO=1 PRIVATE_KEY=0x... forge script script/DeployRepulyser.s.sol:DeployRepulyser \
  --rpc-url https://atlantic.dplabs-internal.com --broadcast
# Then:
SUBJECT=0xYourAddress ANALYZER=0x... forge script script/AnalyzeReputation.s.sol:AnalyzeReputation
```

## How to use

1. **Install Foundry** (one-time, mandatory): `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. **Deploy the stack** to Atlantic testnet or Pharos mainnet:
   ```bash
   PRIVATE_KEY=0x... forge script script/DeployRepulyser.s.sol:DeployRepulyser \
     --rpc-url <rpc> --broadcast
   ```
3. **Save the three addresses** (registry, analyzer, helper) to `assets/deployments.json`.
4. **(Optional) verify** on the block explorer with `forge verify-contract` (see `references/deploy.md`).
5. **Read a reputation** for any address (no key required):
   ```bash
   cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" 0xYourTarget --rpc-url <rpc>
   cast call $ANALYZER "tierString(uint8)(string)" 2 --rpc-url <rpc>  # → "Silver"
   ```
6. **Push signals** (attestor path): the registry owner registers a bot as an attestor once via `registerAttestor(bot, "name")`. The bot then calls `submitSignal(subject, type, score, weight, data)` per signal, or uses the bundled `ReputationAttestor` helper to queue dozens of signals and flush them in one transaction via `submitAll()`.

Full usage walkthrough is in `SKILL.md` and `references/`.

## Supported frameworks

- Foundry (`forge`, `cast`) — the only required toolchain.
- Tested with `forge 1.7.1` / `solc 0.8.24` (via-ir pipeline).
- Compatible with any framework that can shell out to `cast` / run a `forge script`:
  - OpenClaw, Claude Code, Codex, and the rest of the Agent Center's supported frameworks.
  - Plain `bash` for the bundled `assets/templates/template_analyze.sh.tpl`.

## Dependencies

- **Foundry** (`cast` and `forge` on `PATH`).
- **forge-std** (vendored via `lib/forge-std`, included as a git submodule).
- No npm, no Python, no off-chain indexer, no external API.

## Notes

- The trust model: the registry owner is fully trusted to add/revoke attestors. For a production deployment, use a multisig and consider adding a timelock to `registerAttestor`.
- The analyzer is intentionally read-only and stateless — anyone can deploy a parallel analyzer with custom weights against the same registry.
- 100% of the scoring math lives in `ReputationAnalyzer.analyze(subject)` and is fully reproducible from onchain state; no off-chain computation is hidden.
- 29 unit tests cover happy paths, edge cases, fuzz bounds, and the time-decay math.
- All write operations follow the standard Agent Center pre-check flow: confirm private key is set, derive the public address, show the user the target network, and only proceed after acknowledgement.
