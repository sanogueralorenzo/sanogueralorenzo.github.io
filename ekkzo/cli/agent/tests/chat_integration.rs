use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn chat_new_openai_emits_completed_contract() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(&workspace, "openai", &["chat", "--new", "hello-openai"])
        .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[0], "provider"), Some("openai"));
    assert_eq!(json_field(&events[0], "id"), Some("openai-session-new"));
    assert_eq!(json_field(&events[0], "status"), Some("thinking"));
    assert_eq!(json_field(&events[1], "provider"), Some("openai"));
    assert_eq!(json_field(&events[1], "id"), Some("openai-session-new"));
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
    assert_eq!(json_field(&events[1], "answer"), Some("openai-success"));
}

#[test]
fn chat_id_openai_uses_existing_conversation_id() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(
        &workspace,
        "openai",
        &["chat", "--id", "openai-session-existing", "resume-openai"],
    )
    .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(
        json_field(&events[0], "id"),
        Some("openai-session-existing")
    );
    assert_eq!(
        json_field(&events[1], "id"),
        Some("openai-session-existing")
    );
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
}

#[test]
fn chat_openai_failed_turn_maps_failed_status() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(&workspace, "openai", &["chat", "--new", "FAIL-openai-turn"])
        .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[1], "provider"), Some("openai"));
    assert_eq!(json_field(&events[1], "status"), Some("failed"));
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("message"))
            .and_then(Value::as_str),
        Some("openai-failed")
    );
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("code"))
            .and_then(Value::as_str),
        Some("openai_code")
    );
}

#[test]
fn chat_new_anthropic_emits_completed_contract() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(
        &workspace,
        "anthropic",
        &["chat", "--new", "hello-anthropic"],
    )
    .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[0], "provider"), Some("anthropic"));
    assert_eq!(json_field(&events[0], "id"), Some("anthropic-session-new"));
    assert_eq!(json_field(&events[1], "provider"), Some("anthropic"));
    assert_eq!(json_field(&events[1], "id"), Some("anthropic-session-new"));
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
    assert_eq!(json_field(&events[1], "answer"), Some("anthropic-success"));
}

#[test]
fn chat_id_anthropic_uses_existing_conversation_id() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(
        &workspace,
        "anthropic",
        &[
            "chat",
            "--id",
            "anthropic-session-existing",
            "resume-anthropic",
        ],
    )
    .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(
        json_field(&events[0], "id"),
        Some("anthropic-session-existing")
    );
    assert_eq!(
        json_field(&events[1], "id"),
        Some("anthropic-session-existing")
    );
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
}

#[test]
fn chat_anthropic_failed_turn_maps_failed_status() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(
        &workspace,
        "anthropic",
        &["chat", "--new", "FAIL-anthropic-turn"],
    )
    .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[1], "provider"), Some("anthropic"));
    assert_eq!(json_field(&events[1], "status"), Some("failed"));
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("message"))
            .and_then(Value::as_str),
        Some("anthropic-failed")
    );
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("code"))
            .and_then(Value::as_str),
        Some("anthropic_code")
    );
}

#[test]
fn chat_new_google_emits_completed_contract() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(&workspace, "google", &["chat", "--new", "hello-google"])
        .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    let first_id = json_field(&events[0], "id").expect("id should exist");
    assert!(first_id.starts_with("session-"));
    assert_eq!(json_field(&events[0], "provider"), Some("google"));
    assert_eq!(json_field(&events[0], "status"), Some("thinking"));
    assert_eq!(json_field(&events[1], "provider"), Some("google"));
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
    assert_eq!(json_field(&events[1], "id"), Some(first_id));
    assert_eq!(json_field(&events[1], "answer"), Some("google-success"));
}

#[test]
fn chat_id_google_uses_existing_conversation_id() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(
        &workspace,
        "google",
        &["chat", "--id", "google-session-existing", "resume-google"],
    )
    .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(
        json_field(&events[0], "id"),
        Some("google-session-existing")
    );
    assert_eq!(
        json_field(&events[1], "id"),
        Some("google-session-existing")
    );
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
}

#[test]
fn chat_google_failed_turn_maps_failed_status() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_chat(&workspace, "google", &["chat", "--new", "FAIL-google-turn"])
        .expect("agent chat should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[1], "provider"), Some("google"));
    assert_eq!(json_field(&events[1], "status"), Some("failed"));
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("message"))
            .and_then(Value::as_str),
        Some("google-failed")
    );
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("code"))
            .and_then(Value::as_str),
        Some("-32001")
    );
}

