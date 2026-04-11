use super::BridgeAdapter;
use crate::bridge::contracts::turn_events::{
    TurnCompletedEvent, TurnStatus, TurnError, TurnEvent, TurnStartedEvent,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;
use std::env;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct OpenAiBridgeAdapter;

const OPENAI_APP_SERVER_SUBCOMMAND: &str = "app-server";
const OPENAI_CLI_BIN: &str = "codex";

impl BridgeAdapter for OpenAiBridgeAdapter {
    fn run(&self, args: &[String]) -> Result<(), String> {
        let bin = resolve_openai_bin()?;

        let mut child = Command::new(bin)
            .arg(OPENAI_APP_SERVER_SUBCOMMAND)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|err| {
                format!("failed to start '{bin} {OPENAI_APP_SERVER_SUBCOMMAND}': {err}")
            })?;

        let mut child_stdin = child
            .stdin
            .take()
            .ok_or_else(|| "failed to capture child stdin".to_string())?;
        let child_stdout = child
            .stdout
            .take()
            .ok_or_else(|| "failed to capture child stdout".to_string())?;

        let stdin_forwarder = thread::spawn(move || -> Result<(), String> {
            let mut stdin = io::stdin().lock();
            io::copy(&mut stdin, &mut child_stdin)
                .map_err(|err| format!("failed forwarding chat stdin to codex: {err}"))?;
            child_stdin
                .flush()
                .map_err(|err| format!("failed flushing codex stdin: {err}"))
        });

        let mut mapper = OpenAiNotificationMapper::new();
        let mut output = io::stdout().lock();
        let mut reader = BufReader::new(child_stdout);
        process_codex_output(&mut reader, &mut output, &mut mapper)?;

        match stdin_forwarder.join() {
            Ok(Ok(())) => {}
            Ok(Err(err)) => eprintln!("chat stdin forwarder warning: {err}"),
            Err(_) => eprintln!("chat stdin forwarder warning: thread panicked"),
        }

        let status = child.wait().map_err(|err| {
            format!("failed while running '{bin} {OPENAI_APP_SERVER_SUBCOMMAND}': {err}")
        })?;

        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "'{bin} {OPENAI_APP_SERVER_SUBCOMMAND}' exited with status {status}"
            ))
        }
    }
}

fn process_codex_output<R: BufRead, W: Write>(
    reader: &mut R,
    output: &mut W,
    mapper: &mut OpenAiNotificationMapper,
) -> Result<(), String> {
    let mut line = String::new();

    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| format!("failed reading codex app-server output: {err}"))?;
        if bytes == 0 {
            break;
        }

        match mapper.map_notification_json(line.trim_end()) {
            Ok(Some(event)) => {
                let serialized = serialize_turn_event(&event)?;
                writeln!(output, "{serialized}")
                    .map_err(|err| format!("failed writing chat event output: {err}"))?;
                output
                    .flush()
                    .map_err(|err| format!("failed flushing chat event output: {err}"))?;
            }
            Ok(None) => {}
            Err(err) => {
                eprintln!("chat mapper warning: {err}");
            }
        }
    }

    Ok(())
}

fn serialize_turn_event(event: &TurnEvent) -> Result<String, String> {
    match event {
        TurnEvent::Started(value) => serde_json::to_string(value)
            .map_err(|err| format!("failed to serialize started event: {err}")),
        TurnEvent::Completed(value) => serde_json::to_string(value)
            .map_err(|err| format!("failed to serialize completed event: {err}")),
    }
}

#[derive(Debug, Clone)]
struct CachedAgentMessage {
    text: String,
    is_final_answer: bool,
}

#[cfg_attr(not(test), allow(dead_code))]
pub struct OpenAiNotificationMapper {
    final_answers_by_thread: HashMap<String, CachedAgentMessage>,
}

#[cfg_attr(not(test), allow(dead_code))]
impl OpenAiNotificationMapper {
    pub fn new() -> Self {
        Self {
            final_answers_by_thread: HashMap::new(),
        }
    }

    pub fn map_notification_json(
        &mut self,
        raw_notification: &str,
    ) -> Result<Option<TurnEvent>, String> {
        if raw_notification.trim().is_empty() {
            return Ok(None);
        }

        let json_value: Value = serde_json::from_str(raw_notification).map_err(|err| {
            format!("failed to parse codex notification JSON: {err}; input: {raw_notification}")
        })?;

        let Some(method) = json_value.get("method").and_then(Value::as_str) else {
            return Ok(None);
        };
        let params = json_value.get("params").cloned().unwrap_or(Value::Null);

        match method {
            "turn/started" => self.map_turn_started(params),
            "item/completed" => self.map_item_completed(params),
            "turn/completed" => self.map_turn_completed(params),
            _ => Ok(None),
        }
    }

