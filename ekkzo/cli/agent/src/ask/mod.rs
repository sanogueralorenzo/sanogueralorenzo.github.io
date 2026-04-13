pub mod adapters;
pub mod contracts;

use contracts::{AskEvent, AskStatus, ProviderName};
use std::io::Write;
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn ask_command(provider_name: &str, args: Vec<String>) -> ExitCode {
    let stdout = std::io::stdout();
    let mut output = stdout.lock();
    ask_command_with_writer(provider_name, args, &mut output)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AskOutputMode {
    Json,
    Text,
}

struct AskCommandInput {
    output_mode: AskOutputMode,
    prompt: String,
}

fn ask_command_with_writer<W: Write>(
    provider_name: &str,
    args: Vec<String>,
    output: &mut W,
) -> ExitCode {
    let ask_input = match parse_args(args) {
        Ok(value) => value,
        Err(usage) => {
            eprintln!("usage:");
            eprintln!("  agent ask [--json] <prompt>");
            eprintln!("{usage}");
            return ExitCode::from(1);
        }
    };

    let Some(provider) = ProviderName::from_provider_name(provider_name) else {
        eprintln!("unknown provider '{provider_name}'");
        return ExitCode::from(1);
    };

    let id = new_ask_id();

    if let Err(err) = print_event(
        output,
        ask_input.output_mode,
        &AskEvent::thinking(provider, id.clone()),
    ) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }

    let result = match adapters::ask_with_provider(provider_name, &ask_input.prompt) {
        Ok(value) => value,
        Err(err) => {
            eprintln!("{err}");
            return ExitCode::from(1);
        }
    };

    let final_event = AskEvent::new(provider, id, result.status, result.answer, result.error);

    if let Err(err) = print_event(output, ask_input.output_mode, &final_event) {
        eprintln!("{err}");
        return ExitCode::from(1);
    }

    ExitCode::SUCCESS
}

fn parse_args(args: Vec<String>) -> Result<AskCommandInput, String> {
    if args.is_empty() {
        return Err("missing prompt".to_string());
    }

    let mut output_mode = AskOutputMode::Text;
    let mut prompt_tokens: Vec<String> = Vec::new();

    for arg in args {
        if arg == "--json" {
            output_mode = AskOutputMode::Json;
            continue;
        }

        if arg.starts_with("--") {
            return Err(format!("unsupported flag '{arg}'"));
        }

        prompt_tokens.push(arg);
    }

    if prompt_tokens.is_empty() {
        return Err("missing prompt".to_string());
    }

    Ok(AskCommandInput {
        output_mode,
        prompt: prompt_tokens.join(" "),
    })
}

fn print_event<W: Write>(
    output: &mut W,
    output_mode: AskOutputMode,
    event: &AskEvent,
) -> Result<(), String> {
    match output_mode {
        AskOutputMode::Json => print_json_event(output, event),
        AskOutputMode::Text => print_text_event(output, event),
    }
}

fn print_json_event<W: Write>(output: &mut W, event: &AskEvent) -> Result<(), String> {
    let serialized = serde_json::to_string(event)
        .map_err(|err| format!("failed to serialize ask event: {err}"))?;
    writeln!(output, "{serialized}").map_err(|err| format!("failed writing ask event: {err}"))?;
    Ok(())
}

fn print_text_event<W: Write>(output: &mut W, event: &AskEvent) -> Result<(), String> {
    match event.status {
        AskStatus::Thinking => writeln!(
            output,
            "[{}] {} {}",
            provider_name(event.provider),
            event.id,
            status_name(event.status)
        )
        .map_err(|err| format!("failed writing ask event: {err}"))?,
        AskStatus::Completed => writeln!(
            output,
            "[{}] {} {}{}",
            provider_name(event.provider),
            event.id,
            status_name(event.status),
            event
                .answer
                .as_ref()
                .map(|answer| format!(": {answer}"))
                .unwrap_or_default()
        )
        .map_err(|err| format!("failed writing ask event: {err}"))?,
        AskStatus::Interrupted | AskStatus::Failed => writeln!(
            output,
            "[{}] {} {}{}",
            provider_name(event.provider),
            event.id,
            status_name(event.status),
            event
                .error
                .as_ref()
                .map(|error| format!(": {}", error.message))
                .unwrap_or_default()
        )
        .map_err(|err| format!("failed writing ask event: {err}"))?,
    };

    Ok(())
}