fn run_agent_chat(
    workspace: &FixtureWorkspace,
    provider: &str,
    args: &[&str],
) -> Result<std::process::Output, String> {
    set_provider(&workspace.home_dir, provider)?;

    let path_value = std::env::var("PATH").unwrap_or_default();
    let merged_path = format!("{}:{path_value}", workspace.bin_dir.display());

    let mut cmd = Command::new(env!("CARGO_BIN_EXE_agent"));
    cmd.args(args)
        .env("HOME", &workspace.home_dir)
        .env("PATH", merged_path);

    cmd.output()
        .map_err(|err| format!("failed running agent chat: {err}"))
}

fn set_provider(home_dir: &Path, provider: &str) -> Result<(), String> {
    let provider_path = home_dir.join(".config").join("agent").join("provider");
    let provider_parent = provider_path
        .parent()
        .ok_or_else(|| format!("invalid provider path: {}", provider_path.display()))?;
    fs::create_dir_all(provider_parent)
        .map_err(|err| format!("failed to create {}: {err}", provider_parent.display()))?;
    fs::write(&provider_path, format!("{provider}\n"))
        .map_err(|err| format!("failed to write {}: {err}", provider_path.display()))
}

fn parse_json_lines(output: &[u8]) -> Vec<Value> {
    let text = String::from_utf8(output.to_vec()).expect("output should be utf-8");
    text.lines()
        .map(|line| serde_json::from_str::<Value>(line).expect("line should be valid json"))
        .collect()
}

fn json_field<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

struct FixtureWorkspace {
    home_dir: PathBuf,
    bin_dir: PathBuf,
}

fn create_fixture_workspace() -> Result<FixtureWorkspace, String> {
    let root = temp_dir("agent-chat-integration");
    let home_dir = root.join("home");
    let bin_dir = root.join("bin");
    fs::create_dir_all(&home_dir)
        .map_err(|err| format!("failed to create {}: {err}", home_dir.display()))?;
    copy_dir_recursively(&fixture_bin_dir(), &bin_dir)?;
    set_dir_executable(&bin_dir)?;

    Ok(FixtureWorkspace { home_dir, bin_dir })
}

fn fixture_bin_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
        .join("chat")
        .join("bin")
}

fn set_dir_executable(path: &Path) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        for entry in
            fs::read_dir(path).map_err(|err| format!("failed to read {}: {err}", path.display()))?
        {
            let entry = entry
                .map_err(|err| format!("failed to read entry in {}: {err}", path.display()))?;
            let entry_path = entry.path();
            if !entry_path.is_file() {
                continue;
            }
            let mut permissions = fs::metadata(&entry_path)
                .map_err(|err| format!("failed to read {} metadata: {err}", entry_path.display()))?
                .permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(&entry_path, permissions)
                .map_err(|err| format!("failed to chmod {}: {err}", entry_path.display()))?;
        }
    }

    Ok(())
}

fn copy_dir_recursively(source: &Path, destination: &Path) -> Result<(), String> {
    if !source.exists() {
        return Err(format!("fixture path does not exist: {}", source.display()));
    }

    fs::create_dir_all(destination)
        .map_err(|err| format!("failed to create {}: {err}", destination.display()))?;

    for entry in
        fs::read_dir(source).map_err(|err| format!("failed to read {}: {err}", source.display()))?
    {
        let entry =
            entry.map_err(|err| format!("failed to read entry in {}: {err}", source.display()))?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());
        let file_type = entry
            .file_type()
            .map_err(|err| format!("failed to inspect {}: {err}", source_path.display()))?;

        if file_type.is_dir() {
            copy_dir_recursively(&source_path, &destination_path)?;
        } else if file_type.is_file() {
            fs::copy(&source_path, &destination_path).map_err(|err| {
                format!(
                    "failed to copy {} -> {}: {err}",
                    source_path.display(),
                    destination_path.display()
                )
            })?;
        }
    }

    Ok(())
}

fn temp_dir(prefix: &str) -> PathBuf {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time should be valid")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("{prefix}-{suffix}"));
    fs::create_dir_all(&path).expect("temp dir should be created");
    path
}
