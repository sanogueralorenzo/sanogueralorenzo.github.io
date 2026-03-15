use std::env;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, ExitCode, Stdio};

fn main() -> ExitCode {
    let forwarded_args: Vec<_> = env::args_os().skip(1).collect();

    let status = match Command::new("codex")
        .arg("app-server")
        .args(forwarded_args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
    {
        Ok(status) => status,
        Err(error) => {
            eprintln!("failed to launch codex app-server: {error}");
            return ExitCode::from(1);
        }
    };

    if let Some(code) = status.code() {
        return ExitCode::from(u8::try_from(code).unwrap_or(1));
    }

    if let Some(signal) = status.signal() {
        let code = (128 + signal).clamp(0, 255) as u8;
        return ExitCode::from(code);
    }

    ExitCode::from(1)
}