fn provider_name(provider: ProviderName) -> &'static str {
    match provider {
        ProviderName::Openai => "openai",
        ProviderName::Anthropic => "anthropic",
        ProviderName::Google => "google",
    }
}

fn status_name(status: AskStatus) -> &'static str {
    match status {
        AskStatus::Thinking => "thinking",
        AskStatus::Completed => "completed",
        AskStatus::Interrupted => "interrupted",
        AskStatus::Failed => "failed",
    }
}

fn new_ask_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos())
        .unwrap_or_default();
    format!("ask-{nanos}")
}

#[cfg(test)]
mod tests {
    use super::ask_command_with_writer;
    use std::env;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::{Mutex, OnceLock};
    use std::time::{SystemTime, UNIX_EPOCH};
    const OPENAI_ASK_BIN_ENV: &str = "AGENT_OPENAI_ASK_BIN";
    const ANTHROPIC_ASK_BIN_ENV: &str = "AGENT_ANTHROPIC_ASK_BIN";
    const GOOGLE_ASK_BIN_ENV: &str = "AGENT_GOOGLE_ASK_BIN";

    #[test]
    fn json_mode_emits_stable_contract_for_openai() {
        let _guard = env_lock().lock().expect("env lock should be acquired");
        let fixtures = create_fake_provider_bins().expect("fixtures should be created");
        let _env = configure_fake_binaries(&fixtures);

        let mut output = Vec::new();
        let code = ask_command_with_writer(
            "openai",
            vec!["--json".to_string(), "hello".to_string()],
            &mut output,
        );

        assert_eq!(code, std::process::ExitCode::SUCCESS);
        let lines = parse_lines(&output);
        assert_eq!(lines.len(), 2);

        assert_eq!(json_field(&lines[0], "provider"), Some("openai"));
        assert_eq!(json_field(&lines[0], "status"), Some("thinking"));
        assert_eq!(json_field(&lines[1], "provider"), Some("openai"));
        assert_eq!(json_field(&lines[1], "status"), Some("completed"));
        assert_eq!(json_field(&lines[1], "answer"), Some("openai-answer"));
    }

    #[test]
    fn json_mode_maps_interrupted_for_google() {
        let _guard = env_lock().lock().expect("env lock should be acquired");
        let fixtures = create_fake_provider_bins().expect("fixtures should be created");
        let _env = configure_fake_binaries(&fixtures);

        let mut output = Vec::new();
        let code = ask_command_with_writer(
            "google",
            vec!["--json".to_string(), "cancel".to_string()],
            &mut output,
        );

        assert_eq!(code, std::process::ExitCode::SUCCESS);
        let lines = parse_lines(&output);
        assert_eq!(lines.len(), 2);
        assert_eq!(json_field(&lines[1], "provider"), Some("google"));
        assert_eq!(json_field(&lines[1], "status"), Some("interrupted"));
    }

    #[test]
    fn json_mode_maps_failed_for_anthropic() {
        let _guard = env_lock().lock().expect("env lock should be acquired");
        let fixtures = create_fake_provider_bins().expect("fixtures should be created");
        let _env = configure_fake_binaries(&fixtures);

        let mut output = Vec::new();
        let code = ask_command_with_writer(
            "anthropic",
            vec!["--json".to_string(), "boom".to_string()],
            &mut output,
        );

        assert_eq!(code, std::process::ExitCode::SUCCESS);
        let lines = parse_lines(&output);
        assert_eq!(lines.len(), 2);
        assert_eq!(json_field(&lines[1], "provider"), Some("anthropic"));
        assert_eq!(json_field(&lines[1], "status"), Some("failed"));
        assert_eq!(json_nested_field(&lines[1], "error", "code"), Some("7"));
    }

    #[test]
    fn default_mode_emits_human_output() {
        let _guard = env_lock().lock().expect("env lock should be acquired");
        let fixtures = create_fake_provider_bins().expect("fixtures should be created");
        let _env = configure_fake_binaries(&fixtures);

        let mut output = Vec::new();
        let code = ask_command_with_writer("openai", vec!["hello".to_string()], &mut output);

        assert_eq!(code, std::process::ExitCode::SUCCESS);
        let text = String::from_utf8(output).expect("output should be utf-8");
        assert!(text.contains("[openai]"));
        assert!(text.contains("thinking"));
        assert!(text.contains("completed"));
        assert!(!text.trim_start().starts_with('{'));
    }

