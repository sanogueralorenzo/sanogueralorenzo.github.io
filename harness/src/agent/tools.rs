use anyhow::{Result, bail};
use serde_json::{Value, json};

#[derive(Debug, Clone)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

pub struct ToolRegistry {
    tools: Vec<Tool>,
}

struct Tool {
    spec: ToolSpec,
    run: fn(&Value) -> Result<String>,
}

impl ToolRegistry {
    pub fn minimal() -> Self {
        Self {
            tools: vec![
                Tool {
                    spec: ToolSpec {
                        name: "pwd".to_owned(),
                        description: "Return the current working directory.".to_owned(),
                        parameters: json!({
                            "type": "object",
                            "properties": {},
                            "additionalProperties": false
                        }),
                    },
                    run: |_arguments| {
                        let cwd = std::env::current_dir()?;
                        Ok(cwd.display().to_string())
                    },
                },
                Tool {
                    spec: ToolSpec {
                        name: "echo".to_owned(),
                        description: "Return the provided text.".to_owned(),
                        parameters: json!({
                            "type": "object",
                            "properties": {
                                "text": { "type": "string" }
                            },
                            "required": ["text"],
                            "additionalProperties": false
                        }),
                    },
                    run: |arguments| {
                        let Some(text) = arguments.get("text").and_then(Value::as_str) else {
                            bail!("echo requires string argument: text");
                        };
                        Ok(text.to_owned())
                    },
                },
            ],
        }
    }

    pub fn specs(&self) -> Vec<ToolSpec> {
        self.tools.iter().map(|tool| tool.spec.clone()).collect()
    }

    pub fn run(&self, name: &str, arguments: &Value) -> Result<String> {
        let Some(tool) = self.tools.iter().find(|tool| tool.spec.name == name) else {
            bail!("unknown tool: {name}");
        };
        (tool.run)(arguments)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_echo_tool() {
        let tools = ToolRegistry::minimal();

        let output = tools.run("echo", &json!({ "text": "hello" })).unwrap();

        assert_eq!(output, "hello");
    }

    #[test]
    fn rejects_unknown_tool() {
        let tools = ToolRegistry::minimal();

        let error = tools.run("missing", &json!({})).unwrap_err().to_string();

        assert!(error.contains("unknown tool"));
    }
}
