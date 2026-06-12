# Registry — writes

> **Network configuration**: read `<rpc>` from `assets/networks.json`. The registry address comes from `assets/deployments.json`.
> **All write commands require `--private-key $PRIVATE_KEY`.** Complete the standard pre-checks (key set → derive address → confirm network) before running.

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
REGISTRY=$(jq -r '.atlantic-testnet.registry' assets/deployments.json)
```

## SignalType enum (must match IReputationRegistry.SignalType)

| Index | Name | Index | Name |
|---|---|---|---|
| 0 | AccountAge | 5 | NftHoldings |
| 1 | TxVolume | 6 | SocialEndorsements |
| 2 | TxFrequency | 7 | ContractDeploys |
| 3 | DefiInteractions | 8 | AssetDiversity |
| 4 | GovernanceVotes | 9 | LiquidStaking |

## Register the caller as an attestor (one-time, owner only)

The owner is the deployer of `ReputationRegistry`. Have the owner run:

```bash
cast send $REGISTRY \
  "registerAttestor(address,string)" $YOUR_BOT_ADDRESS "Repulyser Bot" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

To register multiple bots in one tx, call the function multiple times in sequence.

## Self-register as a subject (free, any address)

```bash
cast send $REGISTRY \
  "registerSubject(string)" "yourhandle" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

The handle is metadata only and is not used in scoring.

## Submit one signal

Signal arguments:
- `subject` — target address
- `signalType` — `uint8` index from the table above
- `score` — `uint16` in `[0, 10000]`
- `weight` — `uint16` in `(0, 10000]`
- `data` — optional `bytes` (max 256 bytes, e.g. a short URI or note)

```bash
cast send $REGISTRY \
  "submitSignal(address,uint8,uint16,uint16,bytes)" \
  0xSubject 0 6500 8000 0x \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

Returns the new `signalId` in the transaction receipt's logs (event `SignalSubmitted(uint256,address,address,uint8,uint16)`).

## Revoke a signal (any attestor)

```bash
cast send $REGISTRY \
  "revokeSignal(uint256)" $SIGNAL_ID \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Read helpers

```bash
# All signal IDs for a subject
cast call $REGISTRY "signalsOf(address)(uint256[])" 0xSubject --rpc-url $RPC_URL

# Latest signal of a specific type for a subject
cast call $REGISTRY "latestSignalOf(address,uint8)((address,uint8,uint16,uint16,uint64,bytes),bool)" \
  0xSubject 0 --rpc-url $RPC_URL

# Number of signals ever submitted
cast call $REGISTRY "signalCount()(uint256)" --rpc-url $RPC_URL

# Lookup an attestor
cast call $REGISTRY "isAttestor(address)(bool)" 0xBot --rpc-url $RPC_URL
cast call $REGISTRY "attestorName(address)(string)" 0xBot --rpc-url $RPC_URL
```

## Pre-checks (mandatory for every write)

1. `cast wallet address --private-key $PRIVATE_KEY` → show user, get ack.
2. Show target network ("atlantic-testnet" or "mainnet"); require explicit confirmation for mainnet.
3. Check balance:

   ```bash
   cast balance $(cast wallet address --private-key $PRIVATE_KEY) --rpc-url $RPC_URL
   ```
4. Run the `cast send` and surface the tx hash + explorer link.

## Error handling

| Error | Cause | Action |
|---|---|---|
| `ReputationRegistry: not owner` | Caller is not the registry owner | Get the owner key, or have the owner call |
| `ReputationRegistry: not attestor` | Caller is not a registered attestor | Register first via the owner |
| `ReputationRegistry: zero subject` | subject is `0x0` | Reject input |
| `ReputationRegistry: score>10000` | score > 10000 | Clamp to 10000 or reject |
| `ReputationRegistry: bad weight` | weight is 0 or > 10000 | Use a value in `(0, 10000]` |
| `ReputationRegistry: data too long` | data > 256 bytes | Shorten, or pass `0x` |
