#!/usr/bin/env python3
"""Compile EasyList's cosmetic filters with AdGuard's offline Safari converter."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "https://easylist-downloads.adblockplus.org/easylist.txt"
HIDING_MODIFIERS = {"elemhide", "generichide", "specifichide", "ehide", "ghide", "shide"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--converter", required=True, type=Path, help="SafariConverterLib v4.3.1 ConverterTool")
    args = parser.parse_args()
    source = urllib.request.urlopen(SOURCE, timeout=45).read().decode("utf-8")
    version = re.search(r"^! Version: (\d+)$", source, re.MULTILINE)[1]
    lines = []
    for line in source.splitlines():
        if line.startswith(("!", "[")):
            continue
        modifiers = set(line.rsplit("$", 1)[-1].split(",")) if "$" in line else set()
        if "##" in line or "#@#" in line or (line.startswith("@@") and modifiers & HIDING_MODIFIERS):
            lines.append(line)
    if len(lines) < 10000:
        raise ValueError("The upstream cosmetic list is incomplete")
    with tempfile.TemporaryDirectory(prefix="crest-cosmetics-") as directory:
        path = Path(directory)
        (path / "input.txt").write_text("\n".join(lines) + "\n")
        subprocess.run([
            str(args.converter.resolve()), "convert", "--safari-version", "26.0",
            "--advanced-blocking", "false", "--input-path", str(path / "input.txt"),
            "--safari-rules-json-path", str(path / "output.json"),
        ], check=True)
        rules = json.loads((path / "output.json").read_text())
    if not rules or any(rule["action"]["type"] not in {"css-display-none", "ignore-previous-rules"} for rule in rules):
        raise ValueError("The converter must produce only cosmetic rules and their exceptions")
    destination = ROOT / "CrestCore/src/CrestCore/Contracts/Session/ContentBlockingCosmetics.json"
    destination.write_text(json.dumps(rules, ensure_ascii=False, separators=(",", ":")) + "\n")
    path = ROOT / "Config/ThirdPartyDependencies.json"
    catalog = json.loads(path.read_text())
    asset = next(item for item in catalog["bundledData"] if item["identity"] == "easylist-cosmetics")
    asset["version"] = version
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated EasyList cosmetics: {len(rules)} native rules ({version}).")
    print("Run Scripts/control-plane/generate-contracts.sh before building.")


if __name__ == "__main__":
    main()
