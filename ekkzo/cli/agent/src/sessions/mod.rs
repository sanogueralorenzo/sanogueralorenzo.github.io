pub mod adapters;
pub mod contracts;

use std::path::Path;
use std::process::{Command, ExitCode, Stdio};

pub fn sessions_command(args: Vec<String>) -> ExitCode {
    match args.as_slice() {
        [] => print_list(),
        [single] if single == "list" => print_list(),
        [action, session_id] if action == "resume" => resume_session(session_id, false),
        [action, session_id, flag] if action == "resume" && flag == "--dry-run" => {
            resume_session(session_id, true)
        }
        [action, flag, session_id] if action == "resume" && flag == "--dry-run" => {
            resume_session(session_id, true)
        }
        [action, session_id] if action == "delete" => {
            match adapters::delete_session_all_providers(session_id) {
                Ok(summary) => {
                    if summary.total_deleted == 0 {
                        eprintln!("session '{session_id}' was not found in any provider");
                        return ExitCode::from(1);
                    }
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&summary)
                            .expect("delete output should serialize")
                    );
                    ExitCode::SUCCESS
                }
                Err(err) => {
                    eprintln!("{err}");
                    ExitCode::from(1)
                }
            }
        }
        [single] if single == "deleteAll" || single == "delete-all" => {
            match adapters::delete_all_sessions_all_providers() {
                Ok(summary) => {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&summary)
                            .expect("deleteAll output should serialize")
                    );
                    ExitCode::SUCCESS
                }
                Err(err) => {
                    eprintln!("{err}");
                    ExitCode::from(1)
                }
            }
        }
        _ => {
            eprintln!("usage:");
            eprintln!("  agent sessions list");
            eprintln!("  agent sessions resume <id>");
            eprintln!("  agent sessions resume <id> --dry-run");
            eprintln!("  agent sessions delete <id>");
            eprintln!("  agent sessions deleteAll");
            ExitCode::from(1)
        }
    }
}

fn print_list() -> ExitCode {
    match adapters::list_sessions_all_providers() {
        Ok(sessions) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&sessions).expect("sessions output should serialize")
            );
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn resume_session(session_id: &str, dry_run: bool) -> ExitCode {
    match adapters::resolve_resume_session(session_id) {
        Ok(result) => {
            if dry_run {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&result)
                        .expect("resume output should serialize")
                );
                return ExitCode::SUCCESS;
            }

            run_resume_command(&result)
        }
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn run_resume_command(result: &adapters::ResumeSessionResult) -> ExitCode {
    match run_resume_command_code(result) {
        Ok(0) => ExitCode::SUCCESS,
        Ok(code) => ExitCode::from(code.clamp(1, 255) as u8),
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn run_resume_command_code(result: &adapters::ResumeSessionResult) -> Result<i32, String> {
    if result.command.is_empty() {
        return Err("resume command is empty".to_string());
    }

    let mut command = Command::new(&result.command[0]);
    command.args(&result.command[1..]);
    command.stdin(Stdio::inherit());
    command.stdout(Stdio::inherit());
    command.stderr(Stdio::inherit());

    if !result.cwd.trim().is_empty() && Path::new(&result.cwd).exists() {
        command.current_dir(&result.cwd);
    }

    let status = match command.status() {
        Ok(value) => value,
        Err(err) => return Err(format!("failed to run resume command '{}': {err}", result.command[0])),
    };

    Ok(status.code().unwrap_or(1))
}

#[cfg(test)]
mod tests {
    use super::adapters::{
        ProviderSessionRoots, delete_all_sessions_all_providers_with_roots,
        delete_session_all_providers_with_roots, list_sessions_all_providers_with_roots,
    };
    use super::{adapters::ResumeSessionResult, run_resume_command_code};
    use crate::sessions::contracts::SessionProvider;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn fixture_based_list_delete_and_delete_all_work_across_all_providers() {
        let workspace_root = copy_fixture_workspace().expect("fixture workspace should copy");
        let roots = ProviderSessionRoots {
            openai_root: Some(workspace_root.join("openai").join(".codex")),
            anthropic_projects_root: Some(
                workspace_root.join("anthropic").join(".claude").join("projects"),
            ),
            google_tmp_root: Some(workspace_root.join("google").join(".gemini").join("tmp")),
        };

        let initial = list_sessions_all_providers_with_roots(&roots).expect("list should work");
        assert_eq!(initial.len(), 6);
        assert!(
            initial
                .iter()
                .any(|session| session.id == "shared-session" && session.provider == super::contracts::SessionProvider::OpenAi)
        );
        assert!(
            initial
                .iter()
                .any(|session| session.id == "shared-session" && session.provider == super::contracts::SessionProvider::Anthropic)
        );
        assert!(
            initial
                .iter()
                .any(|session| session.id == "shared-session" && session.provider == super::contracts::SessionProvider::Google)
        );

        let deleted_shared = delete_session_all_providers_with_roots("shared-session", &roots)
            .expect("delete should work");
        assert_eq!(deleted_shared.total_deleted, 3);

        let after_single_delete =
            list_sessions_all_providers_with_roots(&roots).expect("list should work");
        assert_eq!(after_single_delete.len(), 3);
        assert!(
            after_single_delete
                .iter()
                .all(|session| session.id != "shared-session")
        );

        let deleted_all =
            delete_all_sessions_all_providers_with_roots(&roots).expect("deleteAll should work");
        assert_eq!(deleted_all.total_deleted, 3);

        let after_delete_all =
            list_sessions_all_providers_with_roots(&roots).expect("list should work");
        assert!(after_delete_all.is_empty());
    }

    #[test]
    fn resume_command_execution_returns_success_exit_code() {
        let result = ResumeSessionResult {
            provider: SessionProvider::OpenAi,
            id: "test".to_string(),
            name: "test".to_string(),
            cwd: "/".to_string(),
            updated_at: "0".to_string(),
            command: vec!["/bin/sh".to_string(), "-c".to_string(), "exit 0".to_string()],
        };

        let code = run_resume_command_code(&result).expect("command should run");
        assert_eq!(code, 0);
    }

    #[test]
    fn resume_command_execution_returns_process_exit_code() {
        let result = ResumeSessionResult {
            provider: SessionProvider::OpenAi,
            id: "test".to_string(),
            name: "test".to_string(),
            cwd: "/".to_string(),
            updated_at: "0".to_string(),
            command: vec!["/bin/sh".to_string(), "-c".to_string(), "exit 7".to_string()],
        };

        let code = run_resume_command_code(&result).expect("command should run");
        assert_eq!(code, 7);
    }

    fn copy_fixture_workspace() -> Result<PathBuf, String> {
        let source = fixture_root();
        let destination = temp_dir("agent-sessions-fixtures");
        copy_dir_recursively(&source, &destination)?;
        Ok(destination)
    }

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests")
            .join("fixtures")
            .join("sessions")
    }

    fn temp_dir(prefix: &str) -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be valid")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("{prefix}-{suffix}"));
        fs::create_dir_all(&path).expect("temp dir should be created");
        path
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
}