    fn map_turn_started(&mut self, params: Value) -> Result<Option<TurnEvent>, String> {
        let params: TurnStartedParams = serde_json::from_value(params)
            .map_err(|err| format!("invalid turn/started params: {err}"))?;

        Ok(Some(TurnEvent::Started(TurnStartedEvent::new(
            params.thread_id,
        ))))
    }

    fn map_item_completed(&mut self, params: Value) -> Result<Option<TurnEvent>, String> {
        let params: ItemCompletedParams = serde_json::from_value(params)
            .map_err(|err| format!("invalid item/completed params: {err}"))?;

        if params.item.item_type != "agentMessage" {
            return Ok(None);
        }

        let Some(text) = params.item.text else {
            return Ok(None);
        };

        let trimmed = text.trim();
        if trimmed.is_empty() {
            return Ok(None);
        }

        let is_final_answer = matches!(params.item.phase.as_deref(), Some("final_answer"));
        self.cache_agent_message(params.thread_id, trimmed.to_string(), is_final_answer);

        Ok(None)
    }

    fn map_turn_completed(&mut self, params: Value) -> Result<Option<TurnEvent>, String> {
        let params: TurnCompletedParams = serde_json::from_value(params)
            .map_err(|err| format!("invalid turn/completed params: {err}"))?;

        let Some(status) = TurnStatus::from_codex_status(&params.turn.status) else {
            return Err(format!(
                "unsupported turn status '{}' in turn/completed",
                params.turn.status
            ));
        };

        let answer = if status == TurnStatus::Completed {
            self.final_answers_by_thread
                .remove(&params.thread_id)
                .map(|value| value.text)
        } else {
            self.final_answers_by_thread.remove(&params.thread_id);
            None
        };

        let error = params.turn.error.and_then(map_turn_error);

        Ok(Some(TurnEvent::Completed(TurnCompletedEvent::new(
            params.thread_id,
            status,
            answer,
            error,
        ))))
    }

    fn cache_agent_message(&mut self, thread_id: String, text: String, is_final_answer: bool) {
        match self.final_answers_by_thread.get_mut(&thread_id) {
            Some(existing) if existing.is_final_answer && !is_final_answer => {}
            Some(existing) => {
                existing.text = text;
                existing.is_final_answer = is_final_answer;
            }
            None => {
                self.final_answers_by_thread.insert(
                    thread_id,
                    CachedAgentMessage {
                        text,
                        is_final_answer,
                    },
                );
            }
        }
    }
}

#[derive(Debug, Deserialize)]
struct TurnStartedParams {
    #[serde(rename = "threadId")]
    thread_id: String,
}

#[derive(Debug, Deserialize)]
struct ItemCompletedParams {
    #[serde(rename = "threadId")]
    thread_id: String,
    item: CompletedItem,
}

#[derive(Debug, Deserialize)]
struct CompletedItem {
    #[serde(rename = "type")]
    item_type: String,
    text: Option<String>,
    phase: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TurnCompletedParams {
    #[serde(rename = "threadId")]
    thread_id: String,
    turn: CompletedTurn,
}

#[derive(Debug, Deserialize)]
struct CompletedTurn {
    status: String,
    error: Option<CompletedTurnError>,
}

#[derive(Debug, Deserialize)]
struct CompletedTurnError {
    message: String,
    #[serde(default)]
    code: Option<Value>,
    #[serde(rename = "codexErrorInfo", default)]
    codex_error_info: Option<Value>,
}

fn map_turn_error(error: CompletedTurnError) -> Option<TurnError> {
    let code = error
        .code
        .as_ref()
        .and_then(extract_error_code)
        .or_else(|| error.codex_error_info.as_ref().and_then(extract_error_code));

    if error.message.trim().is_empty() {
        None
    } else {
        Some(TurnError::new(error.message, code))
    }
}

fn extract_error_code(value: &Value) -> Option<String> {
    match value {
        Value::String(code) => Some(code.clone()),
        Value::Object(fields) => fields.keys().next().cloned(),
        _ => None,
    }
}

fn resolve_openai_bin() -> Result<&'static str, String> {
    if command_exists(OPENAI_CLI_BIN) {
        Ok(OPENAI_CLI_BIN)
    } else {
        Err(format!(
            "openai chat requires '{}' to be installed and available on PATH",
            OPENAI_CLI_BIN
        ))
    }
}

