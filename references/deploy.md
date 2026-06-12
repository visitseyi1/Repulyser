# Deployment

> **Network configuration**: read `<rpc>`, `<chain_id>`, and `<explorer_api_url>` from `assets/networks.json`. Default network is `atlantic-testnet`.

## One-shot deploy

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)

forge script script/DeployRepulyser.s.sol:DeployRepulyser \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

The script will print three addresses:

```
ReputationRegistry deployed at: 0xRRRR...
ReputationAnalyzer deployed at:  0xAAAA...
ReputationAttestor deployed at:  0xHHHH...
```

Copy those into `assets/deployments.json` (use `assets/deployments.example.json` as the template) and commit. The skill's `analyze` reference looks up the analyzer address from there.

### Optional: bootstrap demo data

Set `DEMO=1` to also register the deployer as the first attestor, register a subject handle, and submit 10 demo signals. Useful for end-to-end smoke testing after deploy.

```bash
DEMO=1 forge script script/DeployRepulyser.s.sol:DeployRepulyser \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Verify contracts

```bash
CHAIN_ID=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .chainId' assets/networks.json)
EXPLORER_API_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .explorerApiUrl' assets/networks.json)

# Registry — no constructor args
forge verify-contract $REGISTRY_ADDRESS src/ReputationRegistry.sol:ReputationRegistry \
  --chain-id $CHAIN_ID \
  --verifier-url $EXPLORER_API_URL \
  --verifier blockscout

# Analyzer — takes registry address as constructor arg
forge verify-contract $ANALYZER_ADDRESS src/ReputationAnalyzer.sol:ReputationAnalyzer \
  --chain-id $CHAIN_ID \
  --verifier-url $EXPLORER_API_URL \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address)" $REGISTRY_ADDRESS)

# Attestor helper — takes registry address as constructor arg
forge verify-contract $HELPER_ADDRESS src/ReputationAttestor.sol:ReputationAttestor \
  --chain-id $CHAIN_ID \
  --verifier-url $EXPLORER_API_URL \
  --verifier blockscout \
  --constructor-args $(cast abi-encode "constructor(address)" $REGISTRY_ADDRESS)
```

> If verifying immediately after deployment, wait ~10 seconds for the explorer indexer to catch up (the Pharos docs warn about this for `forge verify-contract`).

## Deployment cost (Atlantic testnet reference)

Approximate deployment costs from the testnet gas report:

| Contract | Deployment cost | Size |
|---|---|---|
| `ReputationRegistry` | ~1,293,450 gas | 5,676 B |
| `ReputationAnalyzer` | ~1,050,000 gas (with via-ir) | ~3,400 B |
| `ReputationAttestor` | ~730,278 gas | 3,403 B |

Combined deploy (registry + analyzer + helper) is well under 4M gas — comfortably within a single Pharos block at normal gas prices.

## Post-deploy checklist

1. Save the three addresses to `assets/deployments.json` and commit.
2. `forge verify-contract` all three on the explorer.
3. Run `DEMO=1` on a throwaway test wallet and confirm `cast call` returns a sensible tier.
4. Decide which off-chain bot addresses should become attestors, and have the owner call `registerAttestor(bot, "BotName")` for each.
5. Wire the bot to call `ReputationAttestor.queue(...)` from a cron job, then `ReputationAttestor.submitAll()` to push batches.
