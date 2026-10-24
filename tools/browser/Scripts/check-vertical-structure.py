#!/usr/bin/env python3
"""Check Crest's small set of durable source-organization contracts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import NamedTuple


SOURCE_ROOTS = ("CrestShared", "CrestMac", "CrestMobile")
REQUIRED_CONFORMANCE_SUFFIXES = frozenset(
    {
        "CaseIterable",
        "Codable",
        "Comparable",
        "Decodable",
        "Encodable",
        "Equatable",
        "Error",
        "Hashable",
        "Identifiable",
        "LocalizedError",
        "RawRepresentable",
        "Sendable",
        "View",
        "ViewModifier",
    }
)
LARGE_ROOT_VIEW_BODY_LINE_LIMIT = 180
LARGE_COMPUTED_VIEW_HELPER_LINE_LIMIT = 120
LIVE_PREVIEW_PATTERNS = (
    (
        "Data(contentsOf:)",
        re.compile(
            r"\b(?:Data|NSData|NSImage|String|UIImage)\s*\(\s*"
            r"contentsOf(?:File)?\s*:"
        ),
    ),
    (
        "Data(contentsOf:)",
        re.compile(
            r"\b(?:Data|NSData|NSImage|String|UIImage)\s*\.\s*init\s*"
            r"\(\s*contentsOf(?:File)?\s*:"
        ),
    ),
    (
        "CGImageSourceCreateWithURL",
        re.compile(r"\bCGImageSourceCreateWithURL\s*\("),
    ),
    ("UserDefaults", re.compile(r"\bUserDefaults\b")),
    ("FileManager", re.compile(r"\bFileManager\b")),
    ("FileHandle", re.compile(r"\bFileHandle\b")),
    ("URLSession", re.compile(r"\bURLSession\w*\b")),
    (
        "WKWebsiteDataStore.default",
        re.compile(r"\bWKWebsiteDataStore\s*\.\s*default\s*\("),
    ),
    (
        "WKContentRuleListStore.default",
        re.compile(r"\bWKContentRuleListStore\s*\.\s*default\b"),
    ),
    ("CloudKit", re.compile(r"\b(?:CKContainer|CKDatabase)\b")),
    (
        "Security Keychain",
        re.compile(
            r"\b(?:SecItem\w*|SecurityBrowserSafeStorage|"
            r"SecurityCredentialKeychainStore|"
            r"SystemSecurityCredentialKeychainClient)\b|"
            r"\bKeychainCredentialVault\s*\(\s*\)"
        ),
    ),
    (
        "System Passwords",
        re.compile(r"\bASCredentialDataManager\b"),
    ),
    (
        "BrowserStore.production",
        re.compile(r"\bBrowserStore\s*\.\s*production\s*\("),
    ),
    (
        "BrowserWebsiteDataStore.persistent",
        re.compile(r"\bBrowserWebsiteDataStore\s*\.\s*persistent\b"),
    ),
    (
        "BrowserExtensionControllerPool.production",
        re.compile(
            r"\bBrowserExtensionControllerPool\s*\.\s*production\s*\("
        ),
    ),
    ("AsyncImage", re.compile(r"\bAsyncImage\s*\(")),
    ("WKWebView", re.compile(r"\bWKWebView\s*\(")),
    ("WebView", re.compile(r"(?<![A-Za-z0-9_])WebView\s*\(")),
)
NONDETERMINISTIC_PREVIEW_PATTERNS = (
    ("UUID()", re.compile(r"\bUUID\s*\(\s*\)")),
    ("Date()", re.compile(r"\bDate\s*\(\s*\)")),
    ("now", re.compile(r"\bDate\s*\.\s*now\b")),
    (
        "random",
        re.compile(
            r"(?:\brandom\s*\(|\.\s*random\s*\(|"
            r"\.\s*(?:randomElement|shuffled)\s*\()"
        ),
    ),
)
RULE_REASONS = {
    "extension-file-primary-type": "Keep named extension files extension-only.",
    "extension-file-count": "Keep named extension files scoped to their filename owner.",
    "extension-file-conformance-mismatch": "Match a named conformance extension's + suffix to its protocol.",
    "extension-file-owner-mismatch": "Match the extension target to the owner named before +.",
    "large-computed-view-helper": "Extract the large computed View builder into a named component.",
    "large-root-view-body": "Compose the root screen from narrowly scoped component Views.",
    "preview-live-app-storage": "Move persisted AppStorage ownership out of the previewed View.",
    "preview-live-dependency": "Replace the live preview dependency with an in-memory fixture.",
    "preview-nondeterministic-fixture": "Use fixed preview identities, dates, and fixture values.",
}
RAW_STRING_DELIMITER_PATTERN = re.compile(r'(#+)("""|")')

