use super::BridgeAdapter;
use crate::bridge::contracts::turn_events::{
    TurnCompletedEvent, TurnCompletionStatus, TurnError, TurnEvent, TurnStartedEvent,
};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::{self, BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

pub struct GoogleBridgeAdapter;

const GOOGLE_ACP_FLAG: &str = "--acp";
const GOOGLE_CLI_BIN: &str = "gemini";

impl BridgeAdapter for GoogleBridgeAdapter {
    fn run(&self, args: &[String]) -> Result<(), String> {
        let bin = resolve_google_bin()?;

        let mut child = Command::new(bin)
            .arg(GOOGLE_ACP_FLAG)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|err| format!("failed to start '{bin} {GOOGLE_ACP_FLAG}': {err}"))?;

        let child_stdin = child
            .stdin
            .take()
            .ok_or_else(|| "failed to capture child stdin".to_string())?;
        let child_stdout = child
            .stdout
            .take()
            .ok_or_else(|| "failed to capture child stdout".to_string())?;

        let mapper = Arc::new(Mutex::new(GoogleNotificationMapper::new()));
        let stdin_mapper = Arc::clone(&mapper);
        let stdin_forwarder = thread::spawn(move || -> Result<(), String> {
            forward_stdin_to_gemini(child_stdin, stdin_mapper)
        });

        let mut output = io::stdout().lock();
        let mut reader = BufReader::new(child_stdout);
        process_gemini_output(&mut reader, &mut output, mapper)?;

        match stdin_forwarder.join() {
            Ok(Ok(())) => {}
            Ok(Err(err)) => eprintln!("chat stdin forwarder warning: {err}"),
            Err(_) => eprintln!("chat stdin forwarder warning: thread panicked"),
        }

        let status = child
            .wait()
            .map_err(|err| format!("failed while running '{bin} {GOOGLE_ACP_FLAG}': {err}"))?;

        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "'{bin} {GOOGLE_ACP_FLAG}' exited with status {status}"
            ))
        }
    }
}

fn forward_stdin_to_gemini(
    mut child_stdin: impl Write,
    mapper: Arc<Mutex<GoogleNotificationMapper>>,
) -> Result<(), String> {
    let mut line = String::new();
    let stdin = io::stdin();
    let mut reader = BufReader::new(stdin.lock());

    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| format!("failed reading chat stdin: {err}"))?;
        if bytes == 0 {
            break;
        }

        if let Ok(mut mapper) = mapper.lock() {
            mapper.observe_client_request(line.trim_end());
        }

        child_stdin
            .write_all(line.as_bytes())
            .map_err(|err| format!("failed forwarding chat stdin to gemini: {err}"))?;
        child_stdin
            .flush()
            .map_err(|err| format!("failed flushing gemini stdin: {err}"))?;
    }

    Ok(())
}

