use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum HealthState {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProviderHealth {
    pub provider: String,
    pub status: HealthState,
    #[serde(rename = "cliAvailable")]
    pub cli_available: bool,
    pub authenticated: bool,
    #[serde(rename = "checkMethod")]
    pub check_method: String,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HealthReport {
    pub status: HealthState,
    pub providers: Vec<ProviderHealth>,
}