DECLARATION_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_.])"
    r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|indirect|"
    r"nonisolated(?:\(unsafe\))?|distributed)\s+)*"
    r"(?P<kind>struct|enum|class|actor|protocol|typealias)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
)
EXTENSION_PATTERN = re.compile(
    # `\s` includes newlines. Letting the leading quantifier cross line
    # boundaries makes a masked generated catalog backtrack through every
    # following line while it searches for `extension`.
    r"^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s*)*"
    r"(?:(?:public|internal|private|fileprivate|package|nonisolated)\s+)*"
    r"extension\s+(?P<target>[A-Za-z_][A-Za-z0-9_.]*)\b",
    re.MULTILINE,
)
VISUAL_CONFORMANCE_PATTERN = re.compile(
    r"\b(?:View|ViewModifier|ButtonStyle|PrimitiveButtonStyle|LabelStyle|"
    r"ProgressViewStyle|ToggleStyle|GaugeStyle|ControlGroupStyle|"
    r"DisclosureGroupStyle|GroupBoxStyle|MenuStyle|PickerStyle|"
    r"TextFieldStyle|FormStyle|Shape|Layout|UIViewRepresentable|"
    r"NSViewRepresentable|UIViewControllerRepresentable|"
    r"NSViewControllerRepresentable|UIGestureRecognizerRepresentable|"
    r"NSGestureRecognizerRepresentable|UIView|NSView|UIViewController|"
    r"NSViewController|AVPlayerViewController)\b"
)
PREVIEW_CONFORMANCE_PATTERN = re.compile(
    r"\b(?:View|ButtonStyle|PrimitiveButtonStyle|LabelStyle|"
    r"ProgressViewStyle|ToggleStyle|GaugeStyle|ControlGroupStyle|"
    r"DisclosureGroupStyle|GroupBoxStyle|MenuStyle|PickerStyle|"
    r"TextFieldStyle|FormStyle|Shape|Layout)\b"
)
COMPUTED_VIEW_PATTERN = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?\s+)*"
    r"(?:(?:public|internal|private|fileprivate|package|nonisolated)\s+)*"
    r"var\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*some\s+"
    r"(?:SwiftUI\s*\.\s*)?View\s*\{",
    re.MULTILINE,
)
VIEW_RETURNING_FUNCTION_PATTERN = re.compile(
    r"^[ \t]*(?:(?:public|internal|private|fileprivate|package|nonisolated)\s+)*"
    r"func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b[^{}]{0,2000}?"
    r"->\s*some\s+(?:SwiftUI\s*\.\s*)?View[^{}]{0,500}?\{",
    re.MULTILINE,
)
VIEW_BUILDER_FUNCTION_PATTERN = re.compile(
    r"^[ \t]*@ViewBuilder(?:\([^\n]*\))?\s+"
    r"(?:(?:public|internal|private|fileprivate|package|nonisolated)\s+)*"
    r"func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b[^{}]{0,2000}?\{",
    re.MULTILINE,
)


class PrimaryDeclaration(NamedTuple):
    kind: str
    name: str
    offset: int
    depth: int
    is_private: bool
    is_visual: bool
    requires_preview: bool
    is_view: bool


