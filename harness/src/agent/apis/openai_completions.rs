use anyhow::{Context, Result, bail};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::agent::apis::CacheRetention;
use crate::agent::apis::tool_call_ids::normalize_chat_tool_call_id;
use crate::agent::model::{ModelClient, ModelStep, ToolCallRequest};
use crate::agent::session::{Event, ToolCallEvent};
use crate::agent::tools::ToolSpec;

pub struct OpenAiCompletionsModel {
    client: Client,
    base_url: String,
    api_key: String,
    model: String,
    session_id: Option<String>,
    cache_retention: CacheRetention,
    supports_image_input: bool,
    reasoning: bool,
}

impl OpenAiCompletionsModel {
    #[cfg(test)]
    pub fn new(base_url: String, api_key: String, model: String) -> Self {
        Self::with_cache(
            base_url,
            api_key,
            model,
            None,
            CacheRetention::Short,
            true,
            false,
        )
    }

    pub fn with_cache(
        base_url: String,
        api_key: String,
        model: String,
        session_id: Option<String>,
        cache_retention: CacheRetention,
        supports_image_input: bool,
        reasoning: bool,
    ) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model,
            session_id,
            cache_retention,
            supports_image_input,
            reasoning,
        }
    }
}

impl ModelClient for OpenAiCompletionsModel {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        let url = format!("{}/chat/completions", self.base_url.trim_end_matches('/'));
        let body = ChatRequest {
            model: self.model.clone(),
            messages: to_chat_messages(events, self.supports_image_input, self.reasoning),
            tools: chat_tools(events, tools),
            tool_choice: if tools.is_empty() { None } else { Some("auto") },
            prompt_cache_key: self.prompt_cache_key(),
            prompt_cache_retention: self.prompt_cache_retention(),
            store: false,
        };

