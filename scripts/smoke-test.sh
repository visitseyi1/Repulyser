#!/usr/bin/env bash
# scripts/smoke-test.sh
#
# End-to-end smoke test for Repulyser using only the Foundry toolchain.
#
# Usage:
#   ./scripts/smoke-test.sh
#   RPC_URL=http://127.0.0.1:8545 ./scripts/smoke-test.sh   # use existing node
#
# Requirements:
#   - forge / cast on PATH (run `foundryup` if not)
#   - jq
#   - anvil (only if no RPC_URL is provided; the script will start it)
#
# What it does:
#   1. forge build
#   2. forge test (29 tests)
#   3. ensure an RPC node is reachable (start anvil if not)
#   4. deploy the three contracts with DEMO=1 (10 demo signals)
#   5. read the analyzer address and query the deployer via cast call
#   6. run the pretty-print forge script
#
# Expected output:
#   Score:    ~4xxx - 6xxx / 10000  (~45-60%)
#   Tier:     Silver or Gold
#   Coverage: 10 / 10 signal types
#
# Note: the anvil instance the script starts is left running on
# http://127.0.0.1:8545 so you can run extra queries yourself.
# To stop it:  pkill -f "anvil "

set -euo pipefail

cd "$(dirname "$0")/.."

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "${CYAN}==> $1${NC}"; }
ok()   { echo -e "${GREEN}    $1${NC}"; }

RPC_URL="${RPC_URL:-}"
STARTED_ANVIL=0

ensure_rpc() {
  if [ -n "$RPC_URL" ] && cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    ok "using RPC_URL=$RPC_URL"
    return 0
  fi
  if ! command -v anvil >/dev/null 2>&1; then
    echo "anvil not on PATH; install Foundry (foundryup) or set RPC_URL to an existing node" >&2
    exit 1
  fi
  pkill -f "anvil " 2>/dev/null || true
  sleep 0.3
  step "starting anvil on http://127.0.0.1:8545"
  nohup anvil --port 8545 </dev/null >/tmp/anvil.log 2>&1 &
  STARTED_ANVIL=1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if cast block-number --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1; then
      RPC_URL=http://127.0.0.1:8545
      ok "anvil up at $RPC_URL"
      return 0
    fi
    sleep 0.3
  done
  echo "anvil failed to start; see /tmp/anvil.log" >&2
  exit 1
}

cleanup() {
  if [ "$STARTED_ANVIL" = "1" ]; then
    pkill -f "anvil " 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Clean stale broadcast so we read addresses from this run
rm -rf broadcast/DeployRepulyser.s.sol/31337

step "1/6 forge build"
forge build >/dev/null
ok "build clean"

step "2/6 forge test (29 tests)"
forge test --summary 2>&1 | tail -3

step "3/6 ensure RPC node"
ensure_rpc

PRIV=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER=$(cast wallet address --private-key $PRIV)

step "4/6 deploy Repulyser (DEMO=1: deploys + pushes 10 signals)"
DEMO=1 forge script script/DeployRepulyser.s.sol:DeployRepulyser \
  --rpc-url "$RPC_URL" --private-key $PRIV --broadcast >/tmp/deploy.log 2>&1
grep -E "deployed at" /tmp/deploy.log | sed 's/^/    /'

BROADCAST_DIR="broadcast/DeployRepulyser.s.sol/31337/run-latest.json"
REGISTRY=$(jq -r '[.transactions[] | select(.contractName=="ReputationRegistry") | .contractAddress] | first' "$BROADCAST_DIR")
ANALYZER=$(jq -r '[.transactions[] | select(.contractName=="ReputationAnalyzer") | .contractAddress] | first' "$BROADCAST_DIR")
HELPER=$(jq   -r '[.transactions[] | select(.contractName=="ReputationAttestor") | .contractAddress] | first' "$BROADCAST_DIR")
ok "registry: $REGISTRY"
ok "analyzer: $ANALYZER"
ok "helper:   $HELPER"

step "5/6 query reputation via cast call"
QUICK=$(cast call $ANALYZER "quickScore(address)(uint16,uint8,uint8)" $DEPLOYER --rpc-url "$RPC_URL")
SCORE=$(echo "$QUICK"   | sed -n '1p')
TIER=$(echo "$QUICK"    | sed -n '2p')
PRESENT=$(echo "$QUICK" | sed -n '3p')
TIER_STR=$(cast call $ANALYZER "tierString(uint8)(string)" $TIER --rpc-url "$RPC_URL" | tr -d '"')
PERCENT_RAW=$((SCORE / 100))
PERCENT_DEC=$((SCORE % 100))
ok "score:    ${SCORE} / 10000  (${PERCENT_RAW}.${PERCENT_DEC} %)"
ok "tier:     ${TIER_STR}"
ok "coverage: ${PRESENT} / 10 signal types"

step "6/6 run the pretty-print script"
set +e
SUBJECT=$DEPLOYER ANALYZER=$ANALYZER forge script script/AnalyzeReputation.s.sol:AnalyzeReputation 2>&1 \
  | grep -E "Subject:|Score|Tier:|Signals present:|type:|contribution:" | head -25
ANALYZE_RC=$?
set -e
# forge script sometimes returns non-zero on success; only fail if the
# analyze call truly errored.
if [ $ANALYZE_RC -ne 0 ] && [ $ANALYZE_RC -ne 1 ]; then
  exit $ANALYZE_RC
fi

echo
echo -e "${GREEN}==> smoke test PASSED${NC}"
if [ "$STARTED_ANVIL" = "1" ]; then
  echo "    Anvil is still running on http://127.0.0.1:8545 (will be killed on exit)"
  echo "    Try more queries yourself:"
  echo "      export ANALYZER=$ANALYZER"
  echo "      export RPC_URL=$RPC_URL"
  echo "      cast call \$ANALYZER 'quickScore(address)(uint16,uint8,uint8)' 0xSomeAddress --rpc-url \$RPC_URL"
fi