class ExtensionDeclaration(NamedTuple):
    target: str
    # The outermost name the extension spells, so `extension Owner.Nested`
    # belongs to Owner's scope.
    enclosing_target: str
    conformances: tuple[str, ...]
    offset: int
    is_visual: bool
    requires_preview: bool


class PreviewRange(NamedTuple):
    macro_offset: int
    opening_brace: int
    closing_brace: int


class Violation(NamedTuple):
    rule: str
    path: str
    subject: str
    detail: str

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.rule, self.path, self.subject)


class DebtEntry(NamedTuple):
    rule: str
    path: str
    subject: str
    reason: str

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.rule, self.path, self.subject)


class AuditResult(NamedTuple):
    unexpected: list[Violation]
    stale: list[DebtEntry]


def _masked_source(source: str) -> str:
    """Mask comments and string payloads while preserving layout and braces."""

    output: list[str] = []
    index = 0
    block_comment_depth = 0
    string_delimiter = ""
    raw_hash_count = 0

    while index < len(source):
        if block_comment_depth:
            if source.startswith("/*", index):
                block_comment_depth += 1
                output.extend("  ")
                index += 2
            elif source.startswith("*/", index):
                block_comment_depth -= 1
                output.extend("  ")
                index += 2
            else:
                character = source[index]
                output.append("\n" if character == "\n" else " ")
                index += 1
            continue

        if string_delimiter:
            closing_delimiter = string_delimiter + ("#" * raw_hash_count)
            if source.startswith(closing_delimiter, index):
                output.extend(" " * len(closing_delimiter))
                index += len(closing_delimiter)
                string_delimiter = ""
                raw_hash_count = 0
            else:
                character = source[index]
                if (
                    raw_hash_count == 0
                    and string_delimiter == '"'
                    and character == "\\"
                    and index + 1 < len(source)
                ):
                    output.extend("  ")
                    index += 2
                else:
                    output.append("\n" if character == "\n" else " ")
                    index += 1
            continue

        if source.startswith("//", index):
            newline = source.find("\n", index)
            if newline == -1:
                output.extend(" " * (len(source) - index))
                break
            output.extend(" " * (newline - index))
            output.append("\n")
            index = newline + 1
            continue

        if source.startswith("/*", index):
            block_comment_depth = 1
            output.extend("  ")
            index += 2
            continue

        raw_string_match = RAW_STRING_DELIMITER_PATTERN.match(source, index)
        if raw_string_match is not None:
            hashes, delimiter = raw_string_match.groups()
            token_length = len(hashes) + len(delimiter)
            output.extend(" " * token_length)
            index += token_length
            string_delimiter = delimiter
            raw_hash_count = len(hashes)
            continue

        if source.startswith('"""', index):
            output.extend("   ")
            index += 3
            string_delimiter = '"""'
            continue

        if source[index] == '"':
            output.append(" ")
            index += 1
            string_delimiter = '"'
            continue

        output.append(source[index])
        index += 1

    return "".join(output)


def _brace_depth(source: str, offset: int) -> int:
    prefix = source[:offset]
    return prefix.count("{") - prefix.count("}")


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


def _inheritance_clause(header: str) -> str:
    angle_depth = 0
    parenthesis_depth = 0
    bracket_depth = 0
    inheritance_start: int | None = None

    for index, character in enumerate(header):
        if character == "<":
            angle_depth += 1
        elif character == ">" and angle_depth:
            angle_depth -= 1
        elif character == "(":
            parenthesis_depth += 1
        elif character == ")" and parenthesis_depth:
            parenthesis_depth -= 1
        elif character == "[":
            bracket_depth += 1
        elif character == "]" and bracket_depth:
            bracket_depth -= 1
        elif (
            character == ":"
            and angle_depth == 0
            and parenthesis_depth == 0
            and bracket_depth == 0
        ):
            inheritance_start = index + 1
            break

    if inheritance_start is None:
        return ""
    inheritance = header[inheritance_start:]
    where_match = re.search(r"\bwhere\b", inheritance)
    return inheritance[: where_match.start()] if where_match is not None else inheritance