fn command_exists(command: &str) -> bool {
    match Command::new(command)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
    {
        Ok(_) => true,
        Err(err) => !matches!(err.kind(), std::io::ErrorKind::NotFound),
    }
}

fn run_codex_schema_generation(out_dir: &Path) -> Result<(), String> {
    let status = Command::new("codex")
        .arg("app-server")
        .arg("generate-json-schema")
        .arg("--out")
        .arg(out_dir)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|err| format!("failed to run codex schema generation: {err}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "codex app-server generate-json-schema failed with status {status}"
        ))
    }
}

fn schema_output_dir() -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_nanos())
        .unwrap_or_default();

    env::temp_dir().join(format!(
        "agent-codex-schema-{}-{unique}",
        std::process::id()
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        OpenAiNotificationMapper, process_codex_output, resolve_openai_bin,
        run_codex_schema_generation, schema_output_dir,
    };
    use crate::bridge::contracts::turn_events::{TurnStatus, TurnEvent};
    use std::fs;
    use std::io::Cursor;

    #[test]
    fn resolve_requires_codex_binary() {
        if super::command_exists("codex") {
            assert_eq!(resolve_openai_bin().ok(), Some("codex"));
        } else {
            assert!(resolve_openai_bin().is_err());
        }
    }

    #[test]
    fn maps_started_notification_to_contract_event() {
        let mut mapper = OpenAiNotificationMapper::new();
        let event = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"inProgress","items":[]}}}"#,
            )
            .expect("turn/started should parse")
            .expect("turn/started should produce an event");

        match event {
            TurnEvent::Started(value) => {
                assert_eq!(value.id, "thread-1");
                assert_eq!(value.status, TurnStatus::Thinking);
            }
            _ => panic!("expected turn.started event"),
        }
    }

    #[test]
    fn ignores_non_notification_json_rpc_messages() {
        let mut mapper = OpenAiNotificationMapper::new();
        let response = mapper
            .map_notification_json(r#"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#)
            .expect("json-rpc response should parse");
        assert!(response.is_none());
    }

    #[test]
    fn maps_completed_notification_with_final_answer() {
        let mut mapper = OpenAiNotificationMapper::new();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"type":"agentMessage","id":"item-1","phase":"final_answer","text":"Final answer text"}}}"#,
            )
            .expect("item/completed should parse")
            .expect_none();

        let completed = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed","items":[]}}}"#,
            )
            .expect("turn/completed should parse")
            .expect("turn/completed should produce event");

        match completed {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("Final answer text"));
                assert!(value.error.is_none());
            }
            _ => panic!("expected turn.completed event"),
        }
    }

    #[test]
    fn completed_without_final_phase_falls_back_to_last_agent_message() {
        let mut mapper = OpenAiNotificationMapper::new();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-2","turnId":"turn-1","item":{"type":"agentMessage","id":"item-1","phase":"commentary","text":"Working..."}}}"#,
            )
            .expect("commentary item should parse")
            .expect_none();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-2","turnId":"turn-1","item":{"type":"agentMessage","id":"item-2","phase":"commentary","text":"Final fallback answer"}}}"#,
            )
            .expect("second commentary item should parse")
            .expect_none();

        let completed = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-2","turn":{"id":"turn-1","status":"completed","items":[]}}}"#,
            )
            .expect("turn/completed should parse")
            .expect("turn/completed should produce event");

        match completed {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("Final fallback answer"));
            }
            _ => panic!("expected turn.completed event"),
        }
    }

    #[test]
    fn final_answer_is_not_overwritten_by_later_commentary_item() {
        let mut mapper = OpenAiNotificationMapper::new();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-3","turnId":"turn-1","item":{"type":"agentMessage","id":"item-1","phase":"final_answer","text":"Stable final answer"}}}"#,
            )
            .expect("final answer item should parse")
            .expect_none();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-3","turnId":"turn-1","item":{"type":"agentMessage","id":"item-2","phase":"commentary","text":"Late commentary"}}}"#,
            )
            .expect("commentary item should parse")
            .expect_none();

        let completed = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-3","turn":{"id":"turn-1","status":"completed","items":[]}}}"#,
            )
            .expect("turn/completed should parse")
            .expect("turn/completed should produce event");

        match completed {
            TurnEvent::Completed(value) => {
                assert_eq!(value.answer.as_deref(), Some("Stable final answer"));
            }
            _ => panic!("expected turn.completed event"),
        }
    }

    #[test]
    fn interrupted_turn_drops_cached_answer() {
        let mut mapper = OpenAiNotificationMapper::new();

        mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-4","turnId":"turn-1","item":{"type":"agentMessage","id":"item-1","phase":"final_answer","text":"Should not appear"}}}"#,
            )
            .expect("item/completed should parse")
            .expect_none();

        let completed = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-4","turn":{"id":"turn-1","status":"interrupted","items":[]}}}"#,
            )
            .expect("turn/completed should parse")
            .expect("turn/completed should produce event");

        match completed {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Interrupted);
                assert!(value.answer.is_none());
            }
            _ => panic!("expected turn.completed event"),
        }
    }

    #[test]
    fn maps_failed_completion_with_error_and_ignores_unknown_fields() {
        let mut mapper = OpenAiNotificationMapper::new();

        let completed = mapper
            .map_notification_json(
                r#"{"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","unexpected":"field","turn":{"id":"turn-1","status":"failed","items":[],"error":{"message":"Boom","codexErrorInfo":{"serverOverloaded":{}},"extra":"ignored"}},"unused":{"a":1}}}"#,
            )
            .expect("turn/completed should parse")
            .expect("turn/completed should produce event");

        match completed {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Failed);
                assert!(value.answer.is_none());
                let error = value.error.expect("failed turn should include error");
                assert_eq!(error.message, "Boom");
                assert_eq!(error.code.as_deref(), Some("serverOverloaded"));
            }
            _ => panic!("expected turn.completed event"),
        }
    }

    #[test]
    fn schema_guard_verifies_required_codex_notifications_and_statuses() {
        if !super::command_exists("codex") {
            eprintln!("skipping schema guard: 'codex' binary not found");
            return;
        }

        let output_dir = schema_output_dir();
        fs::create_dir_all(&output_dir).expect("should create schema output directory");
        run_codex_schema_generation(&output_dir).expect("codex schema generation should succeed");

        let notifications = fs::read_to_string(output_dir.join("ServerNotification.json"))
            .expect("should read generated ServerNotification schema");
        assert!(notifications.contains("\"turn/started\""));
        assert!(notifications.contains("\"turn/completed\""));
        assert!(notifications.contains("\"item/completed\""));

        let turn_completed =
            fs::read_to_string(output_dir.join("v2/TurnCompletedNotification.json"))
                .expect("should read generated TurnCompletedNotification schema");
        assert!(turn_completed.contains("\"completed\""));
        assert!(turn_completed.contains("\"interrupted\""));
        assert!(turn_completed.contains("\"failed\""));

        let _ = fs::remove_dir_all(output_dir);
    }

    #[test]
    fn process_codex_output_emits_only_contract_events() {
        let input = concat!(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\n",
            "{\"jsonrpc\":\"2.0\",\"method\":\"turn/started\",\"params\":{\"threadId\":\"thread-live\"}}\n",
            "{\"jsonrpc\":\"2.0\",\"method\":\"item/completed\",\"params\":{\"threadId\":\"thread-live\",\"item\":{\"type\":\"agentMessage\",\"phase\":\"final_answer\",\"text\":\"Hello\"}}}\n",
            "{\"jsonrpc\":\"2.0\",\"method\":\"turn/completed\",\"params\":{\"threadId\":\"thread-live\",\"turn\":{\"status\":\"completed\"}}}\n",
            "{\"jsonrpc\":\"2.0\",\"method\":\"thread/started\",\"params\":{\"threadId\":\"ignored\"}}\n"
        );

        let mut reader = Cursor::new(input.as_bytes());
        let mut output: Vec<u8> = Vec::new();
        let mut mapper = OpenAiNotificationMapper::new();
        process_codex_output(&mut reader, &mut output, &mut mapper)
            .expect("processing should succeed");

        let output_text = String::from_utf8(output).expect("output should be utf-8");
        let lines: Vec<&str> = output_text.lines().collect();
        assert_eq!(lines.len(), 2, "only started/completed should be emitted");
        assert!(lines[0].contains("\"id\":\"thread-live\""));
        assert!(lines[0].contains("\"status\":\"thinking\""));
        assert!(lines[1].contains("\"id\":\"thread-live\""));
        assert!(lines[1].contains("\"status\":\"completed\""));
        assert!(lines[1].contains("\"answer\":\"Hello\""));
    }

    trait TestOptionExt<T> {
        fn expect_none(self);
    }

    impl<T> TestOptionExt<T> for Option<T> {
        fn expect_none(self) {
            assert!(self.is_none(), "expected no event");
        }
    }
}
