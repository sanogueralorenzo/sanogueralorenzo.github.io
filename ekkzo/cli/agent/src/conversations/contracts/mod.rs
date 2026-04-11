use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionProvider {
    OpenAi,
    Google,
    Anthropic,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionContractRecord {
    pub provider: SessionProvider,
    pub id: String,
    pub name: String,
    pub cwd: String,
    #[serde(rename = "updatedAt")]
    pub updated_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SessionFieldMapping {
    pub provider: SessionProvider,
    pub id: &'static str,
    pub name: &'static str,
    pub cwd: &'static str,
    pub updated_at: &'static str,
}

pub fn session_field_mapping(provider: SessionProvider) -> SessionFieldMapping {
    match provider {
        SessionProvider::OpenAi => SessionFieldMapping {
            provider,
            id: "thread.id",
            name: "name",
            cwd: "cwd",
            updated_at: "updatedAt",
        },
        SessionProvider::Google => SessionFieldMapping {
            provider,
            id: "sessionId",
            name: "title",
            cwd: "cwd",
            updated_at: "updatedAt",
        },
        SessionProvider::Anthropic => SessionFieldMapping {
            provider,
            id: "sessionId",
            name: "summary",
            cwd: "cwd",
            updated_at: "updatedAt",
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{SessionContractRecord, SessionProvider, session_field_mapping};

    #[test]
    fn mapping_matches_openai_contract_fields() {
        let mapping = session_field_mapping(SessionProvider::OpenAi);
        assert_eq!(mapping.id, "thread.id");
        assert_eq!(mapping.name, "name");
        assert_eq!(mapping.cwd, "cwd");
        assert_eq!(mapping.updated_at, "updatedAt");
    }

    #[test]
    fn mapping_matches_google_contract_fields() {
        let mapping = session_field_mapping(SessionProvider::Google);
        assert_eq!(mapping.id, "sessionId");
        assert_eq!(mapping.name, "title");
        assert_eq!(mapping.cwd, "cwd");
        assert_eq!(mapping.updated_at, "updatedAt");
    }

    #[test]
    fn mapping_matches_anthropic_contract_fields() {
        let mapping = session_field_mapping(SessionProvider::Anthropic);
        assert_eq!(mapping.id, "sessionId");
        assert_eq!(mapping.name, "summary");
        assert_eq!(mapping.cwd, "cwd");
        assert_eq!(mapping.updated_at, "updatedAt");
    }

    #[test]
    fn serializes_contract_record_with_updated_at_casing() {
        let record = SessionContractRecord {
            provider: SessionProvider::Anthropic,
            id: "session-1".to_string(),
            name: "Summary".to_string(),
            cwd: "/repo".to_string(),
            updated_at: "2026-04-11T07:00:50.057Z".to_string(),
        };

        let json_value = serde_json::to_value(record).expect("record should serialize");
        assert_eq!(json_value["provider"], "anthropic");
        assert_eq!(json_value["updatedAt"], "2026-04-11T07:00:50.057Z");
        assert!(json_value.get("updated_at").is_none());
    }
}
