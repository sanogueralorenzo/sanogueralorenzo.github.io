use super::{ChatAdapter, ChatInvocation, ChatPromptTarget};
use crate::chat::contracts::turn_events::{
    ProviderName, TurnCompletedEvent, TurnError, TurnEvent, TurnStartedEvent, TurnStatus,
};
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::io::{self, BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

pub struct AnthropicChatAdapter;

const ANTHROPIC_CLI_BIN: &str = "claude";
const ANTHROPIC_PRINT_FLAG: &str = "-p";
const ANTHROPIC_VERBOSE_FLAG: &str = "--verbose";
const ANTHROPIC_OUTPUT_FLAG: &str = "--output-format";
const ANTHROPIC_INPUT_FLAG: &str = "--input-format";
const ANTHROPIC_STREAM_JSON: &str = "stream-json";
const ANTHROPIC_REPLAY_USER_MESSAGES_FLAG: &str = "--replay-user-messages";

impl ChatAdapter for AnthropicChatAdapter {
    fn run(&self, invocation: &ChatInvocation) -> Result<(), String> {
        match invocation {
            ChatInvocation::Passthrough { provider_args } => run_passthrough(provider_args),
            ChatInvocation::Prompt { target, prompt } => run_prompt(target, prompt),
        }
    }
}

fn run_passthrough(args: &[String]) -> Result<(), String> {
    let bin = resolve_anthropic_bin()?;
    let mut child = spawn_anthropic_child(bin, args)?;

    let child_stdin = child
        .stdin
        .take()
        .ok_or_else(|| "failed to capture child stdin".to_string())?;
    let child_stdout = child
        .stdout
        .take()
        .ok_or_else(|| "failed to capture child stdout".to_string())?;

    let mapper = Arc::new(Mutex::new(AnthropicNotificationMapper::new()));
    let stdin_mapper = Arc::clone(&mapper);
    let stdin_forwarder = thread::spawn(move || -> Result<(), String> {
        forward_stdin_to_claude(child_stdin, stdin_mapper)
    });

    let mut output = io::stdout().lock();
    let mut reader = BufReader::new(child_stdout);
    let emitted_final_event = process_claude_output(&mut reader, &mut output, mapper)?;

    match stdin_forwarder.join() {
        Ok(Ok(())) => {}
        Ok(Err(err)) => eprintln!("chat stdin forwarder warning: {err}"),
        Err(_) => eprintln!("chat stdin forwarder warning: thread panicked"),
    }

    wait_for_anthropic_child(bin, child, emitted_final_event)
}

fn run_prompt(target: &ChatPromptTarget, prompt: &str) -> Result<(), String> {
    let bin = resolve_anthropic_bin()?;
    let provider_args = prompt_mode_provider_args(target);
    let mut child = spawn_anthropic_child(bin, &provider_args)?;

    let mut child_stdin = child
        .stdin
        .take()
        .ok_or_else(|| "failed to capture child stdin".to_string())?;
    let child_stdout = child
        .stdout
        .take()
        .ok_or_else(|| "failed to capture child stdout".to_string())?;

    let mapper = Arc::new(Mutex::new(AnthropicNotificationMapper::new()));
    let user_message = build_user_stream_message(prompt);
    if let Ok(mut locked) = mapper.lock() {
        locked.observe_client_request(&user_message);
    }
    write_json_line(&mut child_stdin, &user_message)?;
    drop(child_stdin);

    let expected_id = match target {
        ChatPromptTarget::Existing(id) => Some(id.as_str()),
        ChatPromptTarget::New => None,
    };

    let mut output = io::stdout().lock();
    let mut reader = BufReader::new(child_stdout);
    let completed =
        process_claude_output_until_completion(&mut reader, &mut output, mapper, expected_id)?;

    if !completed {
        return Err("anthropic chat prompt ended before turn completion".to_string());
    }

    let _ = child.kill();
    let _ = child.wait();
    Ok(())
}

fn prompt_mode_provider_args(target: &ChatPromptTarget) -> Vec<String> {
    match target {
        ChatPromptTarget::Existing(id) => vec!["--resume".to_string(), id.clone()],
        ChatPromptTarget::New => Vec::new(),
    }
}

fn build_user_stream_message(prompt: &str) -> String {
    json!({
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": prompt
                }
            ]
        }
    })
    .to_string()
}

fn write_json_line(stdin: &mut ChildStdin, message: &str) -> Result<(), String> {
    writeln!(stdin, "{message}")
        .map_err(|err| format!("failed writing message to claude stdin: {err}"))?;
    stdin
        .flush()
        .map_err(|err| format!("failed flushing claude stdin: {err}"))
}

