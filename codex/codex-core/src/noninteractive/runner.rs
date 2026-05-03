use crate::core::events::parse_thread_id_from_events;
use crate::core::process::exit_code_from_status;
use crate::core::temp::temp_file_path;
use crate::noninteractive::cli::WrapperOptions;
use crate::noninteractive::command::build_codex_command;
use crate::noninteractive::output::{
    cleanup_managed_file, render_final_message, write_result_json,
};
use crate::noninteractive::prompt::load_prompt_bytes;
use crate::noninteractive::result::ResultJson;
use std::process::Stdio;

pub fn run_wrapper(mode: &str, options: WrapperOptions) -> u8 {
    let mut managed_output_last_message = false;
    let output_last_message = if let Some(path) = options.output_last_message.clone() {
        path
    } else {
        managed_output_last_message = true;
        temp_file_path("codex-core-last-message", "txt")
    };

    let prompt_bytes =
        match load_prompt_bytes(&options, managed_output_last_message, &output_last_message) {
            Ok(stdin_bytes) => stdin_bytes,
            Err(exit_code) => return exit_code,
        };

    let mut command = build_codex_command(mode, &options, &output_last_message);
    if prompt_bytes.is_some() {
        command.stdin(Stdio::piped());
    }
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            if error.kind() == std::io::ErrorKind::NotFound {
                eprintln!("Missing 'codex' CLI in PATH.");
            } else {
                eprintln!("Failed to launch codex exec: {error}");
            }
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
    };

    if let Some(bytes) = prompt_bytes
        && let Some(mut stdin) = child.stdin.take()
        && let Err(error) = std::io::Write::write_all(&mut stdin, &bytes)
    {
        eprintln!("Failed to write prompt to codex stdin: {error}");
        cleanup_managed_file(managed_output_last_message, &output_last_message);
        return 1;
    }

    let output = match child.wait_with_output() {
        Ok(output) => output,
        Err(error) => {
            eprintln!("Failed waiting for codex exec: {error}");
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
    };

    let exit_code = i32::from(exit_code_from_status(&output.status));
    let events_text = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr_text = String::from_utf8_lossy(&output.stderr).to_string();

    if !stderr_text.is_empty() {
        eprint!("{stderr_text}");
    }
    if options.emit_events {
        eprint!("{events_text}");
    }
    if options.raw_jsonl {
        print!("{events_text}");
    }

    let final_message = render_final_message(&options, &events_text, &output_last_message);
    let thread_id = parse_thread_id_from_events(&events_text);

    if let Some(path) = options.result_json
        && let Err(error) = write_result_json(
            &path,
            &ResultJson::from_execution(
                exit_code,
                thread_id,
                final_message.clone(),
                stderr_text.clone(),
            ),
        )
    {
        eprintln!("Failed to write result JSON '{}': {error}", path.display());
        cleanup_managed_file(managed_output_last_message, &output_last_message);
        return 1;
    }

    cleanup_managed_file(managed_output_last_message, &output_last_message);

    if exit_code != 0 {
        eprintln!("codex exec failed with exit code {exit_code}");
        return u8::try_from(exit_code).unwrap_or(1);
    }

    0
}
