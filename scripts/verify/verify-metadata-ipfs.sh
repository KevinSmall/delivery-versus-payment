#!/usr/bin/env bash
# Prove that a clean local build reproduces the IPFS metadata hash that Sourcify
# shows for the deployed DVP V1 contracts.
#
# It does a deterministic `forge build` (no cache) and then computes the IPFS
# CIDv0 of the compiled metadata, comparing it to the CID embedded in the
# bytecode and, if given, to an expected value.
#
# Usage:
#   scripts/verify/verify-metadata-ipfs.sh
#   scripts/verify/verify-metadata-ipfs.sh QmNcCobMGvYxA2kfbYg8iLKTK2DPVLXwFN3DvJ6QBnJXzg   # DVP V1 expected
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."   # repo root

EXPECTED_DVP="${1:-}"   # optional expected CID for DeliveryVersusPaymentV1

echo "==> Clean, deterministic build (forge build --force)"
forge build --force >/dev/null

run() {
  local artifact="$1" expected="$2"
  local args=("$artifact")
  [[ -n "$expected" ]] && args+=(--expected "$expected")
  python3 "$SCRIPT_DIR/ipfs_metadata_cid.py" "${args[@]}"
  echo
}

echo "==> DeliveryVersusPaymentV1"
run out/DeliveryVersusPaymentV1.sol/DeliveryVersusPaymentV1.json "$EXPECTED_DVP"

echo "==> DeliveryVersusPaymentV1HelperV1"
run out/DeliveryVersusPaymentV1HelperV1.sol/DeliveryVersusPaymentV1HelperV1.json ""
