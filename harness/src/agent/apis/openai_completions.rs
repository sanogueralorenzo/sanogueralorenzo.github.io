use anyhow::{Context, Result, bail};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::agent::apis::CacheRetention;
use crate::agent::apis::tool_call_ids::normalize_chat_tool_call_id;
use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

pub struct OpenAiCompletionsModel {
    client: Client,
    base_url: String,
    api_key: String,
    model: String,
    session_id: Option<String>,
    cache_retention: CacheRetention,
}

impl OpenAiCompletionsModel {
    #[cfg(test)]
    pub fn new(base_url: String, api_key: String, model: String) -> Self {
        Self::with_cache(base_url, api_key, model, None, CacheRetention::Short)
    }

    pub fn with_cache(
        base_url: String,
        api_key: String,
        model: String,
        session_id: Option<String>,
        cache_retention: CacheRetention,
    ) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model,
            session_id,
            cache_retention,
        }
    }
}

impl ModelClient for OpenAiCompletionsModel {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));
        let body = ChatRequest {
            model: self.model.clone(),
            messages: to_chat_messages(events),
            tools: chat_tools(events, tools),
            tool_choice: if tools.is_empty() { None } else { Some("auto") },
            prompt_cache_key: self.prompt_cache_key(),
            prompt_cache_retention: self.prompt_cache_retention(),
            store: false,
        };

        let mut request = self.client.post(url).bearer_auth(&self.api_key).json(&body);

        if let Some(session_id) = self.cache_session_id() {
            request = request
                .header("session_id", session_id)
                .header("x-client-request-id", session_id);
        }

        let response = request.send().context("send chat completion request")?;

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

impl OpenAiCompletionsModel {
    fn cache_session_id(&self) -> Option<&str> {
        if self.cache_retention == CacheRetention::None {
            return None;
        }
        self.session_id.as_deref()
    }

    fn prompt_cache_key(&self) -> Option<String> {
        self.cache_session_id().map(clamp_prompt_cache_key)
    }

    fn prompt_cache_retention(&self) -> Option<&'static str> {
        match self.cache_retention {
            CacheRetention::Long => Some("24h"),
            CacheRetention::Short | CacheRetention::None => None,
        }
    }
}

fn clamp_prompt_cache_key(key: &str) -> String {
    key.chars().take(64).collect()
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
                details,
                ..
            } => {
                messages.push(ChatMessage::tool(tool_call_id, output));
                if let Some(image) = image_tool_detail(details.as_ref()) {
                    messages.push(ChatMessage::user_image_tool_result(
                        image.mime_type,
                        image.data,
                    ));
                }
            }
            Event::JobStarted
            | Event::TurnStarted { .. }
            | Event::TurnFinished { .. }
            | Event::JobFinished => {}
        }
    }
    messages
}

fn chat_tools(events: &[Event], tools: &[ToolSpec]) -> Option<Vec<ToolRequest>> {
    if !tools.is_empty() {
        return Some(tools.iter().map(ToolRequest::from).collect());
    }
    if has_tool_history(events) {
        return Some(Vec::new());
    }
    None
}

fn has_tool_history(events: &[Event]) -> bool {
    events
        .iter()
        .any(|event| matches!(event, Event::ToolCall { .. } | Event::ToolResult { .. }))
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tools: Option<Vec<ToolRequest>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_choice: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt_cache_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt_cache_retention: Option<&'static str>,
    store: bool,
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
    content: Option<ChatContent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_calls: Option<Vec<OutboundToolCall>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_call_id: Option<String>,
}

impl ChatMessage {
    fn system(content: &str) -> Self {
        Self {
            role: "system",
            content: Some(ChatContent::text(content)),
            tool_calls: None,
            tool_call_id: None,
        }
    }

    fn user(content: &str) -> Self {
        Self {
            role: "user",
            content: Some(ChatContent::text(content)),
            tool_calls: None,
            tool_call_id: None,
        }
    }

    fn assistant(content: &str) -> Self {
        Self {
            role: "assistant",
            content: Some(ChatContent::text(content)),
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
            content: Some(ChatContent::text(content)),
            tool_calls: None,
            tool_call_id: Some(tool_call_id),
        }
    }

