pub mod adapters;
pub mod contracts;

use std::process::ExitCode;

pub fn sessions_command(args: Vec<String>) -> ExitCode {
    match args.as_slice() {
        [] => print_list(),
        [single] if single == "list" => print_list(),
        [action, session_id] if action == "resume" => {
            match adapters::resolve_resume_session(session_id) {
                Ok(result) => {
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&result)
                            .expect("resume output should serialize")
                    );
                    ExitCode::SUCCESS
                }
                Err(err) => {
                    eprintln!("{err}");
                    ExitCode::from(1)
                }
            }
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
