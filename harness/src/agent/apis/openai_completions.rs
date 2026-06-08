use anyhow::{Context, Result, bail};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::agent::apis::tool_call_ids::normalize_chat_tool_call_id;
use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

pub struct OpenAiCompletionsModel {
    client: Client,
    base_url: String,
    api_key: String,
    model: String,
}

impl OpenAiCompletionsModel {
    pub fn new(base_url: String, api_key: String, model: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model,
        }
    }
}

impl ModelClient for OpenAiCompletionsModel {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));
        let body = ChatRequest {
            model: self.model.clone(),
            messages: to_chat_messages(events),
            tools: tools.iter().map(ToolRequest::from).collect(),
            tool_choice: "auto",
        };

        let response = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("send chat completion request")?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().unwrap_or_default();
            bail!("provider returned {status}: {text}");
        }

        let completion: ChatResponse =
            response.json().context("decode chat completion response")?;
        step_from_chat_response(completion)
    }
}

fn step_from_chat_response(completion: ChatResponse) -> Result<ModelStep> {
    let message = completion
        .choices
        .into_iter()
        .next()
        .context("provider response had no choices")?
        .message;

    if let Some(tool_call) = message.tool_calls.into_iter().next() {
        let arguments = serde_json::from_str(&tool_call.function.arguments)
            .with_context(|| format!("parse arguments for tool {}", tool_call.function.name))?;
        return Ok(ModelStep::ToolCall {
            id: tool_call.id,
            name: tool_call.function.name,
            arguments,
        });
    }

    Ok(ModelStep::Final(message.content.unwrap_or_default()))
}

fn to_chat_messages(events: &[Event]) -> Vec<ChatMessage> {
    let mut messages = vec![ChatMessage::system(
        "You are a minimal coding agent. Use tools when they are useful, then answer concisely.",
    )];
    for event in events {
        match event {
            Event::UserMessage { content } => messages.push(ChatMessage::user(content)),
            Event::AssistantMessage { content } => messages.push(ChatMessage::assistant(content)),
            Event::ToolCall {
                id,
                name,
                arguments,
            } => messages.push(ChatMessage::assistant_tool_call(id, name, arguments)),
            Event::ToolResult {
                tool_call_id,
                output,
                ..
            } => messages.push(ChatMessage::tool(tool_call_id, output)),
            Event::JobStarted
            | Event::TurnStarted { .. }
            | Event::TurnFinished { .. }
            | Event::JobFinished => {}
        }
    }
    messages
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
    tools: Vec<ToolRequest>,
    tool_choice: &'static str,
}

#[derive(Serialize)]
struct ToolRequest {
    #[serde(rename = "type")]
    kind: &'static str,
    function: ToolFunctionRequest,
}

impl From<&ToolSpec> for ToolRequest {
    fn from(spec: &ToolSpec) -> Self {
        Self {
            kind: "function",
            function: ToolFunctionRequest {
                name: spec.name.clone(),
                description: spec.description.clone(),
                parameters: spec.parameters.clone(),
            },
        }
    }
}

#[derive(Serialize)]
struct ToolFunctionRequest {
    name: String,
    description: String,
    parameters: Value,
}

#[derive(Serialize)]
struct ChatMessage {
    role: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_calls: Option<Vec<OutboundToolCall>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_call_id: Option<String>,
}

impl ChatMessage {
    fn system(content: &str) -> Self {
        Self {
            role: "system",
            content: Some(content.to_owned()),
            tool_calls: None,
            tool_call_id: None,
        }
    }

    fn user(content: &str) -> Self {
        Self {
            role: "user",
            content: Some(content.to_owned()),
            tool_calls: None,
            tool_call_id: None,
        }
    }

    fn assistant(content: &str) -> Self {
        Self {
            role: "assistant",
            content: Some(content.to_owned()),
            tool_calls: None,
            tool_call_id: None,
        }
    }

    fn assistant_tool_call(id: &str, name: &str, arguments: &Value) -> Self {
        let id = normalize_chat_tool_call_id(id);
        Self {
            role: "assistant",
            content: None,
            tool_calls: Some(vec![OutboundToolCall {
                id,
                kind: "function",
                function: OutboundToolFunction {
                    name: name.to_owned(),
                    arguments: arguments.to_string(),
                },
            }]),
            tool_call_id: None,
        }
    }

    fn tool(tool_call_id: &str, content: &str) -> Self {
        let tool_call_id = normalize_chat_tool_call_id(tool_call_id);
        Self {
            role: "tool",
            content: Some(content.to_owned()),
            tool_calls: None,
            tool_call_id: Some(tool_call_id),
        }
    }
}

#[derive(Serialize)]
struct OutboundToolCall {
    id: String,
    #[serde(rename = "type")]
    kind: &'static str,
    function: OutboundToolFunction,
}

#[derive(Serialize)]
struct OutboundToolFunction {
    name: String,
    arguments: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
}

#[derive(Deserialize)]
struct Choice {
    message: AssistantResponseMessage,
}

#[derive(Deserialize)]
struct AssistantResponseMessage {
    content: Option<String>,
    #[serde(default)]
    tool_calls: Vec<InboundToolCall>,
}

#[derive(Deserialize)]
struct InboundToolCall {
    id: String,
    function: InboundToolFunction,
}

#[derive(Deserialize)]
struct InboundToolFunction {
    name: String,
    arguments: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn converts_tool_call_continuation_messages() {
        let messages = to_chat_messages(&[
            Event::UserMessage {
                content: "where am I?".to_owned(),
            },
            Event::ToolCall {
                id: "call_1".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            },
            Event::ToolResult {
                tool_call_id: "call_1".to_owned(),
                name: "pwd".to_owned(),
                output: "/tmp/project".to_owned(),
            },
        ]);
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[0]["role"], "system");
        assert_eq!(value[1]["role"], "user");
        assert_eq!(value[2]["role"], "assistant");
        assert_eq!(value[2]["tool_calls"][0]["id"], "call_1");
        assert_eq!(value[2]["tool_calls"][0]["function"]["name"], "pwd");
        assert_eq!(value[3]["role"], "tool");
        assert_eq!(value[3]["tool_call_id"], "call_1");
    }

    #[test]
    fn parses_chat_completion_tool_call() {
        let response: ChatResponse = serde_json::from_value(json!({
            "choices": [{
                "message": {
                    "content": null,
                    "tool_calls": [{
                        "id": "call_1",
                        "type": "function",
                        "function": {
                            "name": "echo",
                            "arguments": "{\"text\":\"hello\"}"
                        }
                    }]
                }
            }]
        }))
        .unwrap();

        let step = step_from_chat_response(response).unwrap();

        assert_eq!(
            step,
            ModelStep::ToolCall {
                id: "call_1".to_owned(),
                name: "echo".to_owned(),
                arguments: json!({ "text": "hello" }),
            }
        );
    }

    #[test]
    fn normalizes_responses_tool_ids_for_chat_continuation() {
        let messages = to_chat_messages(&[
            Event::ToolCall {
                id: "call_1|fc_item".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            },
            Event::ToolResult {
                tool_call_id: "call_1|fc_item".to_owned(),
                name: "pwd".to_owned(),
                output: "/tmp/project".to_owned(),
            },
        ]);
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["tool_calls"][0]["id"], "call_1");
        assert_eq!(value[2]["tool_call_id"], "call_1");
    }
}