    fn user_image_tool_result(mime_type: &str, data: &str) -> Self {
        Self {
            role: "user",
            content: Some(ChatContent::Parts(vec![
                ChatContentPart::Text {
                    text: "Attached image(s) from tool result:".to_owned(),
                },
                ChatContentPart::ImageUrl {
                    image_url: ImageUrl {
                        url: format!("data:{mime_type};base64,{data}"),
                    },
                },
            ])),
            tool_calls: None,
            tool_call_id: None,
        }
    }
}

#[derive(Serialize)]
#[serde(untagged)]
enum ChatContent {
    Text(String),
    Parts(Vec<ChatContentPart>),
}

impl ChatContent {
    fn text(content: &str) -> Self {
        Self::Text(content.to_owned())
    }
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum ChatContentPart {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "image_url")]
    ImageUrl { image_url: ImageUrl },
}

#[derive(Serialize)]
struct ImageUrl {
    url: String,
}

struct ImageToolDetail<'a> {
    mime_type: &'a str,
    data: &'a str,
}

fn image_tool_detail(details: Option<&Value>) -> Option<ImageToolDetail<'_>> {
    let image = details?.get("image")?;
    let omitted = image
        .get("omitted")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if omitted {
        return None;
    }
    Some(ImageToolDetail {
        mime_type: image.get("mimeType")?.as_str()?,
        data: image.get("data")?.as_str()?,
    })
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
                details: None,
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
                details: None,
            },
        ]);
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["tool_calls"][0]["id"], "call_1");
        assert_eq!(value[2]["tool_call_id"], "call_1");
    }

    #[test]
    fn converts_image_tool_results_to_follow_up_user_image_message() {
        let messages = to_chat_messages(&[Event::ToolResult {
            tool_call_id: "call_image".to_owned(),
            name: "read".to_owned(),
            output: "Read image file [image/png]".to_owned(),
            details: Some(json!({
                "image": {
                    "mimeType": "image/png",
                    "data": "abc123",
                    "omitted": false
                }
            })),
        }]);
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["role"], "tool");
        assert_eq!(value[2]["role"], "user");
        assert_eq!(value[2]["content"][0]["type"], "text");
        assert_eq!(value[2]["content"][1]["type"], "image_url");
        assert_eq!(
            value[2]["content"][1]["image_url"]["url"],
            "data:image/png;base64,abc123"
        );
    }

    #[test]
    fn omits_empty_tools_without_tool_history() {
        let body = ChatRequest {
            model: "test-model".to_owned(),
            messages: to_chat_messages(&[Event::UserMessage {
                content: "hello".to_owned(),
            }]),
            tools: chat_tools(
                &[Event::UserMessage {
                    content: "hello".to_owned(),
                }],
                &[],
            ),
            tool_choice: None,
            prompt_cache_key: None,
            prompt_cache_retention: None,
            store: false,
        };
        let value = serde_json::to_value(body).unwrap();

        assert!(!value.as_object().unwrap().contains_key("tools"));
        assert!(!value.as_object().unwrap().contains_key("tool_choice"));
    }

    #[test]
    fn builds_prompt_cache_fields_from_session_id() {
        let model = OpenAiCompletionsModel::with_cache(
            "http://localhost".to_owned(),
            "key".to_owned(),
            "model".to_owned(),
            Some("x".repeat(80)),
            CacheRetention::Long,
        );

        assert_eq!(model.prompt_cache_key(), Some("x".repeat(64)));
        assert_eq!(model.prompt_cache_retention(), Some("24h"));
        assert_eq!(
            model.cache_session_id(),
            Some(
                "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            )
        );
    }

    #[test]
    fn disables_prompt_cache_fields_when_retention_is_none() {
        let model = OpenAiCompletionsModel::with_cache(
            "http://localhost".to_owned(),
            "key".to_owned(),
            "model".to_owned(),
            Some("session-1".to_owned()),
            CacheRetention::None,
        );

        assert_eq!(model.prompt_cache_key(), None);
        assert_eq!(model.prompt_cache_retention(), None);
        assert_eq!(model.cache_session_id(), None);
    }
}
