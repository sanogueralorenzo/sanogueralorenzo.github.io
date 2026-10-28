#!/usr/bin/env python3
"""Validate Crest's declared third-party dependency and license surface."""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPOSITORY_ROOT / "Config" / "ThirdPartyDependencies.json"
PACKAGE_RESOLVED_PATH = (
    REPOSITORY_ROOT
    / "Crest.xcodeproj"
    / "project.xcworkspace"
    / "xcshareddata"
    / "swiftpm"
    / "Package.resolved"
)
PACKAGE_LOCK_PATH = REPOSITORY_ROOT / "HelpCenter" / "package-lock.json"
WORKFLOW_DIRECTORY = REPOSITORY_ROOT / ".github" / "workflows"

ALLOWED_NPM_LICENSES = {
    "(BSD-2-Clause OR MIT OR Apache-2.0)",
    "(MIT OR CC0-1.0)",
    "(WTFPL OR MIT)",
    "0BSD",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "BlueOak-1.0.0",
    "CC-BY-4.0",
    "CC0-1.0",
    "ISC",
    "MIT",
    "MIT-0",
    "Python-2.0",
}


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Cannot read {path.relative_to(REPOSITORY_ROOT)}: {error}") from error


def package_name(package_path: str) -> str:
    return package_path.removeprefix("node_modules/").split("/node_modules/")[-1]


def audit_swift_packages(catalog: dict) -> int:
    resolved = load_json(PACKAGE_RESOLVED_PATH)
    actual = {
        pin["identity"]: pin["state"].get("version")
        for pin in resolved.get("pins", [])
    }
    expected = {
        dependency["identity"]: dependency["version"]
        for dependency in catalog["runtimeDependencies"]
    }
    if actual != expected:
        raise RuntimeError(
            f"Swift package inventory changed: expected {expected}, found {actual}."
        )

    for dependency in catalog["runtimeDependencies"]:
        notice_path = REPOSITORY_ROOT / dependency["notice"]
        if not notice_path.is_file():
            raise RuntimeError(f"Missing notice for {dependency['name']}: {dependency['notice']}")
    return len(actual)


def audit_bundled_data(catalog: dict) -> int:
    for data_set in catalog.get("bundledData", []):
        notice_path = REPOSITORY_ROOT / data_set["notice"]
        if not notice_path.is_file():
            raise RuntimeError(
                f"Missing notice for {data_set['name']}: {data_set['notice']}"
            )
    return len(catalog.get("bundledData", []))


def audit_bundled_components(catalog: dict) -> int:
    for component in catalog.get("bundledComponents", []):
        notice_path = REPOSITORY_ROOT / component["notice"]
        if not notice_path.is_file():
            raise RuntimeError(
                f"Missing notice for {component['name']}: {component['notice']}"
            )
    return len(catalog.get("bundledComponents", []))


def audit_npm_packages(catalog: dict) -> int:
    package_lock = load_json(PACKAGE_LOCK_PATH)
    packages = package_lock.get("packages", {})
    root_dependencies = packages.get("", {}).get("dependencies", {})
    expected_direct = catalog["helpCenterDirectDependencies"]
    if set(root_dependencies) != set(expected_direct):
        raise RuntimeError(
            "Help Center direct dependency inventory changed; update the license catalog."
        )

    metadata_exceptions = catalog["knownNpmLicenseMetadataExceptions"]
    failures: list[str] = []
    audited_count = 0
    for path, package in packages.items():
        if not path:
            continue
        audited_count += 1
        name = package_name(path)
        license_name = package.get("license") or metadata_exceptions.get(name)
        if license_name not in ALLOWED_NPM_LICENSES:
            failures.append(f"{name}@{package.get('version', '?')}: {license_name or 'missing'}")

    for name, expected_license in expected_direct.items():
        package = packages.get(f"node_modules/{name}")
        if package is None:
            failures.append(f"{name}: missing from package-lock.json")
        elif package.get("license") != expected_license:
            failures.append(
                f"{name}@{package.get('version', '?')}: expected {expected_license}, "
                f"found {package.get('license', 'missing')}"
            )

    if failures:
        raise RuntimeError("Unreviewed npm licenses:\n  " + "\n  ".join(sorted(failures)))
    return audited_count


def audit_workflow_actions(catalog: dict) -> int:
    expected = set(catalog["workflowActionRepositories"])
    actual: set[str] = set()
    for workflow_path in WORKFLOW_DIRECTORY.glob("*.yml"):
        for action in re.findall(r"^\s*-?\s*uses:\s*([^@\s]+)@", workflow_path.read_text(), re.M):
            if action.startswith("./"):
                continue
            components = action.split("/")
            if len(components) < 2:
                raise RuntimeError(
                    f"Malformed workflow action in {workflow_path.name}: {action}"
                )
            actual.add("/".join(components[:2]))

    if actual != expected:
        raise RuntimeError(
            f"Workflow action inventory changed: expected {sorted(expected)}, "
            f"found {sorted(actual)}."
        )
    return len(actual)


def main() -> int:
    try:
        catalog = load_json(CATALOG_PATH)
        swift_count = audit_swift_packages(catalog)
        data_count = audit_bundled_data(catalog)
        component_count = audit_bundled_components(catalog)
        npm_count = audit_npm_packages(catalog)
        action_count = audit_workflow_actions(catalog)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        f"License audit passed: {swift_count} runtime Swift package, "
        f"{component_count} bundled components, {data_count} bundled data set, "
        f"{npm_count} Help Center packages, and "
        f"{action_count} workflow action repositories are declared and reviewed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