        let request = self.client.post(url).bearer_auth(&self.api_key).json(&body);

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
        if !self.should_send_prompt_cache_key() {
            return None;
        }
        self.cache_session_id().map(clamp_prompt_cache_key)
    }

    fn prompt_cache_retention(&self) -> Option<&'static str> {
        match self.cache_retention {
            CacheRetention::Long => Some("24h"),
            CacheRetention::Short | CacheRetention::None => None,
        }
    }

    fn should_send_prompt_cache_key(&self) -> bool {
        match self.cache_retention {
            CacheRetention::None => false,
            CacheRetention::Short => self.base_url.contains("api.openai.com"),
            CacheRetention::Long => true,
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

    if !message.tool_calls.is_empty() {
        let mut calls = Vec::new();
        for tool_call in message.tool_calls {
            let arguments = serde_json::from_str(&tool_call.function.arguments)
                .with_context(|| format!("parse arguments for tool {}", tool_call.function.name))?;
            calls.push(ToolCallRequest {
                id: tool_call.id,
                name: tool_call.function.name,
                arguments,
            });
        }
        return Ok(single_or_batch_tool_step(calls));
    }

    Ok(ModelStep::Final(message.content.unwrap_or_default()))
}

fn to_chat_messages(
    events: &[Event],
    supports_image_input: bool,
    reasoning: bool,
) -> Vec<ChatMessage> {
    let instruction_role = if reasoning { "developer" } else { "system" };
    let mut messages = vec![ChatMessage::instruction(
        instruction_role,
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
            Event::ToolCalls { calls } => messages.push(ChatMessage::assistant_tool_calls(calls)),
            Event::ToolResult {
                tool_call_id,
                output,
                details,
                ..
            } => {
                let tool_output =
                    if !supports_image_input && image_tool_detail(details.as_ref()).is_some() {
                        non_vision_tool_output(output)
                    } else {
                        output.to_owned()
                    };
                messages.push(ChatMessage::tool(tool_call_id, &tool_output));
                if supports_image_input && let Some(image) = image_tool_detail(details.as_ref()) {
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
    events.iter().any(|event| {
        matches!(
            event,
            Event::ToolCall { .. } | Event::ToolCalls { .. } | Event::ToolResult { .. }
        )
    })
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
    fn instruction(role: &'static str, content: &str) -> Self {
        Self {
            role,
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
        Self::assistant_tool_calls(&[ToolCallEvent {
            id: id.to_owned(),
            name: name.to_owned(),
            arguments: arguments.clone(),
        }])
    }

    fn assistant_tool_calls(calls: &[ToolCallEvent]) -> Self {
        Self {
            role: "assistant",
            content: None,
            tool_calls: Some(
                calls
                    .iter()
                    .map(|call| OutboundToolCall {
                        id: normalize_chat_tool_call_id(&call.id),
                        kind: "function",
                        function: OutboundToolFunction {
                            name: call.name.clone(),
                            arguments: call.arguments.to_string(),
                        },
                    })
                    .collect(),
            ),
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

fn single_or_batch_tool_step(calls: Vec<ToolCallRequest>) -> ModelStep {
    match calls.as_slice() {
        [call] => ModelStep::ToolCall {
            id: call.id.clone(),
            name: call.name.clone(),
            arguments: call.arguments.clone(),
        },
        _ => ModelStep::ToolCalls(calls),
    }
}

fn non_vision_tool_output(output: &str) -> String {
    if output.is_empty() {
        "(tool image omitted: model does not support images)".to_owned()
    } else {
        format!("{output}\n(tool image omitted: model does not support images)")
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
    use std::collections::HashMap;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::mpsc;
    use std::thread;

    use serde_json::json;

    #[test]
    fn converts_tool_call_continuation_messages() {
        let messages = to_chat_messages(
            &[
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
            ],
            true,
            false,
        );
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
    fn converts_multiple_tool_call_continuation_messages() {
        let messages = to_chat_messages(
            &[Event::ToolCalls {
                calls: vec![
                    ToolCallEvent {
                        id: "call_1".to_owned(),
                        name: "pwd".to_owned(),
                        arguments: json!({}),
                    },
                    ToolCallEvent {
                        id: "call_2".to_owned(),
                        name: "ls".to_owned(),
                        arguments: json!({ "path": "." }),
                    },
                ],
            }],
            true,
            false,
        );
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["role"], "assistant");
        assert_eq!(value[1]["tool_calls"].as_array().unwrap().len(), 2);
        assert_eq!(value[1]["tool_calls"][0]["function"]["name"], "pwd");
        assert_eq!(value[1]["tool_calls"][1]["function"]["name"], "ls");
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
    fn parses_chat_completion_multiple_tool_calls() {
        let response: ChatResponse = serde_json::from_value(json!({
            "choices": [{
                "message": {
                    "content": null,
                    "tool_calls": [
                        {
                            "id": "call_1",
                            "type": "function",
                            "function": {
                                "name": "pwd",
                                "arguments": "{}"
                            }
                        },
                        {
                            "id": "call_2",
                            "type": "function",
                            "function": {
                                "name": "ls",
                                "arguments": "{\"path\":\".\"}"
                            }
                        }
                    ]
                }
            }]
        }))
        .unwrap();

        let step = step_from_chat_response(response).unwrap();

        assert_eq!(
            step,
            ModelStep::ToolCalls(vec![
                ToolCallRequest {
                    id: "call_1".to_owned(),
                    name: "pwd".to_owned(),
                    arguments: json!({}),
                },
                ToolCallRequest {
                    id: "call_2".to_owned(),
                    name: "ls".to_owned(),
                    arguments: json!({ "path": "." }),
                },
            ])
        );
    }

    #[test]
    fn normalizes_responses_tool_ids_for_chat_continuation() {
        let messages = to_chat_messages(
            &[
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
            ],
            true,
            false,
        );
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["tool_calls"][0]["id"], "call_1");
        assert_eq!(value[2]["tool_call_id"], "call_1");
    }

    #[test]
    fn converts_image_tool_results_to_follow_up_user_image_message() {
        let messages = to_chat_messages(
            &[Event::ToolResult {
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
            }],
            true,
            false,
        );
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
    fn downgrades_image_tool_results_when_model_is_text_only() {
        let messages = to_chat_messages(
            &[Event::ToolResult {
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
            }],
            false,
            false,
        );
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[1]["role"], "tool");
        assert_eq!(
            value[1]["content"],
            "Read image file [image/png]\n(tool image omitted: model does not support images)"
        );
        assert!(value.get(2).is_none());
    }

    #[test]
    fn uses_developer_instruction_role_for_reasoning_models() {
        let messages = to_chat_messages(&[], true, true);
        let value = serde_json::to_value(messages).unwrap();

        assert_eq!(value[0]["role"], "developer");
    }

    #[test]
    fn omits_empty_tools_without_tool_history() {
        let body = ChatRequest {
            model: "test-model".to_owned(),
            messages: to_chat_messages(
                &[Event::UserMessage {
                    content: "hello".to_owned(),
                }],
                true,
                false,
            ),
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
            true,
            false,
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
    fn sends_short_prompt_cache_key_only_to_openai_base_url_like_pi() {
        let openai_model = OpenAiCompletionsModel::with_cache(
            "https://api.openai.com/v1".to_owned(),
            "key".to_owned(),
            "model".to_owned(),
            Some("session-1".to_owned()),
            CacheRetention::Short,
            true,
            false,
        );
        let custom_model = OpenAiCompletionsModel::with_cache(
            "http://localhost".to_owned(),
            "key".to_owned(),
            "model".to_owned(),
            Some("session-1".to_owned()),
            CacheRetention::Short,
            true,
            false,
        );

        assert_eq!(
            openai_model.prompt_cache_key(),
            Some("session-1".to_owned())
        );
        assert_eq!(custom_model.prompt_cache_key(), None);
    }

    #[test]
    fn sends_prompt_cache_body_but_no_affinity_headers_for_completions() {
        let server = TestServer::start(json!({
            "choices": [{
                "message": {
                    "content": "ok",
                    "tool_calls": []
                }
            }]
        }));
        let mut model = OpenAiCompletionsModel::with_cache(
            server.base_url(),
            "test-key".to_owned(),
            "test-model".to_owned(),
            Some("session-123".to_owned()),
            CacheRetention::Long,
            true,
            false,
        );

        let step = model
            .next_step(
                &[Event::UserMessage {
                    content: "hello".to_owned(),
                }],
                &[],
            )
            .unwrap();
        let request = server.request();

        assert_eq!(step, ModelStep::Final("ok".to_owned()));
        assert_eq!(request.body["prompt_cache_key"], "session-123");
        assert_eq!(request.body["prompt_cache_retention"], "24h");
        assert!(!request.headers.contains_key("session_id"));
        assert!(!request.headers.contains_key("x-client-request-id"));
        assert!(!request.headers.contains_key("x-session-affinity"));
    }

    #[test]
    fn disables_prompt_cache_fields_when_retention_is_none() {
        let model = OpenAiCompletionsModel::with_cache(
            "http://localhost".to_owned(),
            "key".to_owned(),
            "model".to_owned(),
            Some("session-1".to_owned()),
            CacheRetention::None,
            true,
            false,
        );

        assert_eq!(model.prompt_cache_key(), None);
        assert_eq!(model.prompt_cache_retention(), None);
        assert_eq!(model.cache_session_id(), None);
    }

    struct RecordedRequest {
        headers: HashMap<String, String>,
        body: Value,
    }

    struct TestServer {
        base_url: String,
        request: mpsc::Receiver<RecordedRequest>,
        handle: thread::JoinHandle<()>,
    }

    impl TestServer {
        fn start(response: Value) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let base_url = format!("http://{}", listener.local_addr().unwrap());
            let (tx, rx) = mpsc::channel();
            let handle = thread::spawn(move || {
                let (mut stream, _) = listener.accept().unwrap();
                let request = read_http_request(&mut stream);
                tx.send(request).unwrap();
                write_http_json(&mut stream, &response);
            });

            Self {
                base_url,
                request: rx,
                handle,
            }
        }

        fn base_url(&self) -> String {
            self.base_url.clone()
        }

        fn request(self) -> RecordedRequest {
            let _ = self.handle.join();
            self.request.recv().unwrap()
        }
    }

    fn read_http_request(stream: &mut TcpStream) -> RecordedRequest {
        let mut buffer = Vec::new();
        let mut chunk = [0; 4096];
        loop {
            let count = stream.read(&mut chunk).unwrap();
            assert!(count > 0);
            buffer.extend_from_slice(&chunk[..count]);
            if let Some(length) = content_length(&buffer) {
                let header_end = find_header_end(&buffer).unwrap();
                let body_len = buffer.len() - header_end;
                if body_len >= length {
                    let headers = parse_headers(&buffer[..header_end]);
                    let body = String::from_utf8(buffer[header_end..header_end + length].to_vec())
                        .unwrap();
                    return RecordedRequest {
                        headers,
                        body: serde_json::from_str(&body).unwrap(),
                    };
                }
            }
        }
    }

    fn content_length(buffer: &[u8]) -> Option<usize> {
        let headers = String::from_utf8_lossy(buffer);
        let header_text = headers.split("\r\n\r\n").next()?;
        for line in header_text.lines() {
            let Some((name, value)) = line.split_once(':') else {
                continue;
            };
            if name.eq_ignore_ascii_case("content-length") {
                return value.trim().parse().ok();
            }
        }
        None
    }

    fn parse_headers(bytes: &[u8]) -> HashMap<String, String> {
        let text = String::from_utf8_lossy(bytes);
        let mut headers = HashMap::new();
        for line in text.lines().skip(1) {
            let Some((name, value)) = line.split_once(':') else {
                continue;
            };
            headers.insert(name.to_ascii_lowercase(), value.trim().to_owned());
        }
        headers
    }

    fn find_header_end(buffer: &[u8]) -> Option<usize> {
        buffer
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
            .map(|index| index + 4)
    }

    fn write_http_json(stream: &mut TcpStream, value: &Value) {
        let body = value.to_string();
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .unwrap();
        stream.flush().unwrap();
    }
}
