use std::env;
use std::fs;
use std::path::PathBuf;

const PROVIDER_CONFIG_FILE: &str = "provider";
const CONFIG_ENV: &str = "AGENT_CONFIG_PATH";

pub fn load_provider_name() -> Result<Option<String>, String> {
    let path = provider_config_path()?;
    if !path.exists() {
        return Ok(None);
    }

    let raw = fs::read_to_string(&path)
        .map_err(|err| format!("cannot read {}: {err}", path.display()))?;
    let value = raw.trim().to_string();
    if value.is_empty() {
        return Ok(None);
    }

    Ok(Some(value))
}

pub fn save_provider_name(provider: &str) -> Result<(), String> {
    let path = provider_config_path()?;
    let parent = path
        .parent()
        .ok_or_else(|| format!("invalid config path: {}", path.display()))?;

    fs::create_dir_all(parent)
        .map_err(|err| format!("cannot create {}: {err}", parent.display()))?;
    fs::write(&path, format!("{provider}\n"))
        .map_err(|err| format!("cannot write {}: {err}", path.display()))
}

fn provider_config_path() -> Result<PathBuf, String> {
    if let Ok(custom_path) = env::var(CONFIG_ENV) {
        let trimmed = custom_path.trim();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed).join(PROVIDER_CONFIG_FILE));
        }
    }

    let home = env::var("HOME").map_err(missing_home_error)?;
    Ok(PathBuf::from(home)
        .join(".config")
        .join("agent")
        .join(PROVIDER_CONFIG_FILE))
}

fn missing_home_error(err: env::VarError) -> String {
    match err {
        env::VarError::NotPresent => "HOME is not set".to_string(),
        env::VarError::NotUnicode(_) => "HOME is not valid UTF-8".to_string(),
    }
}