def _named_declarations(source: str) -> list[PrimaryDeclaration]:
    masked = _masked_source(source)
    declarations: list[PrimaryDeclaration] = []

    for declaration in DECLARATION_PATTERN.finditer(masked):
        if declaration.group("kind") == "typealias":
            candidate_ends = [
                offset
                for offset in (
                    masked.find("\n", declaration.end()),
                    masked.find(";", declaration.end()),
                )
                if offset != -1
            ]
            header_end = min(candidate_ends) if candidate_ends else len(masked)
        else:
            header_end = masked.find("{", declaration.end())
        if header_end == -1:
            header_end = len(masked)
        header = masked[declaration.end() : header_end]
        inheritance = _inheritance_clause(header)
        declarations.append(
            PrimaryDeclaration(
                declaration.group("kind"),
                declaration.group("name"),
                declaration.start(),
                _brace_depth(masked, declaration.start()),
                bool(
                    re.search(
                        r"\b(?:private|fileprivate)\b",
                        declaration.group(0),
                    )
                ),
                VISUAL_CONFORMANCE_PATTERN.search(inheritance) is not None,
                PREVIEW_CONFORMANCE_PATTERN.search(inheritance) is not None,
                re.search(r"\bView\b", inheritance) is not None,
            )
        )

    return declarations


def _primary_declarations(source: str) -> list[PrimaryDeclaration]:
    return [
        declaration
        for declaration in _named_declarations(source)
        if declaration.depth == 0
    ]


def _conformance_names(inheritance: str) -> tuple[str, ...]:
    names: list[str] = []
    component_start = 0
    angle_depth = 0
    parenthesis_depth = 0
    components: list[str] = []
    for index, character in enumerate(inheritance):
        if character == "<":
            angle_depth += 1
        elif character == ">" and angle_depth:
            angle_depth -= 1
        elif character == "(":
            parenthesis_depth += 1
        elif character == ")" and parenthesis_depth:
            parenthesis_depth -= 1
        elif character == "," and angle_depth == 0 and parenthesis_depth == 0:
            components.append(inheritance[component_start:index])
            component_start = index + 1
    components.append(inheritance[component_start:])

    for component in components:
        without_attributes = re.sub(
            r"@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?",
            " ",
            component,
        )
        conformance = re.match(
            r"\s*(?:(?:any|some)\s+)?"
            r"(?P<name>[A-Za-z_][A-Za-z0-9_.]*)",
            without_attributes,
        )
        if conformance is not None:
            names.append(conformance.group("name").split(".")[-1])
    return tuple(names)


def _top_level_extensions(source: str) -> list[ExtensionDeclaration]:
    masked = _masked_source(source)
    declarations: list[ExtensionDeclaration] = []
    for extension in EXTENSION_PATTERN.finditer(masked):
        if _brace_depth(masked, extension.start()) != 0:
            continue
        opening_brace = masked.find("{", extension.end())
        if opening_brace == -1:
            continue
        inheritance = _inheritance_clause(
            masked[extension.end() : opening_brace]
        )
        conformances = _conformance_names(inheritance)
        declarations.append(
            ExtensionDeclaration(
                extension.group("target").split(".")[-1],
                extension.group("target").split(".")[0],
                conformances,
                extension.start(),
                any(
                    VISUAL_CONFORMANCE_PATTERN.fullmatch(name) is not None
                    for name in conformances
                ),
                any(
                    PREVIEW_CONFORMANCE_PATTERN.fullmatch(name) is not None
                    for name in conformances
                ),
            )
        )
    return declarations


def _feature_location(relative_path: str) -> tuple[str, tuple[str, ...]] | None:
    parts = Path(relative_path).parts
    try:
        features_index = parts.index("Features")
    except ValueError:
        return None

    if features_index + 2 >= len(parts):
        return None
    return parts[features_index + 1], parts[features_index + 2 :]