fn process_gemini_output<R: BufRead, W: Write>(
    reader: &mut R,
    output: &mut W,
    mapper: Arc<Mutex<GoogleNotificationMapper>>,
) -> Result<(), String> {
    let mut line = String::new();

    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| format!("failed reading gemini acp output: {err}"))?;
        if bytes == 0 {
            break;
        }

        let events = match mapper.lock() {
            Ok(mut mapper) => mapper.map_server_message(line.trim_end())?,
            Err(_) => return Err("failed to lock google chat mapper".to_string()),
        };

        for event in events {
            let serialized = serialize_turn_event(&event)?;
            writeln!(output, "{serialized}")
                .map_err(|err| format!("failed writing chat event output: {err}"))?;
        }

        if !line.is_empty() {
            output
                .flush()
                .map_err(|err| format!("failed flushing chat event output: {err}"))?;
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

struct GoogleNotificationMapper {
    pending_prompt_by_request_id: HashMap<String, String>,
    pending_prompt_count_by_session: HashMap<String, usize>,
    started_sessions: HashSet<String>,
    agent_text_by_session: HashMap<String, String>,
}

impl GoogleNotificationMapper {
    fn new() -> Self {
        Self {
            pending_prompt_by_request_id: HashMap::new(),
            pending_prompt_count_by_session: HashMap::new(),
            started_sessions: HashSet::new(),
            agent_text_by_session: HashMap::new(),
        }
    }

    fn observe_client_request(&mut self, raw_line: &str) {
        let Ok(value) = serde_json::from_str::<Value>(raw_line) else {
            return;
        };

        let Some(method) = value.get("method").and_then(Value::as_str) else {
            return;
        };
        if method != "session/prompt" {
            return;
        }

        let Some(request_id) = value.get("id").and_then(request_id_key) else {
            return;
        };
        let Some(session_id) = value
            .get("params")
            .and_then(|params| params.get("sessionId"))
            .and_then(Value::as_str)
        else {
            return;
        };

        let session_id = session_id.to_string();
        self.pending_prompt_by_request_id
            .insert(request_id, session_id.clone());
        *self
            .pending_prompt_count_by_session
            .entry(session_id.clone())
            .or_insert(0) += 1;
        self.started_sessions.remove(&session_id);
        self.agent_text_by_session.remove(&session_id);
    }

    fn map_server_message(&mut self, raw_line: &str) -> Result<Vec<TurnEvent>, String> {
        let mut events = Vec::new();
        if raw_line.trim().is_empty() {
            return Ok(events);
        }

        let Ok(value) = serde_json::from_str::<Value>(raw_line) else {
            return Ok(events);
        };

        if let Some(method) = value.get("method").and_then(Value::as_str) {
            if method == "session/update" {
                self.map_session_update(&value, &mut events)?;
            }
            return Ok(events);
        }

        if value.get("id").is_some() {
            self.map_response(&value, &mut events)?;
        }

        Ok(events)
    }

    fn map_session_update(
        &mut self,
        value: &Value,
        events: &mut Vec<TurnEvent>,
    ) -> Result<(), String> {
        let params = value
            .get("params")
            .ok_or_else(|| "invalid session/update message: missing params".to_string())?;
        let session_id = params
            .get("sessionId")
            .and_then(Value::as_str)
            .ok_or_else(|| "invalid session/update params: missing sessionId".to_string())?
            .to_string();

        let update = params
            .get("update")
            .ok_or_else(|| "invalid session/update params: missing update".to_string())?;
        let update_type = update
            .get("sessionUpdate")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                "invalid session/update params: missing update.sessionUpdate".to_string()
            })?;

        if self.has_pending_prompt(&session_id)
            && !self.started_sessions.contains(&session_id)
            && is_progress_update(update_type)
        {
            self.started_sessions.insert(session_id.clone());
            events.push(TurnEvent::Started(TurnStartedEvent::new(
                session_id.clone(),
            )));
        }

        if update_type == "agent_message_chunk"
            && let Some(text) = update
                .get("content")
                .and_then(|content| content.get("text"))
                .and_then(Value::as_str)
        {
            if !text.is_empty() {
                self.agent_text_by_session
                    .entry(session_id)
                    .and_modify(|existing| existing.push_str(text))
                    .or_insert_with(|| text.to_string());
            }
        }

        Ok(())
    }

    fn map_response(&mut self, value: &Value, events: &mut Vec<TurnEvent>) -> Result<(), String> {
        let Some(request_id) = value.get("id").and_then(request_id_key) else {
            return Ok(());
        };

        let Some(session_id) = self.pending_prompt_by_request_id.remove(&request_id) else {
            return Ok(());
        };

        if !self.started_sessions.contains(&session_id) {
            self.started_sessions.insert(session_id.clone());
            events.push(TurnEvent::Started(TurnStartedEvent::new(
                session_id.clone(),
            )));
        }

        let (status, error) = if let Some(error) = value.get("error") {
            let message = error
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("unknown error")
                .to_string();
            let code = error.get("code").and_then(|code| match code {
                Value::String(value) => Some(value.clone()),
                Value::Number(value) => Some(value.to_string()),
                _ => None,
            });
            (
                TurnCompletionStatus::Failed,
                Some(TurnError::new(message, code)),
            )
        } else {
            let stop_reason = value
                .get("result")
                .and_then(|result| result.get("stopReason"))
                .and_then(Value::as_str)
                .unwrap_or("end_turn");

            let status = map_stop_reason(stop_reason);
            (status, None)
        };

        let answer = if status == TurnCompletionStatus::Completed {
            self.agent_text_by_session.remove(&session_id)
        } else {
            self.agent_text_by_session.remove(&session_id);
            None
        };

        events.push(TurnEvent::Completed(TurnCompletedEvent::new(
            session_id.clone(),
            status,
            answer,
            error,
        )));

        self.started_sessions.remove(&session_id);
        self.decrement_pending_prompt_count(&session_id);

        Ok(())
    }

    fn has_pending_prompt(&self, session_id: &str) -> bool {
        self.pending_prompt_count_by_session
            .get(session_id)
            .copied()
            .unwrap_or(0)
            > 0
    }

    fn decrement_pending_prompt_count(&mut self, session_id: &str) {
        if let Some(value) = self.pending_prompt_count_by_session.get_mut(session_id) {
            if *value <= 1 {
                self.pending_prompt_count_by_session.remove(session_id);
            } else {
                *value -= 1;
            }
        }
    }
}

