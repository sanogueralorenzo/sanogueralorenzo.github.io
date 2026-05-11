use anyhow::{Context, Result};
use std::env;
use std::path::PathBuf;

pub fn resolve_home(override_home: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = override_home {
        return Ok(expand_tilde(path));
    }

    let home = env::var("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home))
}

pub fn expand_tilde(path: PathBuf) -> PathBuf {
    let raw = path.to_string_lossy();
    if raw == "~" {
        if let Ok(home) = env::var("HOME") {
            return PathBuf::from(home);
        }
        return path;
    }

    if let Some(rest) = raw.strip_prefix("~/")
        && let Ok(home) = env::var("HOME")
    {
        return PathBuf::from(home).join(rest);
    }

    path
}