def _preview_ranges(masked_source: str) -> list[PreviewRange]:
    ranges: list[PreviewRange] = []
    for preview in re.finditer(r"(?m)^[ \t]*#Preview\b", masked_source):
        opening_brace = masked_source.find("{", preview.end())
        if opening_brace == -1:
            continue
        closing_brace = _matching_brace(masked_source, opening_brace)
        if closing_brace is None:
            continue
        ranges.append(
            PreviewRange(preview.start(), opening_brace, closing_brace)
        )
    return ranges


def _root_helper_violations(
    relative_path: str, source: str
) -> list[Violation]:
    feature_location = _feature_location(relative_path)
    if feature_location is None:
        return []
    _, feature_relative_parts = feature_location
    directory_parts = feature_relative_parts[:-1]
    masked = _masked_source(source)
    view_ranges: list[tuple[str, int, int]] = []
    for declaration in _primary_declarations(source):
        if not declaration.is_view:
            continue
        opening_brace = masked.find("{", declaration.offset)
        if opening_brace == -1:
            continue
        closing_brace = _matching_brace(masked, opening_brace)
        if closing_brace is None:
            continue
        view_ranges.append((declaration.name, opening_brace, closing_brace))
    for declaration in _top_level_extensions(source):
        if not declaration.requires_preview:
            continue
        opening_brace = masked.find("{", declaration.offset)
        if opening_brace == -1:
            continue
        closing_brace = _matching_brace(masked, opening_brace)
        if closing_brace is None:
            continue
        view_ranges.append(
            (declaration.target, opening_brace, closing_brace)
        )
    violations: list[Violation] = []
    helper_matches = [
        *COMPUTED_VIEW_PATTERN.finditer(masked),
        *VIEW_RETURNING_FUNCTION_PATTERN.finditer(masked),
        *VIEW_BUILDER_FUNCTION_PATTERN.finditer(masked),
    ]
    unique_helpers = {
        (helper.start("name"), helper.group("name")): helper
        for helper in helper_matches
    }
    for helper in unique_helpers.values():
        name = helper.group("name")
        if _brace_depth(masked, helper.start()) != 1:
            continue
        owner = next(
            (
                owner_name
                for owner_name, opening_brace, closing_brace in view_ranges
                if opening_brace < helper.start() < closing_brace
            ),
            None,
        )
        if owner is None:
            continue
        if name == "body" and "Components" in directory_parts:
            continue
        opening_brace = masked.find("{", helper.start(), helper.end() + 1)
        if opening_brace == -1:
            continue
        closing_brace = _matching_brace(masked, opening_brace)
        if closing_brace is None:
            continue
        line_count = masked.count("\n", opening_brace, closing_brace) + 1
        line_limit = (
            LARGE_ROOT_VIEW_BODY_LINE_LIMIT
            if name == "body"
            else LARGE_COMPUTED_VIEW_HELPER_LINE_LIMIT
        )
        if line_count > line_limit:
            if name == "body":
                rule = "large-root-view-body"
                detail = (
                    f"{line_count} lines should compose named component Views"
                )
            else:
                rule = "large-computed-view-helper"
                detail = (
                    f"{line_count} lines should become a named component View"
                )
            violations.append(
                Violation(
                    rule,
                    relative_path,
                    f"{owner}.{name}",
                    detail,
                )
            )
    return violations


