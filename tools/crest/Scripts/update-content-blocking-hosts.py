#!/usr/bin/env python3
"""Refresh Peter Lowe hosts and retain Crest's generic compatibility blocks."""

from pathlib import Path
import json
import re
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SOURCE = "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext"
HOST = re.compile(r"(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*")
# uBlock Origin's generic third-party Funding Choices rule:
# https://github.com/uBlockOrigin/uAssets/blob/651b917a3f7185db80d66412f019a1106c6bc13d/filters/filters.txt#L9500-L9501
COMPATIBILITY_HOSTS = {"fundingchoicesmessages.google.com"}
COMPATIBILITY_HEADER = "# Crest generic ad-block recovery compatibility (uBlock Origin):\n# https://github.com/uBlockOrigin/uAssets/blob/651b917a3f7185db80d66412f019a1106c6bc13d/filters/filters.txt#L9500-L9501\n"


def main():
    text = urllib.request.urlopen(SOURCE, timeout=45).read().decode("utf-8")
    hosts = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) != 2 or fields[0] != "127.0.0.1" or not HOST.fullmatch(fields[1]):
            raise ValueError("The upstream list contains an invalid host entry")
        hosts.append(fields[1])
    declared = int(re.search(r"^# entries:\s+(\d+)$", text, re.MULTILINE)[1])
    if not 1000 <= len(hosts) <= 20000 or len(set(hosts)) != declared or len(hosts) != declared:
        raise ValueError("The upstream host count is incomplete or unexpected")
    version = re.search(r"^# last updated:\s+(.+)$", text, re.MULTILINE)[1]
    path = ROOT / "Config/ThirdPartyDependencies.json"
    catalog = json.loads(path.read_text())
    asset = next(item for item in catalog["bundledData"] if item["identity"] == "peter-lowe-hosts")
    asset["version"] = version
    bundled = text.rstrip() + "\n"
    additional = sorted(COMPATIBILITY_HOSTS - set(hosts))
    if additional:
        bundled += "\n" + COMPATIBILITY_HEADER
        bundled += "".join(f"127.0.0.1 {host}\n" for host in additional)
    (ROOT / "CrestCore/src/CrestCore/Contracts/Session/ContentBlockingHosts.txt").write_text(bundled)
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(f"Updated Peter Lowe's list: {len(hosts)} hosts ({version}).")
    print("Run Scripts/control-plane/generate-contracts.sh before building.")


if __name__ == "__main__":
    main()
