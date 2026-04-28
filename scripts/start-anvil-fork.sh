#!/usr/bin/env bash
set -euo pipefail

# Starts an Anvil fork of eth_sepolia, deploys mock tokens, and keeps running.
# Usage: ./scripts/start-anvil-fork.sh
# Requires: anvil, forge, RPC_ETH_SEPOLIA env var

# Load .env from project root if present
[ -f "$(dirname "$0")/../.env" ] && set -a && source "$(dirname "$0")/../.env" && set +a

: "${RPC_ETH_SEPOLIA:?RPC_ETH_SEPOLIA must be set}"

ANVIL_RPC="http://localhost:8545"

echo "Starting Anvil fork of eth_sepolia..."
anvil --fork-url "$RPC_ETH_SEPOLIA" &
ANVIL_PID=$!

# Ensure Anvil is killed when this script exits
trap 'echo "Stopping Anvil..."; kill "$ANVIL_PID" 2>/dev/null; wait "$ANVIL_PID" 2>/dev/null; echo "Done."' EXIT INT TERM

# Wait for Anvil to be ready
echo "Waiting for Anvil to be ready..."
for i in $(seq 1 20); do
  if curl -sf -X POST "$ANVIL_RPC" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      > /dev/null 2>&1; then
    echo "Anvil is ready."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "Anvil did not start in time." >&2
    exit 1
  fi
  sleep 0.5
done

echo ""
echo "Deploying mock tokens..."
forge script script/DeployMocksToAnvil.s.sol \
  --rpc-url "$ANVIL_RPC" \
  --broadcast \
  --skip-simulation

echo ""
echo "Anvil is running at $ANVIL_RPC (PID $ANVIL_PID)"
echo "DVP contracts inherited from eth_sepolia fork."
echo "Update config/palette.json anvil section with the token addresses printed above."
echo "Press Ctrl+C to stop."

wait "$ANVIL_PID"
