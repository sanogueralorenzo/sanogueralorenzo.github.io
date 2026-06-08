use anyhow::{Context, Result, bail};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

pub struct OpenAiResponsesModel {
    client: Client,
    base_url: String,
    api_key: String,
    model: String,
}

impl OpenAiResponsesModel {
    pub fn new(base_url: String, api_key: String, model: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model,
        }
    }
}

impl ModelClient for OpenAiResponsesModel {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        let url = format!("{}/responses", self.base_url.trim_end_matches('/'));
        let body = ResponsesRequest {
            model: self.model.clone(),
            input: to_response_input(events),
            tools: tools.iter().map(ResponsesTool::from).collect(),
            store: false,
        };

        let response = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("send response request")?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().unwrap_or_default();
            bail!("provider returned {status}: {text}");
        }

        let response: ResponsesResponse = response.json().context("decode response")?;
        step_from_response(response)
    }
}

fn step_from_response(response: ResponsesResponse) -> Result<ModelStep> {
    let mut text = String::new();

    for item in response.output {
        match item {
            ResponsesOutputItem::FunctionCall {
                call_id,
                name,
                arguments,
                ..
            } => {
                let arguments = serde_json::from_str(&arguments)
                    .with_context(|| format!("parse arguments for tool {name}"))?;
                return Ok(ModelStep::ToolCall {
                    id: call_id,
                    name,
                    arguments,
                });
            }
            ResponsesOutputItem::Message { content, .. } => {
                for part in content {
                    text.push_str(&part.text());
                }
            }
            ResponsesOutputItem::Reasoning => {}
            ResponsesOutputItem::Unsupported => {
                bail!("unsupported openai-responses output item");
            }
        }
    }

    Ok(ModelStep::Final(text))
}

fn to_response_input(events: &[Event]) -> Vec<ResponseInputItem> {
    let mut input = vec![ResponseInputItem::message(
        "system",
        "You are a minimal coding agent. Use tools when they are useful, then answer concisely.",
    )];

    for event in events {
        match event {
            Event::UserMessage { content } => {
                input.push(ResponseInputItem::message("user", content));
            }
            Event::AssistantMessage { content } => {
                input.push(ResponseInputItem::assistant_message(content));
            }
            Event::ToolCall {
                id,
                name,
                arguments,
            } => input.push(ResponseInputItem::function_call(id, name, arguments)),
            Event::ToolResult {
                tool_call_id,
                output,
                ..
            } => input.push(ResponseInputItem::function_call_output(
                tool_call_id,
                output,
            )),
            Event::JobStarted
            | Event::TurnStarted { .. }
            | Event::TurnFinished { .. }
            | Event::JobFinished => {}
        }
    }

    input
}

#[derive(Serialize)]
struct ResponsesRequest {
    model: String,
    input: Vec<ResponseInputItem>,
    tools: Vec<ResponsesTool>,
    store: bool,
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum ResponseInputItem {
    #[serde(rename = "message")]
    Message {
        role: &'static str,
        content: Vec<InputContent>,
    },
    #[serde(rename = "function_call")]
    FunctionCall {
        call_id: String,
        name: String,
        arguments: String,
    },
    #[serde(rename = "function_call_output")]
    FunctionCallOutput { call_id: String, output: String },
}

impl ResponseInputItem {
    fn message(role: &'static str, content: &str) -> Self {
        Self::Message {
            role,
            content: vec![InputContent::input_text(content)],
        }
    }

    fn assistant_message(content: &str) -> Self {
        Self::Message {
            role: "assistant",
            content: vec![InputContent::output_text(content)],
        }
    }

    fn function_call(call_id: &str, name: &str, arguments: &Value) -> Self {
        Self::FunctionCall {
            call_id: call_id.to_owned(),
            name: name.to_owned(),
            arguments: arguments.to_string(),
        }
    }

