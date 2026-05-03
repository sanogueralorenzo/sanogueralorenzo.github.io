use anyhow::{Context, Result, bail};
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};

use crate::auth::auth_file::read_validated_auth_file;

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

pub fn ensure_unique_profile_account(
    profiles_dir: &Path,
    normalized_name: &str,
    account_id: &str,
) -> Result<()> {
    for name in list_profile_names(profiles_dir)? {
        if name == normalized_name {
            continue;
        }

        let path = profile_path_for(profiles_dir, &name);
        let existing = read_validated_auth_file(&path)?;
        if existing.account_id == account_id {
            bail!("A profile for this account already exists: '{}'.", name);
        }
    }

    Ok(())
}

pub fn profile_name_for_account_id(
    profiles_dir: &Path,
    account_id: &str,
) -> Result<Option<String>> {
    for name in list_profile_names(profiles_dir)? {
        let path = profile_path_for(profiles_dir, &name);
        let profile = read_validated_auth_file(&path)?;
        if profile.account_id == account_id {
            return Ok(Some(name));
        }
    }

    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::normalize_profile_name;

    #[test]
    fn normalizes_profile_names() {
        assert_eq!(normalize_profile_name("Mario Main").unwrap(), "mario-main");
        assert_eq!(
            normalize_profile_name("  Team__Prod  ").unwrap(),
            "team-prod"
        );
    }

    #[test]
    fn rejects_empty_profile_names() {
        assert!(normalize_profile_name("   ").is_err());
    }
}
