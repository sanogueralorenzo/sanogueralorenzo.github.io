#!/usr/bin/env python3
"""Validate Crest's high-confidence source ownership and SwiftUI contracts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import NamedTuple


SOURCE_ROOTS = ("CrestShared", "CrestMac", "CrestMobile")
LAYER_IMPORT_POLICIES = {
    "CrestShared/Domain/": frozenset({"Foundation"}),
    "CrestShared/Application/": frozenset(
        {"Dispatch", "Foundation", "Observation", "Synchronization"}
    ),
}
PLATFORM_FRAMEWORK_OWNERS = {
    "AppKit": "CrestMac/",
    "CoreServices": "CrestMac/",
    "SecurityInterface": "CrestMac/",
    "UIKit": "CrestMobile/",
}
LEGACY_OBSERVATION_PATTERNS = (
    re.compile(r"\bObservableObject\b"),
    re.compile(r"@Published\b"),
)
ANY_VIEW_PATTERN = re.compile(r"\bAnyView\b")
STATE_DECLARATION_PATTERN = re.compile(
    r"(?P<attributes>(?:@\w+(?:\([^\n)]*\))?\s+)*)"
    r"@State\b(?P<tail>[^\n]*\bvar\s+(?P<name>[A-Za-z_]\w*)(?P<value>[^\n]*))"
)
SELF_ASSIGNMENT_PATTERN = re.compile(r"\bself\.(?P<name>[A-Za-z_]\w*)\s*=")
INIT_PATTERN = re.compile(r"(?<![.\w])init[!?]?\s*(?:<[^>{}]*>)?\s*\(")
NOMINAL_TYPE_PATTERN = re.compile(
    r"\b(?:actor|class|enum|struct)\s+[A-Za-z_]\w*[^{};]*\{"
)
TUPLE_VIEW_PATTERN = re.compile(r"\bTupleView\s*<")
BUILDER_MODIFIER_PATTERN = re.compile(r"\.(?:background|overlay)\s*\(")
BUILDER_STYLE_PATTERN = re.compile(r"\.(?:opacity|blendMode)\s*\(")
EMPTY_GROUP_PATTERN = re.compile(r"\bGroup\s*\{\s*\}", re.DOTALL)


class Violation(NamedTuple):
    rule: str
    path: str
    line: int
    detail: str


class GuardrailConfiguration(NamedTuple):
    excluded_path_prefixes: tuple[str, ...]
    import_exemptions: frozenset[tuple[str, str]]
    xcode27_pattern_exemptions: frozenset[tuple[str, str]]


class StateDeclaration(NamedTuple):
    name: str
    has_inline_default: bool
    line: int
    owner: tuple[int, int] | None


def _validated_entries(
    raw_configuration: dict[str, object], key: str, required_keys: tuple[str, ...]
) -> list[dict[str, str]]:
    entries = raw_configuration.get(key, [])
    if not isinstance(entries, list):
        raise ValueError(f"{key} must be an array.")

    validated: list[dict[str, str]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError(f"Each {key} entry must be an object.")
        values: dict[str, str] = {}
        for required_key in (*required_keys, "reason"):
            value = entry.get(required_key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(
                    f"Each {key} entry needs a nonempty {required_key}."
                )
            values[required_key] = value
        validated.append(values)
    return validated


def load_configuration(path: Path) -> GuardrailConfiguration:
    raw_configuration = json.loads(path.read_text())
    if not isinstance(raw_configuration, dict):
        raise ValueError("Architecture guardrail configuration must be an object.")

    excluded_entries = _validated_entries(
        raw_configuration, "excludedPathPrefixes", ("path",)
    )
    import_entries = _validated_entries(
        raw_configuration, "importExemptions", ("path", "module")
    )
    xcode_entries = _validated_entries(
        raw_configuration, "xcode27PatternExemptions", ("path", "rule")
    )

    return GuardrailConfiguration(
        excluded_path_prefixes=tuple(entry["path"] for entry in excluded_entries),
        import_exemptions=frozenset(
            (entry["path"], entry["module"]) for entry in import_entries
        ),
        xcode27_pattern_exemptions=frozenset(
            (entry["path"], entry["rule"]) for entry in xcode_entries
        ),
    )


def _is_excluded(
    relative_path: str, configuration: GuardrailConfiguration
) -> bool:
    return any(
        relative_path.startswith(prefix)
        for prefix in configuration.excluded_path_prefixes
    )


def _line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def _imports(source: str) -> list[tuple[str, int]]:
    imports: list[tuple[str, int]] = []
    import_kinds = {"class", "enum", "func", "protocol", "struct", "typealias", "var"}
    for line_number, line in enumerate(source.splitlines(), start=1):
        tokens = line.strip().split()
        if not tokens or tokens[0] != "import":
            continue
        module_index = 2 if len(tokens) > 2 and tokens[1] in import_kinds else 1
        if len(tokens) <= module_index:
            continue
        imports.append((tokens[module_index].split(".", maxsplit=1)[0], line_number))
    return imports


def _code_without_block_comments(source: str) -> str:
    return re.sub(
        r"/\*.*?\*/",
        lambda match: "".join(
            "\n" if character == "\n" else " " for character in match.group(0)
        ),
        source,
        flags=re.DOTALL,
    )


def _source_lines(source: str):
    for line_number, line in enumerate(
        _code_without_block_comments(source).splitlines(), start=1
    ):
        yield line_number, line.split("//", maxsplit=1)[0]


def _matching_brace(source: str, opening_brace: int) -> int | None:
    depth = 0
    for offset in range(opening_brace, len(source)):
        character = source[offset]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return offset
    return None


def _initializer_bodies(source: str):
    for initializer in INIT_PATTERN.finditer(source):
        opening_brace = source.find("{", initializer.end())
        if opening_brace == -1:
            continue
        closing_brace = _matching_brace(source, opening_brace)
        if closing_brace is None:
            continue
        yield initializer.start(), opening_brace, source[opening_brace + 1 : closing_brace]


def _nominal_type_ranges(source: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for declaration in NOMINAL_TYPE_PATTERN.finditer(source):
        opening_brace = declaration.end() - 1
        closing_brace = _matching_brace(source, opening_brace)
        if closing_brace is not None:
            ranges.append((opening_brace, closing_brace))
    return ranges


def _enclosing_nominal_type(
    offset: int, ranges: list[tuple[int, int]]
) -> tuple[int, int] | None:
    containing_ranges = [
        candidate
        for candidate in ranges
        if candidate[0] < offset < candidate[1]
    ]
    if not containing_ranges:
        return None
    return min(containing_ranges, key=lambda candidate: candidate[1] - candidate[0])


def _import_violations(
    relative_path: str,
    source: str,
    configuration: GuardrailConfiguration,
) -> list[Violation]:
    violations: list[Violation] = []
    for module, line_number in _imports(source):
        if (relative_path, module) in configuration.import_exemptions:
            continue

        for layer_prefix, allowed_modules in LAYER_IMPORT_POLICIES.items():
            if relative_path.startswith(layer_prefix) and module not in allowed_modules:
                violations.append(
                    Violation(
                        "layer-import",
                        relative_path,
                        line_number,
                        f"{module} is not allowed in {layer_prefix.rstrip('/')}",
                    )
                )

        if (
            relative_path.startswith("CrestShared/Infrastructure/")
            and module == "SwiftUI"
        ):
            violations.append(
                Violation(
                    "layer-import",
                    relative_path,
                    line_number,
                    "SwiftUI presentation does not belong in shared Infrastructure",
                )
            )

        owner_prefix = PLATFORM_FRAMEWORK_OWNERS.get(module)
        if owner_prefix is not None and not relative_path.startswith(owner_prefix):
            violations.append(
                Violation(
                    "platform-framework-placement",
                    relative_path,
                    line_number,
                    f"{module} belongs under {owner_prefix.rstrip('/')}",
                )
            )
    return violations


def _modern_swift_violations(relative_path: str, source: str) -> list[Violation]:
    violations: list[Violation] = []
    for line_number, code in _source_lines(source):
        if any(pattern.search(code) for pattern in LEGACY_OBSERVATION_PATTERNS):
            violations.append(
                Violation(
                    "legacy-observation",
                    relative_path,
                    line_number,
                    "Use @Observable and @State instead of ObservableObject/@Published",
                )
            )
        if ANY_VIEW_PATTERN.search(code):
            violations.append(
                Violation(
                    "any-view",
                    relative_path,
                    line_number,
                    "Preserve concrete SwiftUI view types instead of AnyView",
                )
            )
    return violations


def _state_declarations(source: str, nominal_ranges: list[tuple[int, int]]):
    declarations: list[StateDeclaration] = []
    violations: list[tuple[int, str]] = []
    for match in STATE_DECLARATION_PATTERN.finditer(source):
        name = match.group("name")
        value_tail = match.group("value")
        line_number = _line_number(source, match.start())
        declarations.append(
            StateDeclaration(
                name=name,
                has_inline_default="=" in value_tail,
                line=line_number,
                owner=_enclosing_nominal_type(match.start(), nominal_ranges),
            )
        )

        attributes = re.findall(r"@([A-Za-z_]\w*)", match.group("attributes"))
        if attributes and attributes != ["Previewable"]:
            violations.append((line_number, name))
    return declarations, violations


def _xcode27_violations(
    relative_path: str,
    source: str,
    configuration: GuardrailConfiguration,
) -> list[Violation]:
    violations: list[Violation] = []
    comment_free_source = _code_without_block_comments(source)
    nominal_ranges = _nominal_type_ranges(comment_free_source)
    state_declarations, composed_states = _state_declarations(
        comment_free_source, nominal_ranges
    )

    for line_number, name in composed_states:
        rule = "xcode27-state-wrapper-composition"
        if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
            violations.append(
                Violation(
                    rule,
                    relative_path,
                    line_number,
                    f"@State property {name} composes another wrapper",
                )
            )

    for initializer_offset, opening_brace, initializer_body in _initializer_bodies(
        comment_free_source
    ):
        owner = _enclosing_nominal_type(initializer_offset, nominal_ranges)
        owned_states = {
            declaration.name: declaration
            for declaration in state_declarations
            if declaration.owner == owner and owner is not None
        }
        assignments = list(SELF_ASSIGNMENT_PATTERN.finditer(initializer_body))
        for index, assignment in enumerate(assignments):
            name = assignment.group("name")
            if name not in owned_states:
                continue
            declaration = owned_states[name]
            if declaration.has_inline_default:
                rule = "xcode27-state-default-init"
                if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
                    violations.append(
                        Violation(
                            rule,
                            relative_path,
                            declaration.line,
                            f"@State property {name} has an inline default and is assigned in init",
                        )
                    )

            later_assignments = assignments[index + 1 :]
            if any(
                later.group("name") not in owned_states
                for later in later_assignments
            ):
                rule = "xcode27-state-initialization-order"
                if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
                    violations.append(
                        Violation(
                            rule,
                            relative_path,
                            _line_number(
                                comment_free_source,
                                opening_brace + 1 + assignment.start(),
                            ),
                            f"Initialize non-State properties before assigning {name}",
                        )
                    )

    for match in TUPLE_VIEW_PATTERN.finditer(comment_free_source):
        rule = "xcode27-tuple-view-constraint"
        if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
            violations.append(
                Violation(
                    rule,
                    relative_path,
                    _line_number(comment_free_source, match.start()),
                    "Prefer opaque content or an explicitly justified TupleContent-compatible shape",
                )
            )

    for line_number, code in _source_lines(comment_free_source):
        if (
            BUILDER_MODIFIER_PATTERN.search(code)
            and BUILDER_STYLE_PATTERN.search(code)
            and " in:" not in code
            and "{" not in code[BUILDER_MODIFIER_PATTERN.search(code).start() :]
        ):
            rule = "xcode27-builder-modifier"
            if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
                violations.append(
                    Violation(
                        rule,
                        relative_path,
                        line_number,
                        "Use the closure-based background/overlay form for modified ShapeStyle content",
                    )
                )

    if "MapKit" in {module for module, _ in _imports(source)}:
        for match in EMPTY_GROUP_PATTERN.finditer(comment_free_source):
            rule = "xcode27-empty-builder"
            if (relative_path, rule) not in configuration.xcode27_pattern_exemptions:
                violations.append(
                    Violation(
                        rule,
                        relative_path,
                        _line_number(comment_free_source, match.start()),
                        "Use an explicit EmptyContent or EmptyView when MapKit is in scope",
                    )
                )

    return violations


def scan_repository(
    repository_root: Path, configuration: GuardrailConfiguration
) -> list[Violation]:
    violations: list[Violation] = []
    for source_root in SOURCE_ROOTS:
        root = repository_root / source_root
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.swift")):
            relative_path = path.relative_to(repository_root).as_posix()
            if _is_excluded(relative_path, configuration):
                continue
            source = path.read_text()
            violations.extend(
                _import_violations(relative_path, source, configuration)
            )
            violations.extend(_modern_swift_violations(relative_path, source))
            violations.extend(
                _xcode27_violations(relative_path, source, configuration)
            )
    return sorted(violations, key=lambda violation: (violation.path, violation.line, violation.rule))


def main() -> int:
    repository_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repository-root",
        type=Path,
        default=repository_root,
        help="Repository root to inspect (defaults to the script's repository).",
    )
    parser.add_argument(
        "--configuration",
        type=Path,
        help="Guardrail allowlist JSON (defaults to Config/ArchitectureGuardrails.json).",
    )
    arguments = parser.parse_args()

    root = arguments.repository_root.resolve()
    configuration_path = arguments.configuration or (
        root / "Config" / "ArchitectureGuardrails.json"
    )
    try:
        configuration = load_configuration(configuration_path)
        violations = scan_repository(root, configuration)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if violations:
        for violation in violations:
            print(
                f"{violation.path}:{violation.line}: error: "
                f"[{violation.rule}] {violation.detail}",
                file=sys.stderr,
            )
        print(
            f"Architecture guard failed with {len(violations)} violation(s).",
            file=sys.stderr,
        )
        return 1

    print("Validated Crest architecture and Xcode 27 source guardrails.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
