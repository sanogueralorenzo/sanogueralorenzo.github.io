use crate::models::ValidatedAuthFile;
use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::env;
use std::ffi::OsStr;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub fn normalize_profile_name(name: &str) -> Result<String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        bail!(
            "Invalid profile name '{}'. Use at least one letter or number; names are normalized to lowercase-with-dashes.",
            name
        );
    }

    let mut normalized = String::new();
    let mut previous_was_separator = false;

    for ch in trimmed.chars() {
        if ch.is_alphanumeric() {
            for lower in ch.to_lowercase() {
                normalized.push(lower);
            }
            previous_was_separator = false;
        } else if !normalized.is_empty() && !previous_was_separator {
            normalized.push('-');
            previous_was_separator = true;
        }
    }

    while normalized.ends_with('-') {
        normalized.pop();
    }

    if normalized.is_empty() {
        bail!(
            "Invalid profile name '{}'. Use at least one letter or number; names are normalized to lowercase-with-dashes.",
            name
        );
    }

    Ok(normalized)
}

pub fn resolve_home(override_home: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = override_home {
        return Ok(expand_tilde(path));
    }

    let home = env::var("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home))
}

pub fn expand_tilde(path: PathBuf) -> PathBuf {
    let raw = path.to_string_lossy();
    if raw == "~" || raw.starts_with("~/") {
        if let Ok(home) = env::var("HOME") {
            if raw == "~" {
                return PathBuf::from(home);
            }
            return PathBuf::from(home).join(raw.trim_start_matches("~/"));
        }
    }
    path
}

pub fn create_directory_if_needed(path: &Path, mode: u32) -> Result<()> {
    if !path.exists() {
        fs::create_dir_all(path).with_context(|| format!("failed creating {}", path.display()))?;
    }
    set_file_permissions(path, mode)
}

pub fn set_file_permissions(path: &Path, mode: u32) -> Result<()> {
    let perms = fs::Permissions::from_mode(mode);
    fs::set_permissions(path, perms)
        .with_context(|| format!("Failed setting secure permissions on {}", path.display()))?;
    Ok(())
}

pub fn list_profile_names(profiles_dir: &Path) -> Result<Vec<String>> {
    let mut names = Vec::new();

    for entry in fs::read_dir(profiles_dir)
        .with_context(|| format!("failed reading {}", profiles_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension() != Some(OsStr::new("json")) {
            continue;
        }

        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };

        names.push(stem.to_string());
    }

    names.sort();
    Ok(names)
}

pub fn profile_path_for(profiles_dir: &Path, name: &str) -> PathBuf {
    profiles_dir.join(format!("{name}.json"))
}

pub fn read_validated_auth_file(path: &Path) -> Result<ValidatedAuthFile> {
    if !path.exists() {
        bail!("File not found: {}", path.display());
    }

    let raw_data = fs::read(path).with_context(|| format!("failed reading {}", path.display()))?;
    let document_json: Value = serde_json::from_slice(&raw_data).map_err(|_| {
        anyhow::anyhow!(
            "Invalid auth file at {}. Expected Codex auth.json format.",
            path.display()
        )
    })?;

    let auth_mode = document_json
        .get("auth_mode")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let account_id = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("account_id"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let id_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("id_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let access_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("access_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let refresh_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("refresh_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    if auth_mode.is_empty()
        || id_token.is_empty()
        || access_token.is_empty()
        || refresh_token.is_empty()
        || account_id.is_empty()
    {
        bail!(
            "Invalid auth file at {}. Expected Codex auth.json format.",
            path.display()
        );
    }

    Ok(ValidatedAuthFile {
        raw_data,
        document_json,
        auth_mode,
        account_id,
    })
}

pub fn write_secure_atomically(data: &[u8], destination: &Path) -> Result<()> {
    let Some(parent) = destination.parent() else {
        bail!("invalid destination path: {}", destination.display());
    };
    create_directory_if_needed(parent, 0o700)?;

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let tmp = parent.join(format!(
        ".tmp-{}-{}-{}",
        std::process::id(),
        now.as_nanos(),
        destination
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or("auth")
    ));

    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&tmp)
        .with_context(|| format!("Failed to create temporary auth file at {}", tmp.display()))?;

    if let Err(error) = (|| -> Result<()> {
        file.write_all(data)
            .with_context(|| format!("failed writing {}", tmp.display()))?;
        file.flush().ok();
        set_file_permissions(&tmp, 0o600)?;
        fs::rename(&tmp, destination).with_context(|| {
            format!(
                "Failed replacing {} with temporary auth file {}",
                destination.display(),
                tmp.display()
            )
        })?;
        set_file_permissions(destination, 0o600)?;
        Ok(())
    })() {
        let _ = fs::remove_file(&tmp);
        return Err(error);
    }

    Ok(())
}

pub fn is_executable(path: &Path) -> bool {
    if let Ok(metadata) = fs::metadata(path) {
        metadata.permissions().mode() & 0o111 != 0
    } else {
        false
    }
}
