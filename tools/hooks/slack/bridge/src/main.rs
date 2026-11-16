mod config;
mod errors;
mod process;
mod runtime;
mod server;

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

fn resolve(path: &Path) -> std::io::Result<PathBuf> {
    if path.exists() {
        return path.canonicalize();
    }
    let parent = resolve(
        path.parent()
            .ok_or_else(|| std::io::Error::other("Invalid home"))?,
    )?;
    Ok(parent.join(
        path.file_name()
            .ok_or_else(|| std::io::Error::other("Invalid home"))?,
    ))
}
fn private_home(path: PathBuf) -> Result<PathBuf, String> {
    let path = if path.is_absolute() {
        path
    } else {
        std::env::current_dir()
            .map_err(|_| "Cannot read current directory")?
            .join(path)
    };
    let home = resolve(&path).map_err(|_| "Cannot resolve private home")?;
    for path in [&home, &home.join("extension"), &home.join("hooks")] {
        let path = resolve(path).map_err(|_| "Cannot resolve private home")?;
        if path.ancestors().any(|parent| parent.join(".git").exists()) {
            return Err("Keep private Browser Hooks files outside the public repository".into());
        }
    }
    Ok(home)
}
async fn run() -> Result<(), String> {
    let mut args = std::env::args().skip(1);
    let action = args.next().unwrap_or_else(|| "--help".into());
    if ["--help", "-h"].contains(&action.as_str()) {
        println!("Slack bridge: serve --home PATH [--port PORT] | config --home PATH");
        return Ok(());
    }
    if !["serve", "config"].contains(&action.as_str()) {
        return Err("Expected serve or config".into());
    }
    let mut home = None;
    let mut port = 19736u16;
    while let Some(flag) = args.next() {
        let value = args.next().ok_or("Missing option value")?;
        match flag.as_str() {
            "--home" => home = Some(PathBuf::from(value)),
            "--port" if action == "serve" => port = value.parse().map_err(|_| "Invalid port")?,
            _ => return Err("Unknown option".into()),
        }
    }
    let home = private_home(home.ok_or("--home is required")?)?;
    if action == "config" {
        let config = config::Config::load(&home.join("hooks/slack/config.json"))?;
        println!(
            "{}",
            serde_json::json!({"keywords": config.commands.keys().collect::<Vec<_>>()})
        );
        Ok(())
    } else {
        server::serve(home, port, Duration::from_secs(600)).await
    }
}
#[tokio::main(flavor = "current_thread")]
async fn main() {
    unsafe {
        libc::umask(0o077);
    }
    if let Err(error) = run().await {
        eprintln!("Browser Hooks: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_data_inside_a_git_checkout_is_rejected_before_writing() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::write(temp.path().join(".git"), "synthetic-worktree").unwrap();
        let home = temp.path().join("private");
        assert!(private_home(home.clone()).is_err());
        assert!(!home.exists());
    }
}
