use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct SearchResult {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub keywords: Vec<String>,
    pub category: String,
}

pub struct Index {
    entries: Vec<SearchResult>,
}

impl Index {
    pub fn build(roots: &[PathBuf], max_entries: usize) -> Self {
        let mut entries = Vec::new();
        for root in roots {
            walk(root, max_entries, &mut entries);
            if entries.len() >= max_entries {
                break;
            }
        }
        Self { entries }
    }

    pub fn search(&self, query: &str) -> Vec<SearchResult> {
        let needle = query.trim().to_lowercase();
        if needle.is_empty() {
            return Vec::new();
        }
        self.entries
            .iter()
            .filter(|entry| {
                format!("{} {}", entry.title, entry.keywords.join(" "))
                    .to_lowercase()
                    .contains(&needle)
            })
            .cloned()
            .collect()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

fn walk(directory: &Path, max_entries: usize, results: &mut Vec<SearchResult>) {
    if results.len() >= max_entries {
        return;
    }
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        if results.len() >= max_entries {
            return;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') || name == "node_modules" || name == "dist" {
            continue;
        }
        let path = entry.path();
        let is_directory = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
        let is_app = name.ends_with(".app") || name.ends_with(".desktop");
        if is_directory && !is_app {
            walk(&path, max_entries, results);
            continue;
        }
        let category = if is_app { "app" } else { "file" };
        let title = if is_app {
            name.trim_end_matches(".app")
                .trim_end_matches(".desktop")
                .to_string()
        } else {
            name.clone()
        };
        let path_string = path.to_string_lossy().to_string();
        results.push(SearchResult {
            id: format!("rust:{}:{}", category, path_string),
            title,
            subtitle: path_string.clone(),
            keywords: vec![path_string],
            category: category.to_string(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::Index;
    use std::fs::{create_dir_all, write};

    #[test]
    fn indexes_apps_and_files_and_filters_queries() {
        let root = std::env::temp_dir().join(format!("palette-indexer-{}", std::process::id()));
        let nested = root.join("nested");
        let _ = std::fs::remove_dir_all(&root);
        create_dir_all(&nested).unwrap();
        create_dir_all(root.join("Demo.app")).unwrap();
        write(nested.join("project-notes.md"), "notes").unwrap();

        let index = Index::build(std::slice::from_ref(&root), 100);
        assert_eq!(index.len(), 2);
        assert_eq!(index.search("demo")[0].category, "app");
        assert_eq!(index.search("project-notes")[0].category, "file");
        assert!(index.search("").is_empty());
        let _ = std::fs::remove_dir_all(root);
    }
}
