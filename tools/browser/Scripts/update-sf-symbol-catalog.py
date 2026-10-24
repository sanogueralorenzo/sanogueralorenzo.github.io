#!/usr/bin/env python3
"""Refresh the name-only SF catalog from an explicit SFSafeSymbols revision.

Usage: python3 Scripts/update-sf-symbol-catalog.py --revision <40-character commit SHA>
The picker draws Apple's system artwork; no SF Symbol images are redistributed.
"""
import argparse
import json
import re
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--revision", required=True)
args = parser.parse_args()
if not re.fullmatch(r"[0-9a-f]{40}", args.revision):
    parser.error("Use an immutable, 40-character commit SHA.")

root = Path(__file__).resolve().parents[1]
base = f"https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/{args.revision}/"
source = base + "SymbolsGenerator/Sources/SymbolsGenerator/Resources/symbol_names.txt"
with urllib.request.urlopen(source, timeout=30) as response:
    names = response.read().decode("utf-8")
with urllib.request.urlopen(base + "LICENSE", timeout=30) as response:
    license_text = response.read().decode("utf-8")
entries = [line.strip() for line in names.splitlines() if line.strip() and not line.startswith("//")]
if not entries or any(not re.fullmatch(r"[a-z0-9.]+", name) for name in entries):
    raise SystemExit("Unexpected symbol catalog format; no files were changed.")

metadata_path = root / "Config/ThirdPartyDependencies.json"
metadata = json.loads(metadata_path.read_text())
record = next(item for item in metadata["bundledData"] if item["identity"] == "sf-symbol-names")
record.update(version=args.revision, source=source)
(root / "CrestShared/Resources/SFSymbolNames.txt").write_text(names)
(root / record["notice"]).write_text(
    "SF symbol name catalog from SFSafeSymbols\nRevision: " + args.revision
    + "\nhttps://github.com/SFSafeSymbols/SFSafeSymbols\n"
    + "Only symbol names are included; artwork is supplied by the operating system.\n\n" + license_text
)
metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
print(f"Updated {len(entries)} SF symbol names at {args.revision}.")