fn is_progress_update(update_type: &str) -> bool {
    matches!(
        update_type,
        "user_message_chunk"
            | "agent_message_chunk"
            | "agent_thought_chunk"
            | "tool_call"
            | "tool_call_update"
            | "plan"
            | "usage_update"
    )
}

fn map_stop_reason(stop_reason: &str) -> TurnCompletionStatus {
    match stop_reason {
        "cancelled" => TurnCompletionStatus::Interrupted,
        _ => TurnCompletionStatus::Completed,
    }
}

fn request_id_key(value: &Value) -> Option<String> {
    match value {
        Value::String(value) => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        _ => None,
    }
}

fn resolve_google_bin() -> Result<&'static str, String> {
    if command_exists(GOOGLE_CLI_BIN) {
        Ok(GOOGLE_CLI_BIN)
    } else {
        Err(format!(
            "google chat requires '{}' to be installed and available on PATH",
            GOOGLE_CLI_BIN
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

#[cfg(test)]
mod tests {
    use super::{GoogleNotificationMapper, process_gemini_output, resolve_google_bin};
    use crate::bridge::contracts::turn_events::{TurnCompletionStatus, TurnEvent};
    use serde_json::Value;
    use std::io::Cursor;
    use std::sync::{Arc, Mutex};

    #[test]
    fn resolve_requires_gemini_binary() {
        if super::command_exists("gemini") {
            assert_eq!(resolve_google_bin().ok(), Some("gemini"));
        } else {
            assert!(resolve_google_bin().is_err());
        }
    }

    #[test]
    fn prompt_updates_emit_started_once() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-1","method":"session/prompt","params":{"sessionId":"session-1","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let started = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-1","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking"}}}}"#,
            )
            .expect("first update should parse");
        assert_eq!(started.len(), 1);
        assert!(matches!(started[0], TurnEvent::Started(_)));

        let second = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hello"}}}}"#,
            )
            .expect("second update should parse");
        assert!(second.is_empty());
    }

    #[test]
    fn started_event_matches_contract_fields() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-started","method":"session/prompt","params":{"sessionId":"session-started","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-started","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking"}}}}"#,
            )
            .expect("update should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Started(value) => {
                assert_eq!(value.thread_id, "session-started");
                assert_eq!(value.state, "in_progress");
            }
            _ => panic!("expected turn.started"),
        }
    }

    #[test]
    fn completed_response_emits_completed_with_answer() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-2","method":"session/prompt","params":{"sessionId":"session-2","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-2","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello"}}}}"#,
            )
            .expect("chunk should parse");

        mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-2","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":" world"}}}}"#,
            )
            .expect("chunk should parse");

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-2","result":{"stopReason":"end_turn"}}"#,
            )
            .expect("completion should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnCompletionStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("Hello world"));
                assert!(value.error.is_none());
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn supports_numeric_request_ids_for_prompt_tracking() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":42,"method":"session/prompt","params":{"sessionId":"session-numeric","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-numeric","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hello numeric"}}}}"#,
            )
            .expect("chunk should parse");

        let events = mapper
            .map_server_message(r#"{"jsonrpc":"2.0","id":42,"result":{"stopReason":"end_turn"}}"#)
            .expect("completion should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnCompletionStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("hello numeric"));
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn completion_without_updates_emits_started_then_completed() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-3","method":"session/prompt","params":{"sessionId":"session-3","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-3","result":{"stopReason":"end_turn"}}"#,
            )
            .expect("completion should parse");

        assert_eq!(events.len(), 2);
        assert!(matches!(events[0], TurnEvent::Started(_)));
        assert!(matches!(events[1], TurnEvent::Completed(_)));
    }

    #[test]
    fn cancelled_response_maps_to_interrupted() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-4","method":"session/prompt","params":{"sessionId":"session-4","prompt":[{"type":"text","text":"hello"}]}}"#,
        );
        mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-4","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"partial"}}}}"#,
            )
            .expect("chunk should parse");

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-4","result":{"stopReason":"cancelled"}}"#,
            )
            .expect("cancelled response should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnCompletionStatus::Interrupted);
                assert!(value.answer.is_none());
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn error_response_maps_to_failed() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-5","method":"session/prompt","params":{"sessionId":"session-5","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-5","error":{"code":429,"message":"rate limit"}}"#,
            )
            .expect("error response should parse");

        assert_eq!(events.len(), 2);
        match &events[1] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnCompletionStatus::Failed);
                assert!(value.answer.is_none());
                let error = value.error.as_ref().expect("error should be present");
                assert_eq!(error.message, "rate limit");
                assert_eq!(error.code.as_deref(), Some("429"));
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn failed_response_with_string_code_and_unknown_fields_is_mapped() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-failed","method":"session/prompt","params":{"sessionId":"session-failed","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-failed","error":{"code":"provider_overloaded","message":"Boom","extra":"ignored"},"unexpected":{"nested":true}}"#,
            )
            .expect("error response should parse");

        assert_eq!(events.len(), 2);
        match &events[1] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnCompletionStatus::Failed);
                assert!(value.answer.is_none());
                let error = value.error.as_ref().expect("error should be present");
                assert_eq!(error.message, "Boom");
                assert_eq!(error.code.as_deref(), Some("provider_overloaded"));
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn ignores_non_json_and_untracked_messages() {
        let mut mapper = GoogleNotificationMapper::new();
        let non_json = mapper
            .map_server_message("Ignore file not found: .geminiignore")
            .expect("non json should be ignored");
        assert!(non_json.is_empty());

        let unrelated_json = mapper
            .map_server_message(r#"{"jsonrpc":"2.0","id":"init-1","result":{"protocolVersion":1}}"#)
            .expect("untracked response should be ignored");
        assert!(unrelated_json.is_empty());
    }

    #[test]
    fn ignores_non_prompt_client_requests_for_tracking() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-init","method":"initialize","params":{"protocolVersion":1}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-init","result":{"protocolVersion":1}}"#,
            )
            .expect("initialize response should parse");
        assert!(events.is_empty());
    }

    #[test]
    fn non_progress_updates_do_not_emit_started() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-commands","method":"session/prompt","params":{"sessionId":"session-commands","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-commands","update":{"sessionUpdate":"available_commands_update","availableCommands":[]}}}"#,
            )
            .expect("available commands update should parse");
        assert!(events.is_empty());
    }

    #[test]
    fn completed_event_serializes_expected_fields() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-serial","method":"session/prompt","params":{"sessionId":"session-serial","prompt":[{"type":"text","text":"hello"}]}}"#,
        );
        mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"session-serial","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"done"}}}}"#,
            )
            .expect("chunk should parse");
        let events = mapper
            .map_server_message(
                r#"{"jsonrpc":"2.0","id":"req-serial","result":{"stopReason":"end_turn"}}"#,
            )
            .expect("completion should parse");

        let completed = match events.first() {
            Some(TurnEvent::Completed(value)) => value,
            _ => panic!("expected completed event"),
        };

        let serialized = serde_json::to_value(completed).expect("completed should serialize");
        assert_eq!(
            serialized.get("type"),
            Some(&Value::String("turn.completed".to_string()))
        );
        assert_eq!(
            serialized.get("threadId"),
            Some(&Value::String("session-serial".to_string()))
        );
        assert_eq!(
            serialized.get("status"),
            Some(&Value::String("completed".to_string()))
        );
        assert_eq!(
            serialized.get("answer"),
            Some(&Value::String("done".to_string()))
        );
    }

    #[test]
    fn process_output_emits_contract_events_only() {
        let mut mapper = GoogleNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"jsonrpc":"2.0","id":"req-6","method":"session/prompt","params":{"sessionId":"session-6","prompt":[{"type":"text","text":"hello"}]}}"#,
        );

        let input = concat!(
            "Ignore file not found: .geminiignore\n",
            "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"session-6\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"Hello\"}}}}\n",
            "{\"jsonrpc\":\"2.0\",\"id\":\"req-6\",\"result\":{\"stopReason\":\"end_turn\"}}\n",
            "{\"jsonrpc\":\"2.0\",\"id\":\"init-1\",\"result\":{\"protocolVersion\":1}}\n"
        );
        let mut reader = Cursor::new(input.as_bytes());
        let mut output: Vec<u8> = Vec::new();
        let mapper = Arc::new(Mutex::new(mapper));
        process_gemini_output(&mut reader, &mut output, mapper).expect("processing should succeed");

        let output_text = String::from_utf8(output).expect("output should be utf-8");
        let lines: Vec<&str> = output_text.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("\"type\":\"turn.started\""));
        assert!(lines[1].contains("\"type\":\"turn.completed\""));
        assert!(lines[1].contains("\"status\":\"completed\""));
        assert!(lines[1].contains("\"answer\":\"Hello\""));
    }
}
