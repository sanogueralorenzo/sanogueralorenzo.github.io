use crate::providers::Provider;

pub struct AgentEngine {
    provider: Box<dyn Provider>,
}

impl AgentEngine {
    pub fn new(provider: Box<dyn Provider>) -> Self {
        Self { provider }
    }

    pub fn describe(&self) -> String {
        format!(
            "agent engine ready with provider '{}'",
            self.provider.name()
        )
    }
}
