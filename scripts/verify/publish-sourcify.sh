#!/usr/bin/env bash
# Publish (verify) DVP source to Sourcify for a deployed address.
#
# Sourcify verifies by recompiling your source and matching the resulting
# metadata/bytecode against the on-chain code. No API key is required.
#
# NOTE: this talks to the Sourcify **v2** API directly (POST /v2/verify/...).
# `forge verify-contract --verifier sourcify` (foundry 1.5.x) still uses the
# legacy v1 API, which Sourcify put into a decommissioning "brownout" and now
# returns errors that forge mis-reports as "already verified". We therefore use
# forge only to generate the Standard JSON compiler input, and submit via curl.
#
# Examples:
#   # DVP V1 on Ethereum mainnet (default contract + chain 1):
#   scripts/verify/publish-sourcify.sh 0xb0d73b0559F260bc239FF2ffBc8676595601134c
#
#   # Explicit contract / chain:
#   scripts/verify/publish-sourcify.sh 0xADDR... --chain 1 \
#     --contract src/dvp/V1/DeliveryVersusPaymentV1.sol:DeliveryVersusPaymentV1
#
#   # Point at a different Sourcify server (e.g. staging):
#   scripts/verify/publish-sourcify.sh 0xADDR... --server https://staging.sourcify.dev/server
set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)/../.."   # repo root

ADDRESS="${1:-}"
if [[ -z "$ADDRESS" ]]; then
  echo "Usage: $(basename "$0") <ADDRESS> [--chain ID] [--contract PATH:NAME] [--server URL]" >&2
  exit 1
fi
shift

CHAIN=1
CONTRACT="src/dvp/V1/DeliveryVersusPaymentV1.sol:DeliveryVersusPaymentV1"
SERVER="https://sourcify.dev/server"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chain) CHAIN="$2"; shift 2 ;;
    --contract) CONTRACT="$2"; shift 2 ;;
    --server) SERVER="${2%/}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Full compiler version (with commit hash) as recorded in the build artifact.
ARTIFACT="out/${CONTRACT##*/}.sol/${CONTRACT##*/}.json"
# ^ handles the common case where file base name == contract name; override below if not.
FILE_PART="${CONTRACT%%:*}"
NAME_PART="${CONTRACT##*:}"
ARTIFACT="out/$(basename "$FILE_PART")/${NAME_PART}.json"
if [[ ! -f "$ARTIFACT" ]]; then
  echo "Building ($ARTIFACT not found)..."
  forge build >/dev/null
fi
COMPILER_VERSION="$(python3 -c "import json;print(json.load(open('$ARTIFACT'))['metadata']['compiler']['version'])")"

echo "==> Verifying on Sourcify (v2 API)"
echo "    address : $ADDRESS"
echo "    contract: $CONTRACT"
echo "    chain   : $CHAIN"
echo "    compiler: $COMPILER_VERSION"
echo "    server  : $SERVER"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Standard JSON compiler input (forge builds this from your sources + settings).
forge verify-contract "$ADDRESS" "$CONTRACT" --chain "$CHAIN" --show-standard-json-input > "$TMP/std.json"

# 2) Wrap into the v2 request body.
python3 - "$CONTRACT" "$COMPILER_VERSION" "$TMP/std.json" "$TMP/req.json" <<'PY'
import json, sys
cid, ver, std_path, out_path = sys.argv[1:5]
json.dump({
    "stdJsonInput": json.load(open(std_path)),
    "compilerVersion": ver,
    "contractIdentifier": cid,
}, open(out_path, "w"))
PY

# 3) Submit.
RESP="$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data @"$TMP/req.json" "$SERVER/v2/verify/$CHAIN/$ADDRESS")"
CODE="${RESP##*$'\n'}"
BODY="${RESP%$'\n'*}"
echo "submit HTTP $CODE: $BODY"

if [[ "$CODE" == "409" ]]; then
  echo "Already verified on this server. Current state:"
  curl -s "$SERVER/v2/contract/$CHAIN/$ADDRESS"; echo
  exit 0
fi
if [[ "$CODE" != "202" ]]; then
  echo "Unexpected response; aborting." >&2
  exit 1
fi

VID="$(python3 -c "import json,sys;print(json.load(sys.stdin)['verificationId'])" <<<"$BODY")"

# 4) Poll the async job.
echo "==> Polling job $VID"
for _ in $(seq 1 30); do
  JOB="$(curl -s "$SERVER/v2/verify/$VID")"
  if grep -q '"isJobCompleted":true' <<<"$JOB"; then
    echo "$JOB" | python3 -m json.tool
    break
  fi
  sleep 2
done

echo
echo "Done. View at:"
echo "  https://sourcify.dev/address/$ADDRESS"
