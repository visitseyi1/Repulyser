# Analyze (read-only)

> **Network configuration**: read `<rpc>` and `<explorer_url>` from `assets/networks.json`. The analyzer address comes from `assets/deployments.json` (or from a user-supplied override).

## Read the analyzer address

```bash
ANALYZER=$(jq -r '.atlantic-testnet.analyzer' assets/deployments.json)
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
EXPLORER_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .explorerUrl' assets/networks.json)
```

## Full report (signature: `analyze(address)`)

```bash
SUBJECT=0xYourTargetAddress
cast call $ANALYZER "analyze(address)((address,uint16,uint8,uint8,uint8,uint64,(uint8,uint16,uint16,uint16,uint16,uint64,uint16)[10]))" \
  $SUBJECT --rpc-url $RPC_URL
```

This is one fat tuple. If `cast` has trouble decoding the full breakdown, use the two-step calls below.

## `quickScore` — score, tier, coverage only

```bash
cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" $SUBJECT --rpc-url $RPC_URL
```

Output:

- `uint16 score` (0..10000, i.e. percent × 100)
- `uint8 tier` (0=Unverified, 1=Bronze, 2=Silver, 3=Gold, 4=Platinum, 5=Diamond)
- `uint8 signalsPresent` (how many of 10 dimensions have fresh data)

Convert tier to string with `cast call $ANALYZER "tierString(uint8)(string)" <tier>`.

## `tierString`

```bash
TIER_NUM=$(cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" $SUBJECT --rpc-url $RPC_URL | sed -n '2p')
cast call $ANALYZER "tierString(uint8)(string)" $TIER_NUM --rpc-url $RPC_URL
```

## Forge script: pretty-print

When the user wants a human-readable breakdown, use the bundled `script/AnalyzeReputation.s.sol`:

```bash
SUBJECT=0xYourTargetAddress ANALYZER=$ANALYZER \
  forge script script/AnalyzeReputation.s.sol:AnalyzeReputation
```

Output:

```
=== Repulyser Report ===
Subject:           0x...
Score (0-10000):   4200
Score (percent):   42
Tier:              Silver
Signals present:   3 / 10
Generated at:      1718198400
Breakdown:
  type: 0
    raw: 6500
    decayed: 6500
    weight: 1500
    contribution: 975
    lastUpdate: 1718190000
    used: 1
  ...
```

## Agent display template

When asked "what is the reputation of `0xabc`?", the agent should:

1. Run `quickScore` and `tierString` first — they are cheap.
2. If the user wants the breakdown, call `analyze` and decode the tuple.
3. Render an explorer link to the subject's address: `<explorer_url>/address/<subject>`.
4. Always show:
   - Score in **percent** (`score / 100` with two decimals) and in raw bps.
   - Tier as a string ("Silver") not a number.
   - Coverage (`signalsPresent/10`) so the user knows how much data underlies the score.
   - The block explorer link.
5. Briefly remind the user that score is a heuristic of historical onchain behaviour, not a safety guarantee.

## Worked example (no on-chain deploy needed for syntax reference)

```bash
# Score 4200 / 10000 = 42% → Silver (4000-6000)
cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" 0xAbc... --rpc-url $RPC_URL
# 4200
# 2
# 3
cast call $ANALYZER "tierString(uint8)(string)" 2 --rpc-url $RPC_URL
# "Silver"
```

## Error handling

| Error | Cause | Action |
|---|---|---|
| `invalid address` | Bad subject address | Prompt to check `0x` + 40 hex |
| empty return value | No analyzer deployed at the address | Re-prompt for correct address; check `assets/deployments.json` |
| `execution reverted` | Analyzer misconfigured (e.g. bad registry pointer — should never happen) | Surface revert reason; redeploy if needed |
