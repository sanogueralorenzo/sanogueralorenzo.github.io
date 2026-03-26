use crate::core::events::parse_last_agent_message_from_events;
use crate::noninteractive::cli::WrapperOptions;
use crate::noninteractive::result::ResultJson;
use std::fs;
use std::path::{Path, PathBuf};

pub fn render_final_message(
    options: &WrapperOptions,
    events_text: &str,
    output_last_message: &Path,
) -> String {
    if options.raw_jsonl {
        return String::new();
    }

    let from_file = fs::read_to_string(output_last_message).unwrap_or_default();
    let text = if from_file.is_empty() {
        parse_last_agent_message_from_events(events_text).unwrap_or_default()
    } else {
        from_file
    };
    print!("{text}");
    text
}

pub fn cleanup_managed_file(is_managed: bool, path: &Path) {
    if is_managed {
        let _ = fs::remove_file(path);
    }
}

pub fn write_result_json(path: &PathBuf, result: &ResultJson) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let serialized = serde_json::to_string_pretty(result)
        .map_err(|error| std::io::Error::other(error.to_string()))?;
    fs::write(path, format!("{serialized}\n"))
}
