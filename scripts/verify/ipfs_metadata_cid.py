#!/usr/bin/env python3
"""Compute the IPFS CIDv0 of a Foundry artifact's Solidity metadata.

When solc compiles a contract it emits a metadata JSON document and embeds the
IPFS hash of that document into the contract bytecode (as a CBOR-encoded trailer).
Sourcify shows this same hash. This script reproduces it locally from the build
artifact so you can prove that your local build matches an on-chain deployment.

It reports three things and checks they agree:
  1. CIDv0 computed from the artifact's `rawMetadata` string (as `ipfs add` would).
  2. CIDv0 read directly from the CBOR trailer of the deployed bytecode.
  3. (optional) an expected CID you pass in, e.g. from playground.sourcify.dev.

Usage:
  python3 scripts/verify/ipfs_metadata_cid.py out/DeliveryVersusPaymentV1.sol/DeliveryVersusPaymentV1.json
  python3 scripts/verify/ipfs_metadata_cid.py <artifact.json> --expected QmNc...JXzg

Exit code is non-zero if any of the available hashes disagree.
"""
import argparse
import hashlib
import json
import sys

_B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58encode(b: bytes) -> str:
    n = int.from_bytes(b, "big")
    s = ""
    while n:
        n, r = divmod(n, 58)
        s = _B58[r] + s
    pad = len(b) - len(b.lstrip(b"\x00"))
    return _B58[0] * pad + s


def _uvarint(n: int) -> bytes:
    out = b""
    while True:
        x = n & 0x7F
        n >>= 7
        out += bytes([x | (0x80 if n else 0)])
        if not n:
            break
    return out


def cidv0(data: bytes) -> str:
    """CIDv0 of `data` wrapped as a single UnixFS file, i.e. what `ipfs add` yields
    for small files (< 256 KiB, no chunking)."""
    unixfs = b"\x08\x02" + b"\x12" + _uvarint(len(data)) + data + b"\x18" + _uvarint(len(data))
    pbnode = b"\x0a" + _uvarint(len(unixfs)) + unixfs
    multihash = b"\x12\x20" + hashlib.sha256(pbnode).digest()  # sha2-256, 32 bytes
    return b58encode(multihash)


def cid_from_bytecode(deployed_hex: str):
    deployed_hex = deployed_hex[2:] if deployed_hex.startswith("0x") else deployed_hex
    b = bytes.fromhex(deployed_hex)
    # CBOR trailer: map(2) key "ipfs" (0x6469706673) value bytes(34) (0x5822)
    marker = bytes.fromhex("a264697066735822")
    i = b.find(marker)
    if i < 0:
        return None
    return b58encode(b[i + 8 : i + 8 + 34])


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("artifact", help="Path to Foundry artifact JSON (out/<File>.sol/<Contract>.json)")
    p.add_argument("--expected", help="Expected CID to compare against (e.g. from Sourcify)")
    args = p.parse_args()

    with open(args.artifact) as f:
        art = json.load(f)

    raw = art.get("rawMetadata")
    if raw is None:
        print(f"error: artifact has no rawMetadata field: {args.artifact}", file=sys.stderr)
        return 2

    from_meta = cidv0(raw.encode())
    from_code = cid_from_bytecode(art.get("deployedBytecode", {}).get("object", ""))

    print(f"artifact                 : {args.artifact}")
    print(f"CID from rawMetadata      : {from_meta}")
    print(f"CID from bytecode trailer : {from_code if from_code else '(no CBOR ipfs trailer found)'}")
    if args.expected:
        print(f"expected                  : {args.expected}")

    ok = True
    if from_code and from_code != from_meta:
        print("MISMATCH: metadata CID != bytecode trailer CID", file=sys.stderr)
        ok = False
    if args.expected and args.expected != from_meta:
        print("MISMATCH: computed CID != expected CID", file=sys.stderr)
        ok = False

    print("RESULT: MATCH ✅" if ok else "RESULT: MISMATCH ❌")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
