use std::path::PathBuf;
use uuid::Uuid;

pub fn temp_file_path(prefix: &str, extension: &str) -> PathBuf {
    let suffix = Uuid::new_v4();
    let mut path = std::env::temp_dir();
    path.push(format!("{prefix}-{suffix}.{extension}"));
    path
}
