const APP_SERVER_INIT_TIMEOUT: Duration = Duration::from_secs(2);
const APP_SERVER_ARCHIVE_TIMEOUT: Duration = Duration::from_millis(800);
const APP_SERVER_INIT_REQUEST_ID: i64 = 1;
const APP_SERVER_ARCHIVE_REQUEST_BASE_ID: i64 = 1000;

impl SessionStore {
    fn archive_threads_via_app_server(&self, thread_ids: &[String]) -> HashMap<String, String> {
        let mut failures = HashMap::new();
        if thread_ids.is_empty() || cfg!(test) {
            return failures;
        }

        let mut child = match Command::new("codex")
            .args(["app-server", "--listen", "stdio://"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(child) => child,
            Err(error) => {
                let message = format!("unable to launch codex app-server: {error}");
                for thread_id in thread_ids {
                    failures.insert(thread_id.clone(), message.clone());
                }
                return failures;
            }
        };

        let Some(mut stdin) = child.stdin.take() else {
            let message = "codex app-server did not expose stdin".to_string();
            for thread_id in thread_ids {
                failures.insert(thread_id.clone(), message.clone());
            }
            terminate_child_process(&mut child);
            return failures;
        };
        let Some(stdout) = child.stdout.take() else {
            let message = "codex app-server did not expose stdout".to_string();
            for thread_id in thread_ids {
                failures.insert(thread_id.clone(), message.clone());
            }
            terminate_child_process(&mut child);
            return failures;
        };

        let responses = spawn_json_response_reader(stdout);

        if let Err(error) = send_json_rpc_request(
            &mut stdin,
            APP_SERVER_INIT_REQUEST_ID,
            "initialize",
            serde_json::json!({
                "clientInfo": {
                    "name": "codex-sessions",
                    "version": env!("CARGO_PKG_VERSION"),
                },
                "protocolVersion": "0.1.0",
            }),
        ) {
            let message = format!("failed to initialize codex app-server: {error}");
            for thread_id in thread_ids {
                failures.insert(thread_id.clone(), message.clone());
            }
            terminate_child_process(&mut child);
            return failures;
        }

        match wait_for_response_message(
            &responses,
            APP_SERVER_INIT_REQUEST_ID,
            APP_SERVER_INIT_TIMEOUT,
        ) {
            Ok(Some(error_message)) => {
                let message = format!("codex app-server initialize failed: {error_message}");
                for thread_id in thread_ids {
                    failures.insert(thread_id.clone(), message.clone());
                }
                terminate_child_process(&mut child);
                return failures;
            }
            Ok(None) => {}
            Err(error) => {
                let message = format!("codex app-server initialize timeout: {error}");
                for thread_id in thread_ids {
                    failures.insert(thread_id.clone(), message.clone());
                }
                terminate_child_process(&mut child);
                return failures;
            }
        }

        let mut request_id_to_thread = HashMap::new();
        for (index, thread_id) in thread_ids.iter().enumerate() {
            let request_id = APP_SERVER_ARCHIVE_REQUEST_BASE_ID + index as i64;
            request_id_to_thread.insert(request_id, thread_id.clone());
            if let Err(error) = send_json_rpc_request(
                &mut stdin,
                request_id,
                "thread/archive",
                serde_json::json!({ "threadId": thread_id }),
            ) {
                failures.insert(
                    thread_id.clone(),
                    format!("failed to request thread/archive: {error}"),
                );
                request_id_to_thread.remove(&request_id);
            }
        }

        drop(stdin);

        for (request_id, thread_id) in request_id_to_thread {
            match wait_for_response_message(&responses, request_id, APP_SERVER_ARCHIVE_TIMEOUT) {
                Ok(Some(error_message)) => {
                    failures.insert(
                        thread_id,
                        format!("codex app-server thread/archive failed: {error_message}"),
                    );
                }
                Ok(None) => {}
                Err(error) => {
                    failures.insert(
                        thread_id,
                        format!("timed out waiting for codex app-server archive response: {error}"),
                    );
                }
            }
        }

        terminate_child_process(&mut child);
        failures
    }
}

fn terminate_child_process(child: &mut Child) {
    let _ = child.kill();
    let _ = child.wait();
}

fn spawn_json_response_reader(stdout: ChildStdout) -> Receiver<Value> {
    let (sender, receiver) = mpsc::channel::<Value>();
    thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let Ok(line) = line else {
                break;
            };
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
                if sender.send(parsed).is_err() {
                    break;
                }
            }
        }
    });
    receiver
}

fn send_json_rpc_request(
    stdin: &mut ChildStdin,
    id: i64,
    method: &str,
    params: Value,
) -> Result<()> {
    let payload = serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": params,
    });
    let serialized = serde_json::to_string(&payload)?;
    stdin
        .write_all(serialized.as_bytes())
        .context("failed writing JSON-RPC payload")?;
    stdin.write_all(b"\n").context("failed writing newline")?;
    stdin.flush().context("failed flushing request")
}

fn wait_for_response_message(
    receiver: &Receiver<Value>,
    request_id: i64,
    timeout: Duration,
) -> Result<Option<String>> {
    let started = Instant::now();
    loop {
        let elapsed = started.elapsed();
        if elapsed >= timeout {
            bail!("request id {request_id}");
        }

        let remaining = timeout
            .checked_sub(elapsed)
            .unwrap_or_else(|| Duration::from_millis(0));
        let message = receiver
            .recv_timeout(remaining)
            .with_context(|| format!("request id {request_id}"))?;

        let Some(id) = message.get("id").and_then(Value::as_i64) else {
            continue;
        };
        if id != request_id {
            continue;
        }

        if let Some(error_message) = extract_json_rpc_error(&message) {
            return Ok(Some(error_message));
        }

        return Ok(None);
    }
}

fn extract_json_rpc_error(message: &Value) -> Option<String> {
    let error = message.get("error")?;
    if let Some(text) = error.get("message").and_then(Value::as_str) {
        return Some(text.trim().to_string());
    }
    Some(error.to_string())
}
