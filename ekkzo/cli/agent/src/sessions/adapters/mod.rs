mod anthropic;
mod google;
mod openai;

use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde::Serialize;
use serde_json::Value;
use std::path::PathBuf;

use anthropic::AnthropicSessionsAdapter;
use google::GoogleSessionsAdapter;
use openai::OpenAiSessionsAdapter;

pub trait SessionsAdapter {
    fn map_session(&self, value: &Value) -> Result<SessionContractRecord, String>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProviderDeleteResult {
    pub provider: SessionProvider,
    pub deleted: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DeleteSummary {
    #[serde(rename = "totalDeleted")]
    pub total_deleted: usize,
    #[serde(rename = "byProvider")]
    pub by_provider: Vec<ProviderDeleteResult>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ResumeSessionResult {
    pub provider: SessionProvider,
    pub id: String,
    pub name: String,
    pub cwd: String,
    #[serde(rename = "updatedAt")]
    pub updated_at: String,
    pub command: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ProviderSessionRoots {
    pub openai_root: Option<PathBuf>,
    pub anthropic_projects_root: Option<PathBuf>,
    pub google_tmp_root: Option<PathBuf>,
}

pub fn map_session_with_provider(
    provider_name: &str,
    value: &Value,
) -> Result<SessionContractRecord, String> {
    match provider_name {
        "openai" => OpenAiSessionsAdapter.map_session(value),
        "google" => GoogleSessionsAdapter.map_session(value),
        "anthropic" => AnthropicSessionsAdapter.map_session(value),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}

pub fn map_sessions_with_provider(
    provider_name: &str,
    values: &[Value],
) -> Result<Vec<SessionContractRecord>, String> {
    values
        .iter()
        .map(|value| map_session_with_provider(provider_name, value))
        .collect()
}

pub fn list_sessions_all_providers() -> Result<Vec<SessionContractRecord>, String> {
    list_sessions_all_providers_with_roots(&ProviderSessionRoots::default())
}

pub(crate) fn list_sessions_all_providers_with_roots(
    roots: &ProviderSessionRoots,
) -> Result<Vec<SessionContractRecord>, String> {
    let mut sessions = Vec::new();
    sessions.extend(openai::list_local_sessions_at_root(
        roots.openai_root.as_deref(),
    )?);
    sessions.extend(anthropic::list_local_sessions_at_root(
        roots.anthropic_projects_root.as_deref(),
    )?);
    sessions.extend(google::list_local_sessions_at_root(
        roots.google_tmp_root.as_deref(),
    )?);
    sessions.sort_by(|left, right| {
        right
            .updated_at
            .cmp(&left.updated_at)
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(sessions)
}

pub fn delete_session_all_providers(id: &str) -> Result<DeleteSummary, String> {
    delete_session_all_providers_with_roots(id, &ProviderSessionRoots::default())
}

pub(crate) fn delete_session_all_providers_with_roots(
    id: &str,
    roots: &ProviderSessionRoots,
) -> Result<DeleteSummary, String> {
    let openai_deleted = openai::delete_local_session_at_root(id, roots.openai_root.as_deref())?;
    let anthropic_deleted =
        anthropic::delete_local_session_at_root(id, roots.anthropic_projects_root.as_deref())?;
    let google_deleted = google::delete_local_session_at_root(id, roots.google_tmp_root.as_deref())?;
    build_delete_summary(openai_deleted, anthropic_deleted, google_deleted)
}

pub fn delete_all_sessions_all_providers() -> Result<DeleteSummary, String> {
    delete_all_sessions_all_providers_with_roots(&ProviderSessionRoots::default())
}

pub(crate) fn delete_all_sessions_all_providers_with_roots(
    roots: &ProviderSessionRoots,
) -> Result<DeleteSummary, String> {
    let openai_deleted = openai::delete_all_local_sessions_at_root(roots.openai_root.as_deref())?;
    let anthropic_deleted =
        anthropic::delete_all_local_sessions_at_root(roots.anthropic_projects_root.as_deref())?;
    let google_deleted = google::delete_all_local_sessions_at_root(roots.google_tmp_root.as_deref())?;
    build_delete_summary(openai_deleted, anthropic_deleted, google_deleted)
}

pub fn resolve_resume_session(id: &str) -> Result<ResumeSessionResult, String> {
    resolve_resume_session_with_roots(id, &ProviderSessionRoots::default())
}

pub(crate) fn resolve_resume_session_with_roots(
    id: &str,
    roots: &ProviderSessionRoots,
) -> Result<ResumeSessionResult, String> {
    let matches = list_sessions_all_providers_with_roots(roots)?
        .into_iter()
        .filter(|session| session.id == id)
        .collect::<Vec<_>>();

    if matches.is_empty() {
        return Err(format!("session '{id}' was not found in any provider"));
    }

    if matches.len() > 1 {
        let providers = matches
            .iter()
            .map(|session| format!("{:?}", session.provider).to_lowercase())
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!(
            "session '{id}' exists in multiple providers ({providers}), delete duplicates first"
        ));
    }

    let session = matches.into_iter().next().expect("single match should exist");
    let command = match session.provider {
        SessionProvider::OpenAi => openai::resume_command(&session.id),
        SessionProvider::Anthropic => anthropic::resume_command(&session.id),
        SessionProvider::Google => google::resume_command(&session.id),
    };

    Ok(ResumeSessionResult {
        provider: session.provider,
        id: session.id,
        name: session.name,
        cwd: session.cwd,
        updated_at: session.updated_at,
        command,
    })
}

fn build_delete_summary(
    openai_deleted: usize,
    anthropic_deleted: usize,
    google_deleted: usize,
) -> Result<DeleteSummary, String> {
    let by_provider = vec![
        ProviderDeleteResult {
            provider: SessionProvider::OpenAi,
            deleted: openai_deleted,
        },
        ProviderDeleteResult {
            provider: SessionProvider::Anthropic,
            deleted: anthropic_deleted,
        },
        ProviderDeleteResult {
            provider: SessionProvider::Google,
            deleted: google_deleted,
        },
    ];
    let total_deleted = by_provider.iter().map(|entry| entry.deleted).sum();
    Ok(DeleteSummary {
        total_deleted,
        by_provider,
    })
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .ok_or_else(|| format!("missing required field '{key}'"))
}

fn required_string_or_number(value: &Value, key: &str) -> Result<String, String> {
    let field = value
        .get(key)
        .ok_or_else(|| format!("missing required field '{key}'"))?;

    if let Some(string_value) = field.as_str() {
        return Ok(string_value.to_string());
    }

    if let Some(number_value) = field.as_i64() {
        return Ok(number_value.to_string());
    }

    if let Some(number_value) = field.as_u64() {
        return Ok(number_value.to_string());
    }

    if let Some(number_value) = field.as_f64() {
        return Ok(number_value.to_string());
    }

    Err(format!("invalid field type for '{key}', expected string or number"))
}

fn required_string_at_path(value: &Value, path: &[&str]) -> Result<String, String> {
    let mut current = value;
    for key in path {
        current = current
            .get(key)
            .ok_or_else(|| format!("missing required field '{}'", path.join(".")))?;
    }

    current
        .as_str()
        .map(ToString::to_string)
        .ok_or_else(|| format!("invalid field type for '{}', expected string", path.join(".")))
}

#[cfg(test)]
mod tests {
    use super::{
        ProviderSessionRoots, build_delete_summary, map_session_with_provider,
        map_sessions_with_provider, resolve_resume_session_with_roots,
    };
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;
    use std::path::PathBuf;

    #[test]
    fn rejects_unknown_provider() {
        let err = map_session_with_provider("unknown", &json!({ "id": "x" }))
            .expect_err("unknown provider should fail");
        assert!(err.contains("unknown provider"));
    }

    #[test]
    fn maps_multiple_sessions_for_provider() {
        let values = vec![
            json!({"sessionId":"s-1","title":"One","cwd":"/repo","updatedAt":"2026-04-11T00:00:00Z"}),
            json!({"sessionId":"s-2","title":"Two","cwd":"/repo","updatedAt":"2026-04-11T00:10:00Z"}),
        ];

        let mapped = map_sessions_with_provider("google", &values).expect("mapping should work");
        assert_eq!(mapped.len(), 2);
        assert_eq!(mapped[0].id, "s-1");
        assert_eq!(mapped[1].id, "s-2");
    }

    #[test]
    fn delete_summary_contains_all_providers() {
        let summary = build_delete_summary(2, 1, 3).expect("summary should build");
        assert_eq!(summary.total_deleted, 6);
        assert_eq!(summary.by_provider.len(), 3);
        assert_eq!(summary.by_provider[0].provider, SessionProvider::OpenAi);
        assert_eq!(summary.by_provider[1].provider, SessionProvider::Anthropic);
        assert_eq!(summary.by_provider[2].provider, SessionProvider::Google);
    }

    #[test]
    fn resume_with_roots_reports_missing_session() {
        let roots = ProviderSessionRoots {
            openai_root: Some(PathBuf::from("/tmp/does-not-exist-openai")),
            anthropic_projects_root: Some(PathBuf::from("/tmp/does-not-exist-anthropic")),
            google_tmp_root: Some(PathBuf::from("/tmp/does-not-exist-google")),
        };

        let err = resolve_resume_session_with_roots("missing", &roots)
            .expect_err("missing session should return an error");
        assert!(err.contains("was not found"));
    }
}
