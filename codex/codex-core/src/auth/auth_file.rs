use crate::auth::models::ValidatedAuthFile;
use anyhow::{Context, Result, bail};
use fs2::FileExt;
use serde_json::Value;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub struct AuthFileLock {
    file: File,
}

impl AuthFileLock {
    pub fn acquire(lock_file: &Path) -> Result<Self> {
        if let Some(parent) = lock_file.parent() {
            create_directory_if_needed(parent, 0o700)?;
        }

        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(lock_file)
            .with_context(|| format!("Failed to open lock file: {}", lock_file.display()))?;
        set_file_permissions(lock_file, 0o600)?;

        file.lock_exclusive()
            .with_context(|| format!("Failed to lock auth file: {}", lock_file.display()))?;

        Ok(Self { file })
    }
}

impl Drop for AuthFileLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
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

    let id_token = token_value(&document_json, "id_token");
    let access_token = token_value(&document_json, "access_token");
    let refresh_token = token_value(&document_json, "refresh_token");

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

    let tmp = temporary_auth_path(parent, destination);
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

fn token_value(document_json: &Value, key: &str) -> String {
    document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get(key))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn temporary_auth_path(parent: &Path, destination: &Path) -> std::path::PathBuf {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));

    parent.join(format!(
        ".tmp-{}-{}-{}",
        std::process::id(),
        now.as_nanos(),
        destination
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or("auth")
    ))
}