fn spawn_anthropic_child(bin: &str, args: &[String]) -> Result<Child, String> {
    Command::new(bin)
        .arg(ANTHROPIC_PRINT_FLAG)
        .arg(ANTHROPIC_VERBOSE_FLAG)
        .arg(ANTHROPIC_OUTPUT_FLAG)
        .arg(ANTHROPIC_STREAM_JSON)
        .arg(ANTHROPIC_INPUT_FLAG)
        .arg(ANTHROPIC_STREAM_JSON)
        .arg(ANTHROPIC_REPLAY_USER_MESSAGES_FLAG)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|err| {
            format!(
                "failed to start '{bin} {ANTHROPIC_PRINT_FLAG} {ANTHROPIC_OUTPUT_FLAG} {ANTHROPIC_STREAM_JSON}': {err}"
            )
        })
}

fn wait_for_anthropic_child(
    bin: &str,
    mut child: Child,
    emitted_final_event: bool,
) -> Result<(), String> {
    let status = child.wait().map_err(|err| {
        format!(
            "failed while running '{bin} {ANTHROPIC_PRINT_FLAG} {ANTHROPIC_OUTPUT_FLAG} {ANTHROPIC_STREAM_JSON}': {err}"
        )
    })?;

    if status.success() || emitted_final_event {
        Ok(())
    } else {
        Err(format!(
            "'{bin} {ANTHROPIC_PRINT_FLAG} {ANTHROPIC_OUTPUT_FLAG} {ANTHROPIC_STREAM_JSON}' exited with status {status}"
        ))
    }
}

fn forward_stdin_to_claude(
    mut child_stdin: impl Write,
    mapper: Arc<Mutex<AnthropicNotificationMapper>>,
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
            .map_err(|err| format!("failed forwarding chat stdin to claude: {err}"))?;
        child_stdin
            .flush()
            .map_err(|err| format!("failed flushing claude stdin: {err}"))?;
    }

    Ok(())
}

fn process_claude_output<R: BufRead, W: Write>(
    reader: &mut R,
    output: &mut W,
    mapper: Arc<Mutex<AnthropicNotificationMapper>>,
) -> Result<bool, String> {
    let mut line = String::new();
    let mut emitted_final_event = false;

    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| format!("failed reading claude stream-json output: {err}"))?;
        if bytes == 0 {
            break;
        }

        let events = match mapper.lock() {
            Ok(mut mapper) => mapper.map_server_message(line.trim_end())?,
            Err(_) => return Err("failed to lock anthropic chat mapper".to_string()),
        };

        for event in events {
            if matches!(event, TurnEvent::Completed(_)) {
                emitted_final_event = true;
            }
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

    Ok(emitted_final_event)
}

fn process_claude_output_until_completion<R: BufRead, W: Write>(
    reader: &mut R,
    output: &mut W,
    mapper: Arc<Mutex<AnthropicNotificationMapper>>,
    expected_id: Option<&str>,
) -> Result<bool, String> {
    let mut line = String::new();

    loop {
        line.clear();
        let bytes = reader
            .read_line(&mut line)
            .map_err(|err| format!("failed reading claude stream-json output: {err}"))?;
        if bytes == 0 {
            break;
        }

        let events = match mapper.lock() {
            Ok(mut mapper) => mapper.map_server_message(line.trim_end())?,
            Err(_) => return Err("failed to lock anthropic chat mapper".to_string()),
        };

        for event in events {
            let serialized = serialize_turn_event(&event)?;
            writeln!(output, "{serialized}")
                .map_err(|err| format!("failed writing chat event output: {err}"))?;
            output
                .flush()
                .map_err(|err| format!("failed flushing chat event output: {err}"))?;

            if let TurnEvent::Completed(value) = event {
                if let Some(id) = expected_id
                    && id != value.id
                {
                    eprintln!(
                        "chat mapper warning: expected anthropic session '{id}' but completed session '{}'",
                        value.id
                    );
                }
                return Ok(true);
            }
        }
    }

    Ok(false)
}

fn serialize_turn_event(event: &TurnEvent) -> Result<String, String> {
    match event {
        TurnEvent::Started(value) => serde_json::to_string(value)
            .map_err(|err| format!("failed to serialize started event: {err}")),
        TurnEvent::Completed(value) => serde_json::to_string(value)
            .map_err(|err| format!("failed to serialize completed event: {err}")),
    }
}

#[derive(Default)]
struct PendingTurn {
    started: bool,
    assistant_text: String,
    assistant_error_code: Option<String>,
}

