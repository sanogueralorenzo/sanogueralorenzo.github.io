use anyhow::{Context, Result, bail};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::agent::apis::tool_call_ids::{
    combine_responses_tool_call_id, normalize_responses_tool_call_id,
};
use crate::agent::model::{ModelClient, ModelStep};
use crate::agent::session::Event;
use crate::agent::tools::ToolSpec;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CacheRetention {
    Short,
    Long,
    None,
}

impl CacheRetention {
    pub fn from_env() -> Result<Self> {
        if let Ok(value) = std::env::var("HARNESS_CACHE_RETENTION") {
            return Self::parse(&value);
        }
        if std::env::var("PI_CACHE_RETENTION").ok().as_deref() == Some("long") {
            return Ok(Self::Long);
        }
        Ok(Self::Short)
    }

    fn parse(value: &str) -> Result<Self> {
        match value {
            "short" => Ok(Self::Short),
            "long" => Ok(Self::Long),
            "none" => Ok(Self::None),
            other => bail!("HARNESS_CACHE_RETENTION must be short, long, or none; got {other}"),
        }
    }
}

pub struct OpenAiResponsesModel {
    client: Client,
    base_url: String,
    api_key: String,
    model: String,
    session_id: Option<String>,
    cache_retention: CacheRetention,
}

