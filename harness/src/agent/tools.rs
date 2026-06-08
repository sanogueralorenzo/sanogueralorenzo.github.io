use anyhow::{Result, bail};

pub struct ToolRegistry {
    tools: Vec<Tool>,
}

struct Tool {
    name: &'static str,
    run: fn(&str) -> Result<String>,
}

impl ToolRegistry {
    pub fn minimal() -> Self {
        Self {
            tools: vec![
                Tool {
                    name: "pwd",
                    run: |_input| {
                        let cwd = std::env::current_dir()?;
                        Ok(cwd.display().to_string())
                    },
                },
                Tool {
                    name: "echo",
                    run: |input| Ok(input.to_owned()),
                },
            ],
        }
    }

    pub fn run(&self, name: &str, input: &str) -> Result<String> {
        let Some(tool) = self.tools.iter().find(|tool| tool.name == name) else {
            bail!("unknown tool: {name}");
        };
        (tool.run)(input)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runs_echo_tool() {
        let tools = ToolRegistry::minimal();

        let output = tools.run("echo", "hello").unwrap();

        assert_eq!(output, "hello");
    }

    #[test]
    fn rejects_unknown_tool() {
        let tools = ToolRegistry::minimal();

        let error = tools.run("missing", "").unwrap_err().to_string();

        assert!(error.contains("unknown tool"));
    }
}
