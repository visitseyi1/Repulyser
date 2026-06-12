#!/usr/bin/env bash
# Repulyser analyze — generated template.
# Fill in the SUBJECT and (optionally) ANALYZER + RPC_URL, then run.
# This file is a TEMPLATE; do not commit real addresses here.

set -euo pipefail

# ---- Required: the address you want to analyze ----
SUBJECT="${SUBJECT:-0x0000000000000000000000000000000000000000}"

# ---- Optional: override the network and analyzer address ----
NETWORK="${NETWORK:-atlantic-testnet}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RPC_URL="${RPC_URL:-$(jq -r ".networks[] | select(.name==\"$NETWORK\") | .rpcUrl" "$SKILL_DIR/assets/networks.json")}"
ANALYZER="${ANALYZER:-$(jq -r ".$NETWORK.analyzer" "$SKILL_DIR/assets/deployments.json")}"
EXPLORER_URL="${EXPLORER_URL:-$(jq -r ".networks[] | select(.name==\"$NETWORK\") | .explorerUrl" "$SKILL_DIR/assets/networks.json")}"

if [ -z "$RPC_URL" ] || [ "$RPC_URL" = "null" ]; then
  echo "ERROR: no RPC URL for network '$NETWORK' in assets/networks.json" >&2
  exit 1
fi

if [ -z "$ANALYZER" ] || [ "$ANALYZER" = "0x0000000000000000000000000000000000000000" ]; then
  echo "ERROR: no analyzer address for '$NETWORK' in assets/deployments.json — deploy first or set ANALYZER env var" >&2
  exit 1
fi

echo "Network:   $NETWORK ($RPC_URL)"
echo "Analyzer:  $ANALYZER"
echo "Subject:   $SUBJECT"
echo "Explorer:  $EXPLORER_URL/address/$SUBJECT"
echo "----------------------------------------------------------------"

QUICK=$(cast call "$ANALYZER" "quickScore(address)(uint16,uint8,uint8)" "$SUBJECT" --rpc-url "$RPC_URL")
SCORE=$(echo "$QUICK" | sed -n '1p')
TIER_NUM=$(echo "$QUICK" | sed -n '2p')
PRESENT=$(echo "$QUICK" | sed -n '3p')
TIER_STR=$(cast call "$ANALYZER" "tierString(uint8)(string)" "$TIER_NUM" --rpc-url "$RPC_URL" | tr -d '"')

# Score is in [0, 10000] i.e. percent * 100
PERCENT_RAW=$((SCORE / 100))
PERCENT_DEC=$((SCORE % 100))
printf "Score:     %s / 10000  (%d.%02d %%)\n" "$SCORE" "$PERCENT_RAW" "$PERCENT_DEC"
printf "Tier:      %s\n" "$TIER_STR"
printf "Coverage:  %s / 10 signal types have fresh data\n" "$PRESENT"
echo "----------------------------------------------------------------"
echo "Full breakdown: SUBJECT=$SUBJECT ANALYZER=$ANALYZER forge script script/AnalyzeReputation.s.sol:AnalyzeReputation"
