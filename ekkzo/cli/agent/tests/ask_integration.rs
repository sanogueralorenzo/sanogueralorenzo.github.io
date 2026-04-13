use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

const OPENAI_ASK_BIN_ENV: &str = "AGENT_OPENAI_ASK_BIN";
const ANTHROPIC_ASK_BIN_ENV: &str = "AGENT_ANTHROPIC_ASK_BIN";
const GOOGLE_ASK_BIN_ENV: &str = "AGENT_GOOGLE_ASK_BIN";

#[test]
fn ask_json_emits_stable_contract_for_openai() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_ask(&workspace, "openai", &["ask", "--json", "hello"])
        .expect("agent ask should run");

    assert!(output.status.success());
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);

    assert_eq!(json_field(&events[0], "provider"), Some("openai"));
    assert_eq!(json_field(&events[0], "status"), Some("thinking"));
    assert_eq!(json_field(&events[0], "id"), json_field(&events[1], "id"));

    assert_eq!(json_field(&events[1], "provider"), Some("openai"));
    assert_eq!(json_field(&events[1], "status"), Some("completed"));
    assert_eq!(json_field(&events[1], "answer"), Some("openai-answer"));
    assert!(events[1].get("error").is_some_and(Value::is_null));
}

#[test]
fn ask_json_maps_interrupted_for_google() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_ask(&workspace, "google", &["ask", "--json", "cancel"])
        .expect("agent ask should run");

    assert_eq!(output.status.code(), Some(0));
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[1], "provider"), Some("google"));
    assert_eq!(json_field(&events[1], "status"), Some("interrupted"));
    assert!(events[1].get("answer").is_some_and(Value::is_null));
}

#[test]
fn ask_json_maps_failed_for_anthropic() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output = run_agent_ask(&workspace, "anthropic", &["ask", "--json", "boom"])
        .expect("agent ask should run");

    assert_eq!(output.status.code(), Some(0));
    let events = parse_json_lines(&output.stdout);
    assert_eq!(events.len(), 2);
    assert_eq!(json_field(&events[1], "provider"), Some("anthropic"));
    assert_eq!(json_field(&events[1], "status"), Some("failed"));
    assert_eq!(
        events[1]
            .get("error")
            .and_then(|value| value.get("code"))
            .and_then(Value::as_str),
        Some("7")
    );
}

#[test]
fn ask_without_json_is_human_readable() {
    let workspace = create_fixture_workspace().expect("workspace should be created");
    let output =
        run_agent_ask(&workspace, "openai", &["ask", "hello"]).expect("agent ask should run");

    assert!(output.status.success());
    let text = String::from_utf8(output.stdout).expect("stdout should be utf-8");
    assert!(text.contains("[openai]"));
    assert!(text.contains("thinking"));
    assert!(text.contains("completed"));
    assert!(!text.trim_start().starts_with('{'));
}

fn run_agent_ask(
    workspace: &FixtureWorkspace,
    provider: &str,
    args: &[&str],
) -> Result<std::process::Output, String> {
    let agent_bin = env!("CARGO_BIN_EXE_agent");
    let mut cmd = Command::new(agent_bin);
    cmd.args(args)
        .env("HOME", &workspace.home_dir)
        .env(OPENAI_ASK_BIN_ENV, workspace.openai_bin())
        .env(ANTHROPIC_ASK_BIN_ENV, workspace.anthropic_bin())
        .env(GOOGLE_ASK_BIN_ENV, workspace.google_bin());

    set_provider(&workspace.home_dir, provider)?;

    cmd.output()
        .map_err(|err| format!("failed running agent binary: {err}"))
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

impl FixtureWorkspace {
    fn openai_bin(&self) -> String {
        self.bin_dir.join("codex").to_string_lossy().into_owned()
    }

    fn anthropic_bin(&self) -> String {
        self.bin_dir.join("claude").to_string_lossy().into_owned()
    }

    fn google_bin(&self) -> String {
        self.bin_dir.join("gemini").to_string_lossy().into_owned()
    }
}

fn create_fixture_workspace() -> Result<FixtureWorkspace, String> {
    let root = temp_dir("agent-ask-integration");
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
        .join("ask")
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
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("time should be valid")
        .as_nanos();
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "{prefix}-{}-{suffix}-{counter}",
        std::process::id()
    ));
    fs::create_dir_all(&path).expect("temp dir should be created");
    path
}
