use crate::auth::manager::ProfileManager;
use crate::auth::models::{CodexAppRelaunchStatus, SwitchResult};
use anyhow::Result;

pub fn print_profiles(manager: &ProfileManager, plain: bool) -> Result<()> {
    let current = manager.current_profile_name()?;
    let profiles = manager.list_profiles()?;

    if profiles.is_empty() {
        if !plain {
            println!("No saved profiles");
        }
        return Ok(());
    }

    if plain {
        for name in profiles {
            println!("{name}");
        }
        return Ok(());
    }

    println!("Profiles:");
    for name in profiles {
        if current.as_deref() == Some(name.as_str()) {
            println!("* {name}");
        } else {
            println!("  {name}");
        }
    }

    Ok(())
}

pub fn print_use_result(result: SwitchResult) {
    match result.codex_app_relaunch_status {
        CodexAppRelaunchStatus::NotAttempted => {
            println!(
                "Profile {} applied, please restart Codex",
                result.applied_profile_name
            );
        }
        CodexAppRelaunchStatus::Relaunched => {
            println!(
                "Profile {} applied, restarting Codex",
                result.applied_profile_name
            );
        }
        CodexAppRelaunchStatus::Failed(message) => {
            println!(
                "Profile {} applied, restarting Codex",
                result.applied_profile_name
            );
            println!("Failed to reopen Codex automatically: {message}");
        }
    }
}

pub fn masked(value: &str) -> String {
    if value.chars().count() <= 8 {
        return "*".repeat(value.chars().count());
    }

    let prefix: String = value.chars().take(4).collect();
    let suffix: String = value
        .chars()
        .rev()
        .take(4)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    format!("{prefix}...{suffix}")
}
