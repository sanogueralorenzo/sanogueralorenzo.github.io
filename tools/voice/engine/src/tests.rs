use super::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct FixtureFile<T> {
    version: u32,
    operation: String,
    cases: Vec<T>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PreprocessFixture {
    name: String,
    input: String,
    expected_text: String,
    expected_changed: bool,
    expected_applied_rule_ids: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NormalizationFixtures {
    version: u32,
    operation: String,
    compose_input_cases: Vec<TextFixture>,
    instruction_input_cases: Vec<TextFixture>,
    compose_output_cases: Vec<TextFixture>,
    clean_model_output_cases: Vec<CleanModelOutputFixture>,
}

#[derive(Deserialize)]
struct TextFixture {
    name: String,
    input: String,
    expected: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CleanModelOutputFixture {
    name: String,
    input: String,
    bullet_mode: bool,
    expected: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PostprocessFixture {
    name: String,
    original_text: String,
    model_output: String,
    list_mode: bool,
    expected: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EditAnalysisFixtures {
    version: u32,
    operation: String,
    cases: Vec<EditAnalysisFixture>,
    allow_blank_output_cases: Vec<AllowBlankOutputFixture>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EditAnalysisFixture {
    name: String,
    instruction: String,
    expected_normalized_instruction: String,
    expected_intent: String,
    expected_strict_edit_command: bool,
}

#[derive(Deserialize)]
struct AllowBlankOutputFixture {
    intent: String,
    expected: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeterministicEditFixtures {
    version: u32,
    operation: String,
    cases: Vec<DeterministicEditFixture>,
    null_cases: Vec<NullEditFixture>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeterministicEditFixture {
    name: String,
    source_text: String,
    instruction: String,
    expected: ExpectedDeterministicEdit,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExpectedDeterministicEdit {
    output: String,
    applied: bool,
    intent: String,
    scope: String,
    command_kind: String,
    matched_count: usize,
    rule_confidence: String,
    no_match_detected: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NullEditFixture {
    name: String,
    source_text: String,
    instruction: String,
}

#[derive(Deserialize)]
struct BooleanFixture {
    name: String,
    input: String,
    expected: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReplacementCasingFixture {
    name: String,
    source_text: String,
    instruction: String,
    edited_output: String,
    expected: String,
}

fn parse_fixture<T>(json: &str) -> FixtureFile<T>
where
    T: for<'de> Deserialize<'de>,
{
    let file: FixtureFile<T> = serde_json::from_str(json).expect("fixture json should parse");
    assert_eq!(1, file.version);
    file
}

fn parse_edit_intent(value: &str) -> EditIntent {
    match value {
        "GENERAL" => EditIntent::General,
        "DELETE_ALL" => EditIntent::DeleteAll,
        "REPLACE" => EditIntent::Replace,
        _ => panic!("unknown edit intent: {value}"),
    }
}

fn assert_deterministic_edit(
    case_name: &str,
    actual: DeterministicEditResult,
    expected: ExpectedDeterministicEdit,
) {
    assert_eq!(expected.output, actual.output, "{case_name}");
    assert_eq!(expected.applied, actual.applied, "{case_name}");
    assert_eq!(expected.intent, actual.intent.as_str(), "{case_name}");
    assert_eq!(expected.scope, actual.scope.as_str(), "{case_name}");
    assert_eq!(
        expected.command_kind,
        actual.command_kind.as_str(),
        "{case_name}"
    );
    assert_eq!(expected.matched_count, actual.matched_count, "{case_name}");
    assert_eq!(
        expected.rule_confidence,
        actual.rule_confidence.as_str(),
        "{case_name}"
    );
    assert_eq!(
        expected.no_match_detected, actual.no_match_detected,
        "{case_name}"
    );
}

#[test]
fn preprocess_applies_rules_in_order() {
    let result = preprocess("um meet meet me in 5 mins");

    assert_eq!("meet me in 5 minutes", result.text);
    assert_eq!(
        vec!["FILLER", "ADJACENT_DUPLICATE", "MINUTES_NORMALIZATION"],
        result.applied_rules
    );
}

#[test]
fn preprocess_applies_correction_before_number_conversion() {
    let result = preprocess("at five, no at six");

    assert_eq!("at 6", result.text);
    assert_eq!(
        vec!["CORRECTION_TURN", "NUMBER_WORDS_TO_DIGITS"],
        result.applied_rules
    );
}

#[test]
fn clean_model_output_matches_spoken_number_guards() {
    assert_eq!(
        "The code is 123",
        clean_model_output("the code is one, two, three", false)
    );
    assert_eq!(
        "The code is one twenty three",
        clean_model_output("the code is one twenty three", false)
    );
    assert_eq!(
        "The code is twenty one five",
        clean_model_output("the code is twenty one five", false)
    );
}

#[test]
fn postprocess_rejects_assistant_reply() {
    assert_eq!(
        "buy milk and bread",
        postprocess("buy milk and bread", "Sure, buy milk and bread", false)
    );
}

#[test]
fn conformance_preprocess_matches_fixtures() {
    let file: FixtureFile<PreprocessFixture> =
        parse_fixture(include_str!("../fixtures/preprocess.json"));
    assert_eq!("preprocess", file.operation);

    for case in file.cases {
        let result = preprocess(&case.input);
        assert_eq!(case.expected_text, result.text, "{}", case.name);
        assert_eq!(case.expected_changed, result.changed, "{}", case.name);
        assert_eq!(
            case.expected_applied_rule_ids, result.applied_rules,
            "{}",
            case.name
        );
    }
}

#[test]
fn conformance_normalization_matches_fixtures() {
    let file: NormalizationFixtures =
        serde_json::from_str(include_str!("../fixtures/normalization.json"))
            .expect("normalization fixture json should parse");
    assert_eq!(1, file.version);
    assert_eq!("normalization", file.operation);

    for case in file.compose_input_cases {
        assert_eq!(
            case.expected,
            normalize_compose_input(&case.input),
            "{}",
            case.name
        );
    }
    for case in file.instruction_input_cases {
        assert_eq!(
            case.expected,
            normalize_instruction_input(&case.input),
            "{}",
            case.name
        );
    }
    for case in file.compose_output_cases {
        assert_eq!(
            case.expected,
            normalize_compose_output_text(&case.input),
            "{}",
            case.name
        );
    }
    for case in file.clean_model_output_cases {
        assert_eq!(
            case.expected,
            clean_model_output(&case.input, case.bullet_mode),
            "{}",
            case.name
        );
    }
}

#[test]
fn conformance_postprocess_matches_fixtures() {
    let file: FixtureFile<PostprocessFixture> =
        parse_fixture(include_str!("../fixtures/postprocess.json"));
    assert_eq!("postprocess", file.operation);

    for case in file.cases {
        assert_eq!(
            case.expected,
            postprocess(&case.original_text, &case.model_output, case.list_mode),
            "{}",
            case.name
        );
    }
}

#[test]
fn conformance_edit_analysis_matches_fixtures() {
    let file: EditAnalysisFixtures =
        serde_json::from_str(include_str!("../fixtures/edit_analysis.json"))
            .expect("edit analysis fixture json should parse");
    assert_eq!(1, file.version);
    assert_eq!("edit_analysis", file.operation);

    for case in file.cases {
        let analysis = analyze_instruction(&case.instruction);
        assert_eq!(
            case.expected_normalized_instruction, analysis.normalized_instruction,
            "{}",
            case.name
        );
        assert_eq!(
            case.expected_intent,
            analysis.intent.as_str(),
            "{}",
            case.name
        );
        assert_eq!(
            case.expected_strict_edit_command,
            is_strict_edit_command(&case.instruction),
            "{}",
            case.name
        );
    }

    for case in file.allow_blank_output_cases {
        assert_eq!(
            case.expected,
            should_allow_blank_output(parse_edit_intent(&case.intent)),
            "{}",
            case.intent
        );
    }
}

#[test]
fn conformance_deterministic_edits_match_fixtures() {
    let file: DeterministicEditFixtures =
        serde_json::from_str(include_str!("../fixtures/deterministic_edits.json"))
            .expect("deterministic edit fixture json should parse");
    assert_eq!(1, file.version);
    assert_eq!("deterministic_edits", file.operation);

    for case in file.cases {
        let actual = try_apply_deterministic_edit(&case.source_text, &case.instruction)
            .unwrap_or_else(|| panic!("expected deterministic edit result: {}", case.name));
        assert_deterministic_edit(&case.name, actual, case.expected);
    }

    for case in file.null_cases {
        assert!(
            try_apply_deterministic_edit(&case.source_text, &case.instruction).is_none(),
            "{}",
            case.name
        );
    }
}

#[test]
fn conformance_list_detection_matches_fixtures() {
    let file: FixtureFile<BooleanFixture> =
        parse_fixture(include_str!("../fixtures/list_detection.json"));
    assert_eq!("list_detection", file.operation);

    for case in file.cases {
        assert_eq!(case.expected, looks_like_list(&case.input), "{}", case.name);
    }
}

#[test]
fn conformance_replacement_casing_matches_fixtures() {
    let file: FixtureFile<ReplacementCasingFixture> =
        parse_fixture(include_str!("../fixtures/replacement_casing.json"));
    assert_eq!("replacement_casing", file.operation);

    for case in file.cases {
        assert_eq!(
            case.expected,
            post_replace_capitalization(&case.source_text, &case.instruction, &case.edited_output),
            "{}",
            case.name
        );
    }
}

#[test]
fn contract_jni_text_fields_replace_field_separator() {
    assert_eq!(
        "hello world",
        sanitize_field(&format!("hello{FIELD_SEPARATOR}world"))
    );
}