struct AnthropicNotificationMapper {
    pending_turns: VecDeque<PendingTurn>,
    active_session_id: Option<String>,
}

impl AnthropicNotificationMapper {
    fn new() -> Self {
        Self {
            pending_turns: VecDeque::new(),
            active_session_id: None,
        }
    }

    fn observe_client_request(&mut self, raw_line: &str) {
        let Ok(value) = serde_json::from_str::<Value>(raw_line) else {
            return;
        };

        let Some(event_type) = value.get("type").and_then(Value::as_str) else {
            return;
        };
        if event_type == "user" {
            self.pending_turns.push_back(PendingTurn::default());
        }
    }

    fn map_server_message(&mut self, raw_line: &str) -> Result<Vec<TurnEvent>, String> {
        let mut events = Vec::new();
        if raw_line.trim().is_empty() {
            return Ok(events);
        }

        let Ok(value) = serde_json::from_str::<Value>(raw_line) else {
            return Ok(events);
        };

        let Some(event_type) = value.get("type").and_then(Value::as_str) else {
            return Ok(events);
        };

        match event_type {
            "system" => self.map_system_event(&value),
            "assistant" => self.map_assistant_event(&value, &mut events)?,
            "result" => self.map_result_event(&value, &mut events),
            _ => {}
        }

        Ok(events)
    }

    fn map_system_event(&mut self, value: &Value) {
        let subtype = value.get("subtype").and_then(Value::as_str);
        if subtype != Some("init") {
            return;
        }

        if let Some(session_id) = value.get("session_id").and_then(Value::as_str) {
            self.active_session_id = Some(session_id.to_string());
        }
    }

    fn map_assistant_event(
        &mut self,
        value: &Value,
        events: &mut Vec<TurnEvent>,
    ) -> Result<(), String> {
        let thread_id = self.resolve_session_id(value)?;
        let Some(turn) = self.pending_turns.front_mut() else {
            return Ok(());
        };

        if !turn.started {
            turn.started = true;
            events.push(TurnEvent::Started(TurnStartedEvent::new(
                ProviderName::Anthropic,
                thread_id.clone(),
            )));
        }

        if let Some(error_code) = value.get("error").and_then(Value::as_str)
            && !error_code.trim().is_empty()
        {
            turn.assistant_error_code = Some(error_code.to_string());
        }

        let Some(content) = value
            .get("message")
            .and_then(|message| message.get("content"))
            .and_then(Value::as_array)
        else {
            return Ok(());
        };

        for block in content {
            let Some(block_type) = block.get("type").and_then(Value::as_str) else {
                continue;
            };
            if block_type != "text" {
                continue;
            }

            if let Some(text) = block.get("text").and_then(Value::as_str)
                && !text.is_empty()
            {
                turn.assistant_text.push_str(text);
            }
        }

        Ok(())
    }

    fn map_result_event(&mut self, value: &Value, events: &mut Vec<TurnEvent>) {
        let Some(mut turn) = self.pending_turns.pop_front() else {
            return;
        };

        let thread_id = self
            .resolve_session_id(value)
            .unwrap_or_else(|_| "unknown".to_string());

        if !turn.started {
            turn.started = true;
            events.push(TurnEvent::Started(TurnStartedEvent::new(
                ProviderName::Anthropic,
                thread_id.clone(),
            )));
        }

        let status = map_result_status(value);
        let answer = if status == TurnStatus::Completed {
            if turn.assistant_text.trim().is_empty() {
                value
                    .get("result")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|text| !text.is_empty())
                    .map(str::to_string)
            } else {
                Some(turn.assistant_text)
            }
        } else {
            None
        };

        let error = if status == TurnStatus::Failed {
            let message = value
                .get("result")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|text| !text.is_empty())
                .unwrap_or("claude turn failed")
                .to_string();

            let code = value
                .get("error")
                .and_then(Value::as_str)
                .map(str::to_string)
                .or(turn.assistant_error_code);
            Some(TurnError::new(message, code))
        } else {
            None
        };

        events.push(TurnEvent::Completed(TurnCompletedEvent::new(
            ProviderName::Anthropic,
            thread_id,
            status,
            answer,
            error,
        )));
    }

    fn resolve_session_id(&mut self, value: &Value) -> Result<String, String> {
        if let Some(session_id) = value.get("session_id").and_then(Value::as_str) {
            let session_id = session_id.to_string();
            self.active_session_id = Some(session_id.clone());
            return Ok(session_id);
        }

        if let Some(session_id) = self.active_session_id.clone() {
            return Ok(session_id);
        }

        Err("missing session_id and no active session is known".to_string())
    }
}

