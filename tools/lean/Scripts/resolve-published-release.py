#!/usr/bin/env python3
"""Resolve the source commit from a channel's latest published appcast item."""

from __future__ import annotations

import argparse
import pathlib
import re
import urllib.parse
import xml.etree.ElementTree as ElementTree


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ROLLING_CHANNELS = ("development", "nightly")


def published_commit_prefix(appcast: str, channel: str) -> str | None:
    root = ElementTree.fromstring(appcast)
    channel_element = f"{{{SPARKLE_NAMESPACE}}}channel"
    asset_pattern = re.compile(
        rf"^(?:Installer-)?Crest-.+-{re.escape(channel)}-"
        rf"\d{{4}}-\d{{2}}-\d{{2}}-([0-9a-f]{{7,40}})-arm64\.dmg$"
    )

    for item in root.findall(".//item"):
        if (item.findtext(channel_element) or "").strip() != channel:
            continue
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        asset_name = pathlib.PurePosixPath(
            urllib.parse.urlparse(enclosure.get("url", "")).path
        ).name
        match = asset_pattern.fullmatch(urllib.parse.unquote(asset_name))
        if match is not None:
            return match.group(1)

    return None


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", type=pathlib.Path, required=True)
    parser.add_argument("--channel", choices=ROLLING_CHANNELS, required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    commit_prefix = published_commit_prefix(
        arguments.appcast.read_text(),
        arguments.channel,
    )
    if commit_prefix is not None:
        print(commit_prefix)


if __name__ == "__main__":
    main()
