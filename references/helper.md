# ReputationAttestor helper — batch signal writes

> **Network configuration**: read `<rpc>` from `assets/networks.json`. The helper address comes from `assets/deployments.json`.
> **The `ReputationAttestor` contract itself must be a registered attestor on the registry** before it can submit signals. This is done with a one-time `registerAttestor(helper, "Repulyser Attestor Helper")` call by the registry owner.

```bash
RPC_URL=$(jq -r '.networks[] | select(.name=="atlantic-testnet") | .rpcUrl' assets/networks.json)
REGISTRY=$(jq -r '.atlantic-testnet.registry' assets/deployments.json)
HELPER=$(jq -r '.atlantic-testnet.attestorHelper' assets/deployments.json)
```

## Why use the helper

The helper exists for agents that need to push a batch of signals (e.g. "score 50 wallets, push all 500 signals at once") without spamming the registry with 500 separate transactions. It works in two phases:

1. **Queue** — `queue(subject, signalType, score, weight, data)` appends to a local array. The helper owner (your bot) is the only one who can queue.
2. **Submit** — `submitAll()` (or `submit(i)`) writes all queued payloads to the registry in a single transaction. The caller of `submitAll` must be a registered attestor on the registry, OR the helper itself must be registered as the attestor.

The standard pattern is:

- Helper contract = the attestor (registered once by the registry owner).
- Bot wallet = the helper owner. Bot queues signals. Helper submits them in one tx.

This keeps the on-chain identity stable (one address) while the bot key can rotate.

## One-time setup

```bash
# 1. Owner of registry registers the helper as an attestor
cast send $REGISTRY \
  "registerAttestor(address,string)" $HELPER "Repulyser Attestor Helper" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

The bot wallet (any address) then becomes the helper's `owner` simply by deploying the helper from that wallet, OR by transferring ownership via the helper's owner (not exposed in v1; redeploy if needed).

## Queue one signal

```bash
cast send $HELPER \
  "queue(address,uint8,uint16,uint16,bytes)" \
  0xSubject 0 6500 8000 0x \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

Returns nothing; check `pendingLength()` to see how many are queued.

```bash
cast call $HELPER "pendingLength()(uint256)" --rpc-url $RPC_URL
```

## Submit a queued signal (one at a time)

```bash
cast send $HELPER \
  "submit(uint256)" 0 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

Returns the new `signalId`. The `submit` function requires `msg.sender` to be a registered attestor on the registry (i.e. the helper itself, since the helper forwards the call). For a "bot is the attestor" pattern, also register the bot address as an attestor and call `submit` from the bot.

## Submit ALL queued signals in one tx (preferred)

```bash
cast send $HELPER \
  "submitAll()" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

Returns an array of new signalIds. Already-submitted entries are skipped (no-op), so `submitAll` is safe to call multiple times.

## Read helper state

```bash
# Number of queued entries (including already-submitted)
cast call $HELPER "pendingLength()(uint256)" --rpc-url $RPC_URL

# Inspect a queued entry
cast call $HELPER "pending(uint256)((address,uint8,uint16,uint16,bytes,bool))" 0 --rpc-url $RPC_URL
# returned tuple: (subject, signalType, score, weight, data, submitted)

# Which registry is the helper bound to?
cast call $HELPER "registry()(address)" --rpc-url $RPC_URL

# Who owns the helper (i.e. who can queue)?
cast call $HELPER "owner()(address)" --rpc-url $RPC_URL
```

## Error handling

| Error | Cause | Action |
|---|---|---|
| `ReputationAttestor: not owner` | Caller is not the helper's owner | Re-route via the helper owner key |
| `ReputationAttestor: not attestor` | Caller of `submit`/`submitAll` is not a registered attestor on the registry | Register the caller as an attestor on the registry |
| `ReputationAttestor: already submitted` | `submit(i)` called twice for the same index | Use `submitAll`, or skip the index |
| `ReputationAttestor: zero registry` | Helper deployed with `address(0)` as registry | Should never happen post-deploy |