    #[test]
    fn transport_failure_exits_non_zero_without_final_event() {
        let _guard = env_lock().lock().expect("env lock should be acquired");
        let fixtures = create_fake_provider_bins().expect("fixtures should be created");
        let _env = configure_fake_binaries(&fixtures);
        let _override = ScopedEnvVar::set(OPENAI_ASK_BIN_ENV, "definitely-missing-openai-bin");

        let mut output = Vec::new();
        let code = ask_command_with_writer(
            "openai",
            vec!["--json".to_string(), "hello".to_string()],
            &mut output,
        );

        assert_eq!(code, std::process::ExitCode::from(1));
        let lines = parse_lines(&output);
        assert_eq!(lines.len(), 1);
        assert_eq!(json_field(&lines[0], "provider"), Some("openai"));
        assert_eq!(json_field(&lines[0], "status"), Some("thinking"));
    }

    fn parse_lines(output: &[u8]) -> Vec<serde_json::Value> {
        let text = String::from_utf8(output.to_vec()).expect("output should be utf-8");
        text.lines()
            .map(|line| {
                serde_json::from_str::<serde_json::Value>(line).expect("line should be json")
            })
            .collect()
    }

    fn json_field<'a>(value: &'a serde_json::Value, key: &str) -> Option<&'a str> {
        value.get(key).and_then(serde_json::Value::as_str)
    }

    fn json_nested_field<'a>(
        value: &'a serde_json::Value,
        key: &str,
        nested: &str,
    ) -> Option<&'a str> {
        value
            .get(key)
            .and_then(|nested_value| nested_value.get(nested))
            .and_then(serde_json::Value::as_str)
    }

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    struct FakeProviderBins {
        bin_dir: PathBuf,
    }

    impl FakeProviderBins {
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

    fn create_fake_provider_bins() -> Result<FakeProviderBins, String> {
        let destination_root = temp_dir("agent-ask-fixtures");
        let destination_bin = destination_root.join("bin");
        copy_dir_recursively(&fixture_bin_dir(), &destination_bin)?;
        set_dir_executable(&destination_bin)?;
        Ok(FakeProviderBins {
            bin_dir: destination_bin,
        })
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
            for entry in fs::read_dir(path)
                .map_err(|err| format!("failed to read {}: {err}", path.display()))?
            {
                let entry = entry
                    .map_err(|err| format!("failed to read entry in {}: {err}", path.display()))?;
                let entry_path = entry.path();
                if !entry_path.is_file() {
                    continue;
                }
                let mut permissions = fs::metadata(&entry_path)
                    .map_err(|err| {
                        format!("failed to read {} metadata: {err}", entry_path.display())
                    })?
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

        for entry in fs::read_dir(source)
            .map_err(|err| format!("failed to read {}: {err}", source.display()))?
        {
            let entry = entry
                .map_err(|err| format!("failed to read entry in {}: {err}", source.display()))?;
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

    fn configure_fake_binaries(fixtures: &FakeProviderBins) -> [ScopedEnvVar; 3] {
        [
            ScopedEnvVar::set(OPENAI_ASK_BIN_ENV, &fixtures.openai_bin()),
            ScopedEnvVar::set(ANTHROPIC_ASK_BIN_ENV, &fixtures.anthropic_bin()),
            ScopedEnvVar::set(GOOGLE_ASK_BIN_ENV, &fixtures.google_bin()),
        ]
    }

    struct ScopedEnvVar {
        key: &'static str,
        previous: Option<String>,
    }

    impl ScopedEnvVar {
        fn set(key: &'static str, value: &str) -> Self {
            let previous = env::var(key).ok();
            unsafe {
                env::set_var(key, value);
            }
            Self { key, previous }
        }
    }

    impl Drop for ScopedEnvVar {
        fn drop(&mut self) {
            match &self.previous {
                Some(value) => unsafe {
                    env::set_var(self.key, value);
                },
                None => unsafe {
                    env::remove_var(self.key);
                },
            }
        }
    }
}