fn map_result_status(value: &Value) -> TurnStatus {
    let stop_reason = value
        .get("stop_reason")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let terminal_reason = value
        .get("terminal_reason")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let is_error = value
        .get("is_error")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if stop_reason == "cancelled" || terminal_reason == "cancelled" {
        TurnStatus::Interrupted
    } else if is_error {
        TurnStatus::Failed
    } else {
        TurnStatus::Completed
    }
}

fn resolve_anthropic_bin() -> Result<&'static str, String> {
    if command_exists(ANTHROPIC_CLI_BIN) {
        Ok(ANTHROPIC_CLI_BIN)
    } else {
        Err(format!(
            "anthropic chat requires '{}' to be installed and available on PATH",
            ANTHROPIC_CLI_BIN
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
    use super::{AnthropicNotificationMapper, process_claude_output, resolve_anthropic_bin};
    use crate::chat::contracts::turn_events::{ProviderName, TurnEvent, TurnStatus};
    use serde_json::Value;
    use std::io::Cursor;
    use std::sync::{Arc, Mutex};

    #[test]
    fn resolve_requires_claude_binary() {
        if super::command_exists("claude") {
            assert_eq!(resolve_anthropic_bin().ok(), Some("claude"));
        } else {
            assert!(resolve_anthropic_bin().is_err());
        }
    }

    #[test]
    fn assistant_event_emits_started_once() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        let started = mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-1","message":{"content":[{"type":"text","text":"Thinking"}]}}"#,
            )
            .expect("assistant event should parse");
        assert_eq!(started.len(), 1);
        assert!(matches!(started[0], TurnEvent::Started(_)));

        let second = mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-1","message":{"content":[{"type":"text","text":" more"}]}}"#,
            )
            .expect("assistant event should parse");
        assert!(second.is_empty());
    }

    #[test]
    fn started_event_matches_contract_fields() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-started","message":{"content":[{"type":"text","text":"thinking"}]}}"#,
            )
            .expect("assistant event should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Started(value) => {
                assert_eq!(value.provider, ProviderName::Anthropic);
                assert_eq!(value.id, "session-started");
                assert_eq!(value.status, TurnStatus::Thinking);
            }
            _ => panic!("expected turn.started"),
        }
    }

    #[test]
    fn completed_event_uses_cached_assistant_text() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-2","message":{"content":[{"type":"text","text":"Hello"},{"type":"text","text":" world"}]}}"#,
            )
            .expect("assistant event should parse");

        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-2","is_error":false,"result":"fallback","stop_reason":"end_turn","terminal_reason":"completed"}"#,
            )
            .expect("result event should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("Hello world"));
                assert!(value.error.is_none());
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn completed_event_falls_back_to_result_text_when_no_assistant_text() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-3","is_error":false,"result":"Result text","stop_reason":"end_turn","terminal_reason":"completed"}"#,
            )
            .expect("result event should parse");

        assert_eq!(events.len(), 2);
        assert!(matches!(events[0], TurnEvent::Started(_)));
        match &events[1] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Completed);
                assert_eq!(value.answer.as_deref(), Some("Result text"));
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn cancelled_result_maps_to_interrupted() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );
        mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-4","message":{"content":[{"type":"text","text":"partial"}]}}"#,
            )
            .expect("assistant event should parse");

        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-4","is_error":false,"result":"partial","stop_reason":"cancelled","terminal_reason":"cancelled"}"#,
            )
            .expect("result event should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Interrupted);
                assert!(value.answer.is_none());
                assert!(value.error.is_none());
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn failed_result_maps_error_fields_and_ignores_unknown_fields() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );
        mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-5","error":"authentication_failed","message":{"content":[{"type":"text","text":"Not logged in"}]}}"#,
            )
            .expect("assistant event should parse");

        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-5","is_error":true,"subtype":"success","result":"Not logged in","stop_reason":"stop_sequence","terminal_reason":"completed","unexpected":{"nested":true}}"#,
            )
            .expect("result event should parse");

        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.status, TurnStatus::Failed);
                assert!(value.answer.is_none());
                let error = value.error.as_ref().expect("error should be present");
                assert_eq!(error.message, "Not logged in");
                assert_eq!(error.code.as_deref(), Some("authentication_failed"));
            }
            _ => panic!("expected turn.completed"),
        }
    }

    #[test]
    fn ignores_non_json_and_unrelated_events() {
        let mut mapper = AnthropicNotificationMapper::new();
        let non_json = mapper
            .map_server_message("Ignore file not found: .claude")
            .expect("non-json line should be ignored");
        assert!(non_json.is_empty());

        let unrelated = mapper
            .map_server_message(r#"{"type":"user","session_id":"session-6","message":{"role":"user","content":[{"type":"text","text":"replay"}]}}"#)
            .expect("unrelated event should parse");
        assert!(unrelated.is_empty());
    }

    #[test]
    fn non_user_client_input_does_not_open_turn() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(r#"{"type":"system","subtype":"init"}"#);

        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-no-turn","is_error":false,"result":"ignored","stop_reason":"end_turn"}"#,
            )
            .expect("result should parse");
        assert!(events.is_empty());
    }

    #[test]
    fn uses_system_init_session_id_when_assistant_omits_it() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper
            .map_server_message(r#"{"type":"system","subtype":"init","session_id":"session-init"}"#)
            .expect("system init should parse");
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        let events = mapper
            .map_server_message(
                r#"{"type":"assistant","message":{"content":[{"type":"text","text":"text"}]}}"#,
            )
            .expect("assistant should parse");
        assert_eq!(events.len(), 1);
        match &events[0] {
            TurnEvent::Started(value) => assert_eq!(value.id, "session-init"),
            _ => panic!("expected turn.started"),
        }
    }

    #[test]
    fn multiple_pending_turns_are_processed_in_order() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"first"}]}}"#,
        );
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"second"}]}}"#,
        );

        mapper
            .map_server_message(
                r#"{"type":"assistant","session_id":"session-queue","message":{"content":[{"type":"text","text":"first answer"}]}}"#,
            )
            .expect("assistant should parse");
        let first = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-queue","is_error":false,"result":"first fallback","stop_reason":"end_turn"}"#,
            )
            .expect("first result should parse");
        let second = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-queue","is_error":false,"result":"second fallback","stop_reason":"end_turn"}"#,
            )
            .expect("second result should parse");

        assert_eq!(first.len(), 1);
        assert_eq!(second.len(), 2);
        match &first[0] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.answer.as_deref(), Some("first answer"))
            }
            _ => panic!("expected completed event"),
        }
        match &second[1] {
            TurnEvent::Completed(value) => {
                assert_eq!(value.answer.as_deref(), Some("second fallback"))
            }
            _ => panic!("expected completed event"),
        }
    }

    #[test]
    fn completed_event_serializes_expected_fields() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );
        let events = mapper
            .map_server_message(
                r#"{"type":"result","session_id":"session-serial","is_error":false,"result":"Done","stop_reason":"end_turn"}"#,
            )
            .expect("result event should parse");

        let completed = match events.get(1) {
            Some(TurnEvent::Completed(value)) => value,
            _ => panic!("expected completed event"),
        };

        let serialized = serde_json::to_value(completed).expect("completed should serialize");
        assert_eq!(serialized.get("type"), None);
        assert_eq!(
            serialized.get("id"),
            Some(&Value::String("session-serial".to_string()))
        );
        assert_eq!(
            serialized.get("status"),
            Some(&Value::String("completed".to_string()))
        );
        assert_eq!(
            serialized.get("answer"),
            Some(&Value::String("Done".to_string()))
        );
    }

    #[test]
    fn process_output_emits_only_contract_events() {
        let mut mapper = AnthropicNotificationMapper::new();
        mapper.observe_client_request(
            r#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}"#,
        );

        let input = concat!(
            "Ignore file not found: .claude\n",
            "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"session-live\"}\n",
            "{\"type\":\"user\",\"session_id\":\"session-live\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]},\"isReplay\":true}\n",
            "{\"type\":\"assistant\",\"session_id\":\"session-live\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}}\n",
            "{\"type\":\"result\",\"session_id\":\"session-live\",\"is_error\":false,\"result\":\"Hello\",\"stop_reason\":\"end_turn\"}\n"
        );
        let mut reader = Cursor::new(input.as_bytes());
        let mut output: Vec<u8> = Vec::new();
        let mapper = Arc::new(Mutex::new(mapper));
        let emitted_final_event = process_claude_output(&mut reader, &mut output, mapper)
            .expect("processing should succeed");

        let output_text = String::from_utf8(output).expect("output should be utf-8");
        let lines: Vec<&str> = output_text.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("\"provider\":\"anthropic\""));
        assert!(lines[0].contains("\"id\":\"session-live\""));
        assert!(lines[0].contains("\"status\":\"thinking\""));
        assert!(lines[1].contains("\"provider\":\"anthropic\""));
        assert!(lines[1].contains("\"id\":\"session-live\""));
        assert!(lines[1].contains("\"status\":\"completed\""));
        assert!(lines[1].contains("\"answer\":\"Hello\""));
        assert!(emitted_final_event);
    }
}