def _source_violations(
    repository_root: Path,
    source_path: Path,
) -> list[Violation]:
    relative_path = source_path.relative_to(repository_root).as_posix()
    source = source_path.read_text()
    declarations = _primary_declarations(source)
    extension_declarations = _top_level_extensions(source)
    declaration_names = sorted(declaration.name for declaration in declarations)
    violations: list[Violation] = []

    if "+" in source_path.stem and declarations:
        violations.append(
            Violation(
                "extension-file-primary-type",
                relative_path,
                ",".join(declaration_names),
                "Named extension files may contain extensions only",
            )
        )

    if "+" in source_path.stem:
        extension_targets = [
            declaration.target for declaration in extension_declarations
        ]
        owner_name, extension_suffix = source_path.stem.split("+", maxsplit=1)
        # A type nested in the owner is part of the owner's scope.
        unrelated_targets = sorted(
            {
                declaration.target
                for declaration in extension_declarations
                if owner_name
                not in (declaration.target, declaration.enclosing_target)
            }
        )
        # Infrastructure paths omit the redundant Browser prefix while Swift
        # symbols retain it. Still require one exact owner across the file.
        if (
            relative_path.startswith("CrestShared/Infrastructure/")
            and not owner_name.startswith("Browser")
            and set(extension_targets) == {f"Browser{owner_name}"}
        ):
            unrelated_targets = []
        if not extension_targets:
            violations.append(
                Violation(
                    "extension-file-count",
                    relative_path,
                    "none",
                    "Named extension files contain at least one owner extension",
                )
            )
        elif unrelated_targets:
            violations.append(
                Violation(
                    "extension-file-owner-mismatch",
                    relative_path,
                    ",".join(unrelated_targets),
                    f"Every extension target must be {owner_name}",
                )
            )
        conformances = {
            conformance
            for declaration in extension_declarations
            for conformance in declaration.conformances
        }
        if extension_suffix in REQUIRED_CONFORMANCE_SUFFIXES:
            if extension_suffix not in conformances:
                violations.append(
                    Violation(
                        "extension-file-conformance-mismatch",
                        relative_path,
                        ",".join(sorted(conformances)) or "none",
                        f"+{extension_suffix} requires that conformance",
                    )
                )
    masked_source = _masked_source(source)
    preview_ranges = _preview_ranges(masked_source)
    if preview_ranges:
        live_preview_subjects = sorted(
            {
                subject
                for subject, pattern in LIVE_PREVIEW_PATTERNS
                if pattern.search(masked_source) is not None
            }
        )
        for subject in live_preview_subjects:
            violations.append(
                Violation(
                    "preview-live-dependency",
                    relative_path,
                    subject,
                    "Previews must use deterministic in-memory dependencies",
                )
            )
        if re.search(
            r"@(?:SwiftUI\s*\.\s*)?AppStorage\b",
            masked_source,
        ) is not None:
            violations.append(
                Violation(
                    "preview-live-app-storage",
                    relative_path,
                    "@AppStorage",
                    "Move persistence ownership out of the View before previewing it",
                )
            )
        nondeterministic_subjects = sorted(
            {
                subject
                for subject, pattern in NONDETERMINISTIC_PREVIEW_PATTERNS
                if pattern.search(masked_source) is not None
            }
        )
        for subject in nondeterministic_subjects:
            violations.append(
                Violation(
                    "preview-nondeterministic-fixture",
                    relative_path,
                    subject,
                    "Previews use fixed identities, dates, and fixture values",
                )
            )

    violations.extend(_root_helper_violations(relative_path, source))

    return violations


def scan_repository(repository_root: Path) -> list[Violation]:
    violations: list[Violation] = []
    source_paths: list[Path] = []
    for source_root_name in SOURCE_ROOTS:
        source_root = repository_root / source_root_name
        if not source_root.is_dir():
            continue
        source_paths.extend(sorted(source_root.rglob("*.swift")))
    for source_path in source_paths:
        violations.extend(
            _source_violations(
                repository_root,
                source_path,
            )
        )
    return sorted(violations, key=lambda violation: violation.key)