impl OpenAiResponsesModel {
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

impl ModelClient for OpenAiResponsesModel {
    fn next_step(&mut self, events: &[Event], tools: &[ToolSpec]) -> Result<ModelStep> {
        let url = format!("{}/responses", self.base_url.trim_end_matches('/'));
        let body = ResponsesRequest {
            model: self.model.clone(),
            input: to_response_input(events),
            tools: non_empty_tools(tools),
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

        let response = request.send().context("send response request")?;

        let status = response.status();
        if !status.is_success() {
            let text = response.text().unwrap_or_default();
            bail!("provider returned {status}: {text}");
        }

        let response: ResponsesResponse = response.json().context("decode response")?;
        step_from_response(response)
    }
}

impl OpenAiResponsesModel {
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

fn step_from_response(response: ResponsesResponse) -> Result<ModelStep> {
    let mut text = String::new();

    for item in response.output {
        match item {
            ResponsesOutputItem::FunctionCall {
                call_id,
                id,
                name,
                arguments,
                ..
            } => {
                let arguments = serde_json::from_str(&arguments)
                    .with_context(|| format!("parse arguments for tool {name}"))?;
                return Ok(ModelStep::ToolCall {
                    id: combine_responses_tool_call_id(call_id, id),
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
                details,
                ..
            } => input.push(ResponseInputItem::function_call_output(
                tool_call_id,
                output,
                details.as_ref(),
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
    #[serde(skip_serializing_if = "Option::is_none")]
    tools: Option<Vec<ResponsesTool>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt_cache_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    prompt_cache_retention: Option<&'static str>,
    store: bool,
}

fn non_empty_tools(tools: &[ToolSpec]) -> Option<Vec<ResponsesTool>> {
    if tools.is_empty() {
        None
    } else {
        Some(tools.iter().map(ResponsesTool::from).collect())
    }
}

fn clamp_prompt_cache_key(key: &str) -> String {
    key.chars().take(64).collect()
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
        #[serde(skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        call_id: String,
        name: String,
        arguments: String,
    },
    #[serde(rename = "function_call_output")]
    FunctionCallOutput {
        call_id: String,
        output: FunctionCallOutputContent,
    },
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
        let id = normalize_responses_tool_call_id(call_id);
        Self::FunctionCall {
            call_id: id.call_id,
            id: id.item_id,
            name: name.to_owned(),
            arguments: arguments.to_string(),
        }
    }

    fn function_call_output(call_id: &str, output: &str, details: Option<&Value>) -> Self {
        let id = normalize_responses_tool_call_id(call_id);
        Self::FunctionCallOutput {
            call_id: id.call_id,
            output: function_call_output_content(output, details),
        }
    }
}

#[derive(Serialize)]
#[serde(untagged)]
enum FunctionCallOutputContent {
    Text(String),
    Parts(Vec<InputContent>),
}

#[derive(Serialize)]
#[serde(tag = "type")]
enum InputContent {
    #[serde(rename = "input_text")]
    InputText { text: String },
    #[serde(rename = "input_image")]
    InputImage {
        detail: &'static str,
        image_url: String,
    },
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

    fn input_image(mime_type: &str, data: &str) -> Self {
        Self::InputImage {
            detail: "auto",
            image_url: format!("data:{mime_type};base64,{data}"),
        }
    }

    fn output_text(text: &str) -> Self {
        Self::OutputText {
            text: text.to_owned(),
            annotations: Vec::new(),
        }
    }
}

fn function_call_output_content(
    output: &str,
    details: Option<&Value>,
) -> FunctionCallOutputContent {
    let Some(image) = image_tool_detail(details) else {
        return FunctionCallOutputContent::Text(output.to_owned());
    };
    let mut parts = Vec::new();
    if !output.is_empty() {
        parts.push(InputContent::input_text(output));
    }
    parts.push(InputContent::input_image(image.mime_type, image.data));
    FunctionCallOutputContent::Parts(parts)
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
        #[serde(default)]
        id: Option<String>,
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
    use std::collections::HashMap;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::mpsc;
    use std::thread;

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
                details: None,
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
    fn converts_pipe_separated_tool_call_ids() {
        let input = to_response_input(&[
            Event::ToolCall {
                id: "call_pwd|fc_pwd".to_owned(),
                name: "pwd".to_owned(),
                arguments: json!({}),
            },
            Event::ToolResult {
                tool_call_id: "call_pwd|fc_pwd".to_owned(),
                name: "pwd".to_owned(),
                output: "/tmp/project".to_owned(),
                details: None,
            },
        ]);
        let value = serde_json::to_value(input).unwrap();

        assert_eq!(value[1]["type"], "function_call");
        assert_eq!(value[1]["call_id"], "call_pwd");
        assert_eq!(value[1]["id"], "fc_pwd");
        assert_eq!(value[2]["type"], "function_call_output");
        assert_eq!(value[2]["call_id"], "call_pwd");
    }

    #[test]
    fn converts_image_tool_results_to_response_content_parts() {
        let input = to_response_input(&[Event::ToolResult {
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
        let value = serde_json::to_value(input).unwrap();

        assert_eq!(value[1]["type"], "function_call_output");
        assert_eq!(value[1]["output"][0]["type"], "input_text");
        assert_eq!(value[1]["output"][1]["type"], "input_image");
        assert_eq!(
            value[1]["output"][1]["image_url"],
            "data:image/png;base64,abc123"
        );
    }

    #[test]
    fn hashes_foreign_pipe_separated_tool_item_ids() {
        let input = to_response_input(&[Event::ToolCall {
            id: "call_pwd|unsafe/item+id==".to_owned(),
            name: "pwd".to_owned(),
            arguments: json!({}),
        }]);
        let value = serde_json::to_value(input).unwrap();
        let item_id = value[1]["id"].as_str().unwrap();

        assert_eq!(value[1]["call_id"], "call_pwd");
        assert!(item_id.starts_with("fc_"));
        assert!(item_id.len() <= 64);
        assert!(
            item_id
                .chars()
                .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
        );
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
                id: "call_pwd|fc_pwd".to_owned(),
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

    #[test]
    fn resolves_cache_retention_values() {
        assert_eq!(
            CacheRetention::parse("short").unwrap(),
            CacheRetention::Short
        );
        assert_eq!(CacheRetention::parse("long").unwrap(), CacheRetention::Long);
        assert_eq!(CacheRetention::parse("none").unwrap(), CacheRetention::None);
        assert!(CacheRetention::parse("forever").is_err());
    }

    #[test]
    fn builds_prompt_cache_fields_from_session_id() {
        let model = OpenAiResponsesModel::with_cache(
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
    fn disables_prompt_cache_and_affinity_when_cache_retention_is_none() {
        let model = OpenAiResponsesModel::with_cache(
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

    #[test]
    fn sends_prompt_cache_and_affinity_fields() {
        let server = TestServer::start(json!({
            "output": [{
                "type": "message",
                "role": "assistant",
                "content": [{ "type": "output_text", "text": "ok", "annotations": [] }]
            }]
        }));
        let mut model = OpenAiResponsesModel::with_cache(
            server.base_url(),
            "test-key".to_owned(),
            "test-model".to_owned(),
            Some("session-123".to_owned()),
            CacheRetention::Long,
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
        assert!(!request.body.as_object().unwrap().contains_key("tools"));
        assert_eq!(request.headers.get("session_id").unwrap(), "session-123");
        assert_eq!(
            request.headers.get("x-client-request-id").unwrap(),
            "session-123"
        );
    }

    #[test]
    fn omits_prompt_cache_and_affinity_fields_when_retention_is_none() {
        let server = TestServer::start(json!({
            "output": [{
                "type": "message",
                "role": "assistant",
                "content": [{ "type": "output_text", "text": "ok", "annotations": [] }]
            }]
        }));
        let mut model = OpenAiResponsesModel::with_cache(
            server.base_url(),
            "test-key".to_owned(),
            "test-model".to_owned(),
            Some("session-123".to_owned()),
            CacheRetention::None,
        );

        model
            .next_step(
                &[Event::UserMessage {
                    content: "hello".to_owned(),
                }],
                &[],
            )
            .unwrap();
        let request = server.request();

        assert!(request.body["prompt_cache_key"].is_null());
        assert!(request.body["prompt_cache_retention"].is_null());
        assert!(!request.headers.contains_key("session_id"));
        assert!(!request.headers.contains_key("x-client-request-id"));
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
