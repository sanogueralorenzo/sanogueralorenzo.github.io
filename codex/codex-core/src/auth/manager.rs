use crate::auth::models::{
    AuthPaths, CodexAppRelaunchStatus, ProfileSource, SwitchResult, ValidatedAuthFile,
};
use crate::auth::process::{
    is_codex_app_running, relaunch_codex_app, terminate_running_codex_app_sessions,
};
use crate::auth::util::{
    create_directory_if_needed, list_profile_names, normalize_profile_name, profile_path_for,
    read_validated_auth_file, set_file_permissions, write_secure_atomically,
};
use anyhow::{Context, Result, bail};
use fs2::FileExt;
use std::fs::{self, File, OpenOptions};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

const APP_RESTART_DELAY: Duration = Duration::from_secs(3);

struct FileLock {
    file: File,
}

impl FileLock {
    fn acquire(lock_file: &Path) -> Result<Self> {
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

impl Drop for FileLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

#[derive(Debug)]
pub struct ProfileManager {
    pub paths: AuthPaths,
}

impl ProfileManager {
    pub fn new(home_directory: PathBuf) -> Self {
        Self {
            paths: AuthPaths::new(home_directory),
        }
    }

    pub fn ensure_directories(&self) -> Result<()> {
        create_directory_if_needed(&self.paths.codex_directory, 0o700)?;
        create_directory_if_needed(&self.paths.manager_directory, 0o700)?;
        create_directory_if_needed(&self.paths.profiles_directory, 0o700)?;
        Ok(())
    }

    pub fn list_profiles(&self) -> Result<Vec<String>> {
        self.ensure_directories()?;
        list_profile_names(&self.paths.profiles_directory)
    }

    pub fn save_profile(&self, name: &str, source: ProfileSource) -> Result<String> {
        let normalized_name = normalize_profile_name(name)?;
        self.ensure_directories()?;

        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if profile_path.exists() {
            bail!(
                "A profile with the same normalized name already exists: '{}'.",
                normalized_name
            );
        }

        let current_auth =
            read_validated_auth_file(&self.paths.codex_auth_file).with_context(|| {
                format!(
                    "Cannot save profile because current Codex token is missing or invalid at {}.",
                    self.paths.codex_auth_file.display()
                )
            })?;

        let payload = match source {
            ProfileSource::Current => current_auth.clone(),
            ProfileSource::Path(path) => read_validated_auth_file(&path)?,
        };

        self.ensure_unique_profile_account(&normalized_name, &payload.account_id)?;

        write_secure_atomically(&payload.raw_data, &profile_path)?;
        if payload.account_id == current_auth.account_id {
            self.write_active_account_id(&payload.account_id)?;
        }

        Ok(normalized_name)
    }

    pub fn remove_profile(&self, name: &str) -> Result<()> {
        let normalized_name = normalize_profile_name(name)?;
        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if !profile_path.exists() {
            bail!("Profile '{}' was not found.", normalized_name);
        }

        let removed = read_validated_auth_file(&profile_path)?;
        fs::remove_file(&profile_path)
            .with_context(|| format!("failed removing {}", profile_path.display()))?;

        if self.read_active_account_id().as_deref() == Some(&removed.account_id)
            && self
                .profile_name_for_account_id(&removed.account_id)?
                .is_none()
        {
            self.clear_active_account_id()?;
        }

        Ok(())
    }

    pub fn apply_profile(&self, name: &str) -> Result<SwitchResult> {
        let normalized_name = normalize_profile_name(name)?;
        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if !profile_path.exists() {
            bail!("Profile '{}' was not found.", normalized_name);
        }

        let payload = read_validated_auth_file(&profile_path)?;
        self.apply_validated_auth(
            payload,
            name.trim().to_string(),
            Some(self.read_validated_auth_account_id(&profile_path)?),
        )
    }

    pub fn apply_auth_file(&self, path: &Path) -> Result<SwitchResult> {
        let payload = read_validated_auth_file(path)?;
        let account_id = payload.account_id.clone();
        self.apply_validated_auth(payload, path.display().to_string(), Some(account_id))
    }

    pub fn current_profile_name(&self) -> Result<Option<String>> {
        let current = read_validated_auth_file(&self.paths.codex_auth_file)?;
        self.profile_name_for_account_id(&current.account_id)
    }

    pub fn current_auth_document(&self) -> Result<ValidatedAuthFile> {
        read_validated_auth_file(&self.paths.codex_auth_file)
    }

    pub fn sync_active_profile_with_current_auth(&self) -> Result<bool> {
        self.ensure_directories()?;

        let Some(active_account_id) = self.read_active_account_id() else {
            return Ok(false);
        };

        let current = read_validated_auth_file(&self.paths.codex_auth_file)?;
        if current.account_id != active_account_id {
            return Ok(false);
        }

        let Some(active_name) = self.profile_name_for_account_id(&active_account_id)? else {
            self.clear_active_account_id()?;
            return Ok(false);
        };

        let profile_path = profile_path_for(&self.paths.profiles_directory, &active_name);
        let existing = read_validated_auth_file(&profile_path)?;

        if existing.document_json == current.document_json {
            return Ok(false);
        }

        write_secure_atomically(&current.raw_data, &profile_path)?;
        Ok(true)
    }

    fn apply_validated_auth(
        &self,
        payload: ValidatedAuthFile,
        applied_profile_name: String,
        active_account_id: Option<String>,
    ) -> Result<SwitchResult> {
        let codex_app_was_running = is_codex_app_running();
        if codex_app_was_running {
            terminate_running_codex_app_sessions()?;
            thread::sleep(APP_RESTART_DELAY);
        }

        self.ensure_directories()?;
        let _lock = FileLock::acquire(&self.paths.codex_auth_lock_file)?;

        write_secure_atomically(&payload.raw_data, &self.paths.codex_auth_file)?;
        if let Some(account_id) = active_account_id {
            self.write_active_account_id(&account_id)?;
        } else {
            self.clear_active_account_id()?;
        }

        let codex_app_relaunch_status = if codex_app_was_running {
            thread::sleep(APP_RESTART_DELAY);
            match relaunch_codex_app() {
                Ok(()) => CodexAppRelaunchStatus::Relaunched,
                Err(error) => CodexAppRelaunchStatus::Failed(error.to_string()),
            }
        } else {
            CodexAppRelaunchStatus::NotAttempted
        };

        Ok(SwitchResult {
            applied_profile_name,
            codex_app_relaunch_status,
        })
    }

    fn ensure_unique_profile_account(&self, normalized_name: &str, account_id: &str) -> Result<()> {
        for name in self.list_profiles()? {
            if name == normalized_name {
                continue;
            }
            let path = profile_path_for(&self.paths.profiles_directory, &name);
            let existing = read_validated_auth_file(&path)?;
            if existing.account_id == account_id {
                bail!("A profile for this account already exists: '{}'.", name);
            }
        }
        Ok(())
    }

    fn profile_name_for_account_id(&self, account_id: &str) -> Result<Option<String>> {
        for name in self.list_profiles()? {
            let path = profile_path_for(&self.paths.profiles_directory, &name);
            let profile = read_validated_auth_file(&path)?;
            if profile.account_id == account_id {
                return Ok(Some(name));
            }
        }
        Ok(None)
    }

    fn read_active_account_id(&self) -> Option<String> {
        let data = fs::read(&self.paths.active_account_id_file).ok()?;
        let text = String::from_utf8(data).ok()?;
        let value = text.trim();
        if value.is_empty() {
            None
        } else {
            Some(value.to_string())
        }
    }

    fn write_active_account_id(&self, account_id: &str) -> Result<()> {
        write_secure_atomically(account_id.as_bytes(), &self.paths.active_account_id_file)
    }

    fn clear_active_account_id(&self) -> Result<()> {
        if self.paths.active_account_id_file.exists() {
            fs::remove_file(&self.paths.active_account_id_file).with_context(|| {
                format!(
                    "failed removing {}",
                    self.paths.active_account_id_file.display()
                )
            })?;
        }
        Ok(())
    }
    fn read_validated_auth_account_id(&self, path: &Path) -> Result<String> {
        Ok(read_validated_auth_file(path)?.account_id)
    }
}
