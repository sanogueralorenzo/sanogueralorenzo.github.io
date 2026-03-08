use crate::manager::ProfileManager;
use crate::models::SwitchResult;
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
    println!("Applied auth from {}", result.source_description);
    println!("Updated: {}", result.destination.display());

    if result.invalidation.had_targets() {
        println!("Invalidated Codex sessions:");
        println!(
            "  app processes terminated: {}",
            result.invalidation.terminated_app_pids.len()
        );
        println!(
            "  cli processes terminated: {}",
            result.invalidation.terminated_cli_pids.len()
        );

        if !result.invalidation.terminated_app_pids.is_empty() {
            println!(
                "  app PIDs: {}",
                join_i32(&result.invalidation.terminated_app_pids)
            );
        }
        if !result.invalidation.terminated_cli_pids.is_empty() {
            println!(
                "  cli PIDs: {}",
                join_i32(&result.invalidation.terminated_cli_pids)
            );
        }
        if !result.invalidation.failed_pids.is_empty() {
            println!(
                "  failed to terminate PIDs: {}",
                join_i32(&result.invalidation.failed_pids)
            );
        }
    } else {
        println!("No running Codex app/CLI sessions were detected.");
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

fn join_i32(values: &[i32]) -> String {
    values
        .iter()
        .map(|v| v.to_string())
        .collect::<Vec<String>>()
        .join(", ")
}