def load_debt_configuration(configuration_path: Path) -> list[DebtEntry]:
    raw_configuration = json.loads(configuration_path.read_text())
    if not isinstance(raw_configuration, dict):
        raise ValueError("Vertical structure debt configuration must be an object.")
    raw_rules = raw_configuration.get("rules")
    if not isinstance(raw_rules, dict):
        raise ValueError("rules must be an object.")

    entries: list[DebtEntry] = []
    for rule, raw_rule in raw_rules.items():
        if not isinstance(rule, str) or not rule.strip():
            raise ValueError("Each rule name must be a nonempty string.")
        if not isinstance(raw_rule, dict):
            raise ValueError(f"Rule {rule} must be an object.")
        reason = raw_rule.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            raise ValueError(f"Rule {rule} needs a nonempty reason.")
        raw_entries = raw_rule.get("violations")
        if not isinstance(raw_entries, list):
            raise ValueError(f"Rule {rule} violations must be an array.")
        for raw_entry in raw_entries:
            if (
                not isinstance(raw_entry, list)
                or len(raw_entry) != 2
                or not all(
                    isinstance(value, str) and value.strip()
                    for value in raw_entry
                )
            ):
                raise ValueError(
                    f"Each {rule} violation must be a nonempty [path, subject] pair."
                )
            entries.append(DebtEntry(rule, raw_entry[0], raw_entry[1], reason))

    keys = [entry.key for entry in entries]
    if len(keys) != len(set(keys)):
        raise ValueError("Vertical structure debt entries must be unique.")
    if keys != sorted(keys):
        raise ValueError("Vertical structure debt entries must be sorted.")
    return entries


def audit_repository(
    repository_root: Path, configured_debt: list[DebtEntry]
) -> AuditResult:
    violations = scan_repository(repository_root)
    violation_by_key = {violation.key: violation for violation in violations}
    debt_by_key = {entry.key: entry for entry in configured_debt}
    unexpected_keys = sorted(set(violation_by_key) - set(debt_by_key))
    stale_keys = sorted(set(debt_by_key) - set(violation_by_key))
    return AuditResult(
        [violation_by_key[key] for key in unexpected_keys],
        [debt_by_key[key] for key in stale_keys],
    )


def _baseline_json(repository_root: Path) -> str:
    violations = scan_repository(repository_root)
    violations_by_rule: dict[str, list[Violation]] = {}
    for violation in violations:
        violations_by_rule.setdefault(violation.rule, []).append(violation)

    lines = ["{", '  "rules": {']
    rules = sorted(violations_by_rule)
    for rule_index, rule in enumerate(rules):
        lines.append(f"    {json.dumps(rule)}: {{")
        lines.append(
            f'      "reason": {json.dumps(RULE_REASONS.get(rule, "Resolve the tracked vertical organization debt."))},'
        )
        lines.append('      "violations": [')
        rule_violations = violations_by_rule[rule]
        for violation_index, violation in enumerate(rule_violations):
            suffix = "," if violation_index + 1 < len(rule_violations) else ""
            lines.append(
                "        "
                + json.dumps([violation.path, violation.subject])
                + suffix
            )
        lines.append("      ]")
        suffix = "," if rule_index + 1 < len(rules) else ""
        lines.append(f"    }}{suffix}")
    lines.extend(["  }", "}"])
    return "\n".join(lines) + "\n"


def _print_audit(audit: AuditResult) -> None:
    if audit.unexpected:
        print("New vertical-organization violations:", file=sys.stderr)
        for violation in audit.unexpected:
            print(
                f"- {violation.rule}: {violation.path} [{violation.subject}] "
                f"{violation.detail}",
                file=sys.stderr,
            )
    if audit.stale:
        print("Stale vertical-organization debt entries:", file=sys.stderr)
        for entry in audit.stale:
            print(
                f"- {entry.rule}: {entry.path} [{entry.subject}]",
                file=sys.stderr,
            )


def main() -> int:
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=default_root)
    parser.add_argument(
        "--configuration",
        type=Path,
        default=default_root / "Config" / "VerticalStructureDebt.json",
    )
    parser.add_argument(
        "--print-baseline",
        action="store_true",
        help="Print the exact current debt ledger without writing files.",
    )
    arguments = parser.parse_args()

    if arguments.print_baseline:
        print(_baseline_json(arguments.repository_root), end="")
        return 0

    try:
        configured_debt = load_debt_configuration(arguments.configuration)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Invalid vertical structure debt configuration: {error}", file=sys.stderr)
        return 2

    audit = audit_repository(arguments.repository_root, configured_debt)
    _print_audit(audit)
    return 1 if audit.unexpected or audit.stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
