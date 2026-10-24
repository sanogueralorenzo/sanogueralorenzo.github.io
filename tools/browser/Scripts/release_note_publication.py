#!/usr/bin/env python3
"""Read and advance Crest's per-channel release-note publication cursors."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import tempfile
from typing import NamedTuple

try:
    from release_note_catalog import (
        CATALOG_PATH,
        PUBLICATION_CHANNELS,
        CatalogValidationError,
        ReleaseNoteCatalog,
        parse_catalog_document,
        unique_json_object,
    )
except ModuleNotFoundError:
    from Scripts.release_note_catalog import (
        CATALOG_PATH,
        PUBLICATION_CHANNELS,
        CatalogValidationError,
        ReleaseNoteCatalog,
        parse_catalog_document,
        unique_json_object,
    )


PUBLICATION_STATE_FILENAME = "release-note-publication.json"
PUBLICATION_STATE_SCHEMA_VERSION = 1


class PublicationState(NamedTuple):
    channels: dict[str, str]


def validate_channels(
    raw_channels: object,
    source: str,
    catalog: ReleaseNoteCatalog,
) -> dict[str, str]:
    if not isinstance(raw_channels, dict) or set(raw_channels) != set(
        PUBLICATION_CHANNELS
    ):
        channels = ", ".join(PUBLICATION_CHANNELS)
        raise CatalogValidationError(
            f"{source}: channels must contain exactly {channels}"
        )

    validated: dict[str, str] = {}
    for channel in PUBLICATION_CHANNELS:
        marker = raw_channels[channel]
        if not isinstance(marker, str) or marker not in catalog.entries:
            raise CatalogValidationError(
                f"{source}: {channel} cursor '{marker}' must identify a catalog entry"
            )
        validated[channel] = marker
    return validated


def parse_publication_state(
    contents: str,
    source: str,
    catalog: ReleaseNoteCatalog,
) -> PublicationState:
    try:
        document = json.loads(contents, object_pairs_hook=unique_json_object)
    except (json.JSONDecodeError, CatalogValidationError) as error:
        raise CatalogValidationError(f"{source}: {error}") from error

    if not isinstance(document, dict):
        raise CatalogValidationError(f"{source}: publication state root must be an object")
    if set(document) != {"schemaVersion", "channels"}:
        raise CatalogValidationError(
            f"{source}: publication state must contain only schemaVersion and channels"
        )
    if document["schemaVersion"] != PUBLICATION_STATE_SCHEMA_VERSION:
        raise CatalogValidationError(
            f"{source}: schemaVersion must be {PUBLICATION_STATE_SCHEMA_VERSION}"
        )
    return PublicationState(validate_channels(document["channels"], source, catalog))


def effective_publication_state(
    catalog: ReleaseNoteCatalog,
    state_contents: str | None,
    source: str = PUBLICATION_STATE_FILENAME,
) -> PublicationState:
    if state_contents is not None:
        return parse_publication_state(state_contents, source, catalog)
    if not catalog.publication_baselines:
        raise CatalogValidationError(
            "catalog has no publicationBaselines and no publication state exists"
        )
    return PublicationState(dict(catalog.publication_baselines))


def advance_channel(
    catalog: ReleaseNoteCatalog,
    state: PublicationState,
    channel: str,
) -> PublicationState:
    if channel not in PUBLICATION_CHANNELS:
        raise CatalogValidationError(f"unsupported publication channel '{channel}'")
    if not catalog.entries:
        raise CatalogValidationError("cannot advance a cursor in an empty catalog")

    channels = dict(state.channels)
    channels[channel] = next(reversed(catalog.entries))
    return PublicationState(channels)


def publication_state_contents(state: PublicationState) -> str:
    document = {
        "schemaVersion": PUBLICATION_STATE_SCHEMA_VERSION,
        "channels": {
            channel: state.channels[channel] for channel in PUBLICATION_CHANNELS
        },
    }
    return json.dumps(document, indent=2) + "\n"


def write_publication_state(path: pathlib.Path, state: PublicationState) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as stream:
        temporary_path = pathlib.Path(stream.name)
        stream.write(publication_state_contents(state))
    try:
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def read_optional(path: pathlib.Path | None) -> tuple[str | None, str]:
    if path is None or not path.is_file():
        return None, str(path or PUBLICATION_STATE_FILENAME)
    return path.read_text(), str(path)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("marker", "advance"))
    parser.add_argument("--catalog", type=pathlib.Path, default=pathlib.Path(CATALOG_PATH))
    parser.add_argument("--state", type=pathlib.Path)
    parser.add_argument("--channel", choices=PUBLICATION_CHANNELS, required=True)
    parser.add_argument("--output", type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    catalog = parse_catalog_document(arguments.catalog.read_text(), str(arguments.catalog))
    state_contents, state_source = read_optional(arguments.state)
    state = effective_publication_state(catalog, state_contents, state_source)

    if arguments.command == "marker":
        if arguments.output is not None:
            raise CatalogValidationError("marker does not accept --output")
        print(state.channels[arguments.channel])
        return 0

    if arguments.output is None:
        raise CatalogValidationError("advance requires --output")
    advanced = advance_channel(catalog, state, arguments.channel)
    write_publication_state(arguments.output, advanced)
    print(advanced.channels[arguments.channel])
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CatalogValidationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