    fn function_call_output(call_id: &str, output: &str) -> Self {
        Self::FunctionCallOutput {
            call_id: call_id.to_owned(),
            output: output.to_owned(),
        }
    }
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum InputContent {
    #[serde(rename = "input_text")]
    InputText { text: String },
    #[serde(rename = "output_text")]
    OutputText {
        text: String,
        annotations: Vec<Value>,
    },
}

impl InputContent {
    fn input_text(text: &str) -> Self {
        Self::InputText {
            text: text.to_owned(),
        }
    }

    fn output_text(text: &str) -> Self {
        Self::OutputText {
            text: text.to_owned(),
            annotations: Vec::new(),
        }
    }
}

#[derive(Serialize)]
struct ResponsesTool {
    #[serde(rename = "type")]
    kind: &'static str,
    name: String,
    description: String,
    parameters: Value,
    strict: bool,
}

impl From<&ToolSpec> for ResponsesTool {
    fn from(spec: &ToolSpec) -> Self {
        Self {
            kind: "function",
            name: spec.name.clone(),
            description: spec.description.clone(),
            parameters: spec.parameters.clone(),
            strict: false,
        }
    }
}

#[derive(Deserialize)]
struct ResponsesResponse {
    output: Vec<ResponsesOutputItem>,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum ResponsesOutputItem {
    #[serde(rename = "message")]
    Message { content: Vec<OutputContent> },
    #[serde(rename = "function_call")]
    FunctionCall {
        call_id: String,
        name: String,
        arguments: String,
    },
    #[serde(rename = "reasoning")]
    Reasoning,
    #[serde(other)]
    Unsupported,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum OutputContent {
    #[serde(rename = "output_text")]
    OutputText { text: String },
    #[serde(rename = "refusal")]
    Refusal { refusal: String },
}

impl OutputContent {
    fn text(self) -> String {
        match self {
            Self::OutputText { text } => text,
            Self::Refusal { refusal } => refusal,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn converts_tool_call_continuation_items() {
        let input = to_response_input(&[
            Event::UserMessage {
                content: "where am I?".to_owned(),
            },
            Event::ToolCall {
                id: "call_pwd".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            },
            Event::ToolResult {
                tool_call_id: "call_pwd".to_owned(),
                name: "pwd".to_owned(),
                output: "/tmp/project".to_owned(),
            },
        ]);
        let value = serde_json::to_value(input).unwrap();

        assert_eq!(value[0]["type"], "message");
        assert_eq!(value[0]["role"], "system");
        assert_eq!(value[1]["role"], "user");
        assert_eq!(value[2]["type"], "function_call");
        assert_eq!(value[2]["call_id"], "call_pwd");
        assert_eq!(value[2]["name"], "pwd");
        assert_eq!(value[2]["arguments"], "{}");
        assert_eq!(value[3]["type"], "function_call_output");
        assert_eq!(value[3]["call_id"], "call_pwd");
        assert_eq!(value[3]["output"], "/tmp/project");
    }

    #[test]
    fn parses_response_function_call() {
        let response: ResponsesResponse = serde_json::from_value(json!({
            "output": [{
                "type": "function_call",
                "id": "fc_pwd",
                "call_id": "call_pwd",
                "name": "pwd",
                "arguments": "{}"
            }]
        }))
        .unwrap();

        let step = step_from_response(response).unwrap();

        assert_eq!(
            step,
            ModelStep::ToolCall {
                id: "call_pwd".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            }
        );
    }

    #[test]
    fn parses_response_message_text() {
        let response: ResponsesResponse = serde_json::from_value(json!({
            "output": [{
                "type": "message",
                "role": "assistant",
                "content": [{
                    "type": "output_text",
                    "text": "I checked the current directory.",
                    "annotations": []
                }]
            }]
        }))
        .unwrap();

        let step = step_from_response(response).unwrap();

        assert_eq!(
            step,
            ModelStep::Final("I checked the current directory.".to_owned())
        );
    }
}
