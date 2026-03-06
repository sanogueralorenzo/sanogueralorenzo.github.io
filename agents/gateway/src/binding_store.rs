use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::fs;
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct BindingStore {
    file_path: PathBuf,
    lock: Arc<Mutex<()>>,
}

impl BindingStore {
    pub fn new(file_path: PathBuf) -> Self {
        Self {
            file_path,
            lock: Arc::new(Mutex::new(())),
        }
    }

    pub async fn get(&self, chat_id: &str) -> Result<Option<String>> {
        let _guard = self.lock.lock().await;
        let bindings = self.read_all().await?;
        Ok(bindings.get(chat_id).cloned())
    }

    pub async fn set(&self, chat_id: &str, thread_id: &str) -> Result<()> {
        let _guard = self.lock.lock().await;
        let mut bindings = self.read_all().await?;
        bindings.insert(chat_id.to_string(), thread_id.to_string());
        self.write_all(&bindings).await
    }

    pub async fn remove(&self, chat_id: &str) -> Result<bool> {
        let _guard = self.lock.lock().await;
        let mut bindings = self.read_all().await?;
        let existed = bindings.remove(chat_id).is_some();
        if existed {
            self.write_all(&bindings).await?;
        }
        Ok(existed)
    }

    async fn ensure_file(&self) -> Result<()> {
        if let Some(parent) = self.file_path.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("Failed to create directory: {}", parent.display()))?;
        }

        if fs::metadata(&self.file_path).await.is_err() {
            fs::write(&self.file_path, b"{}\n").await.with_context(|| {
                format!(
                    "Failed to initialize bindings file: {}",
                    self.file_path.display()
                )
            })?;
        }
        Ok(())
    }

    async fn read_all(&self) -> Result<HashMap<String, String>> {
        self.ensure_file().await?;
        let raw = fs::read_to_string(&self.file_path).await.with_context(|| {
            format!("Failed to read bindings file: {}", self.file_path.display())
        })?;

        let parsed: Value = serde_json::from_str(&raw).unwrap_or(Value::Object(Default::default()));
        let Some(obj) = parsed.as_object() else {
            return Ok(HashMap::new());
        };

        let mut out = HashMap::new();
        for (key, value) in obj {
            if let Some(v) = value.as_str() {
                out.insert(key.clone(), v.to_string());
            }
        }
        Ok(out)
    }

    async fn write_all(&self, bindings: &HashMap<String, String>) -> Result<()> {
        self.ensure_file().await?;
        let tmp = self.file_path.with_extension(format!(
            "{}.{}.tmp",
            std::process::id(),
            timestamp_millis()
        ));
        let encoded = serde_json::to_string_pretty(bindings)?;
        fs::write(&tmp, format!("{encoded}\n"))
            .await
            .with_context(|| format!("Failed to write temp bindings file: {}", tmp.display()))?;
        fs::rename(&tmp, &self.file_path).await.with_context(|| {
            format!(
                "Failed to replace bindings file: {}",
                self.file_path.display()
            )
        })?;
        Ok(())
    }
}

fn timestamp_millis() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default()
}
