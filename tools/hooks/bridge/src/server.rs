use crate::slack::Slack;
use axum::{
    Json, Router,
    body::{Body, to_bytes},
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, Method, Request, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
};
use base64::{Engine, engine::general_purpose::STANDARD, engine::general_purpose::URL_SAFE_NO_PAD};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    sync::{Arc, LazyLock, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use subtle::ConstantTimeEq;
use tokio::{net::TcpListener, sync::watch, time::timeout};

#[derive(Clone, Deserialize, Serialize)]
struct Credentials {
    origin: String,
    token: String,
}
struct Pair {
    saved: Option<Credentials>,
    code: Option<String>,
    deadline: Instant,
}
pub struct App {
    slack: Slack,
    home: PathBuf,
    host: String,
    pair: Mutex<Pair>,
    rotated: watch::Sender<u64>,
    closing: watch::Sender<bool>,
}
pub(crate) type ApiResult<T> = Result<T, (StatusCode, &'static str)>;
pub(crate) fn fail(message: &'static str) -> (StatusCode, &'static str) {
    (StatusCode::BAD_REQUEST, message)
}
fn response(status: StatusCode, value: Value) -> Response {
    let mut r = (status, Json(value)).into_response();
    r.headers_mut()
        .insert("cache-control", "no-store".parse().unwrap());
    r.headers_mut()
        .insert("x-content-type-options", "nosniff".parse().unwrap());
    r
}
fn extension(origin: &str) -> bool {
    static ORIGIN: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"\Achrome-extension://[a-p]{32}\z").unwrap());
    ORIGIN.is_match(origin)
}
fn equal(a: &str, b: &str) -> bool {
    bool::from(a.as_bytes().ct_eq(b.as_bytes()))
}
fn random(bytes: usize) -> Result<String, String> {
    let mut raw = vec![0; bytes];
    getrandom::fill(&mut raw).map_err(|_| "System randomness unavailable")?;
    Ok(URL_SAFE_NO_PAD.encode(raw))
}
fn private_dir(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|_| "Cannot create private directory")?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        .map_err(|_| "Cannot secure private directory".into())
}
fn private_json(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path.parent().unwrap();
    private_dir(parent)?;
    let mut file =
        tempfile::NamedTempFile::new_in(parent).map_err(|_| "Cannot create private file")?;
    file.write_all(value.to_string().as_bytes())
        .map_err(|_| "Cannot write private file")?;
    file.as_file()
        .sync_all()
        .map_err(|_| "Cannot save private file")?;
    file.persist(path)
        .map_err(|_| "Cannot replace private file")?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .map_err(|_| "Cannot secure private file".into())
}
fn header<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
    headers
        .get(name)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
}
impl App {
    pub async fn start(
        home: PathBuf,
        port: u16,
        ttl: Duration,
    ) -> Result<(Arc<Self>, TcpListener), String> {
        let slack = Slack::new(&home)?;
        private_dir(&home)?;
        private_dir(&home.join("extension"))?;
        let credentials = home.join("pairing.json");
        let saved = if credentials.exists() {
            let c: Credentials = serde_json::from_slice(
                &fs::read(&credentials).map_err(|_| "Cannot read saved pairing")?,
            )
            .map_err(|_| "Invalid saved pairing")?;
            if !extension(&c.origin) || c.token.is_empty() {
                return Err("Invalid saved pairing".into());
            }
            fs::set_permissions(&credentials, fs::Permissions::from_mode(0o600))
                .map_err(|_| "Cannot secure saved pairing")?;
            Some(c)
        } else {
            None
        };
        let listener = TcpListener::bind(("127.0.0.1", port))
            .await
            .map_err(|_| "Cannot bind loopback bridge")?;
        let host = listener
            .local_addr()
            .map_err(|_| "Cannot read bridge address")?
            .to_string();
        let code = random(24)?;
        let expires = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|_| "Invalid clock")?
            .as_millis()
            + ttl.as_millis();
        private_json(
            &home.join("extension/bridge-pairing.json"),
            &json!({"code":code,"expiresAt":expires}),
        )?;
        let (rotated, _) = watch::channel(0);
        let (closing, _) = watch::channel(false);
        let app = Arc::new(Self {
            slack,
            home,
            host,
            pair: Mutex::new(Pair {
                saved,
                code: Some(code),
                deadline: Instant::now() + ttl,
            }),
            rotated,
            closing,
        });
        let expire = app.clone();
        let mut changed = app.rotated.subscribe();
        let mut shutdown = app.closing.subscribe();
        tokio::spawn(async move {
            tokio::select! {
                _=tokio::time::sleep(ttl)=>{let mut pair=expire.pair.lock().unwrap();expire.clear_code(&mut pair);},
                _=changed.changed()=>{},
                _=shutdown.changed()=>{},
            }
        });
        Ok((app, listener))
    }
    fn clear_code(&self, pair: &mut Pair) {
        let _ = fs::remove_file(self.home.join("extension/bridge-pairing.json"));
        pair.code = None;
    }
    fn check_host(&self, headers: &HeaderMap) -> ApiResult<()> {
        if header(headers, "host") != self.host {
            return Err((StatusCode::FORBIDDEN, "Loopback host required"));
        }
        Ok(())
    }
    fn check_origin(&self, headers: &HeaderMap) -> ApiResult<String> {
        self.check_host(headers)?;
        let origin = header(headers, "x-browser-hooks-origin");
        if headers.contains_key("origin") && header(headers, "origin") != origin {
            return Err((StatusCode::FORBIDDEN, "Origin mismatch"));
        }
        if !extension(origin) {
            return Err((StatusCode::FORBIDDEN, "Extension origin required"));
        }
        Ok(origin.into())
    }
    fn authenticated(&self, headers: &HeaderMap, origin: &str) -> ApiResult<()> {
        let pair = self.pair.lock().unwrap();
        if !pair.saved.as_ref().is_some_and(|saved| {
            saved.origin == origin
                && equal(
                    header(headers, "authorization"),
                    &format!("Bearer {}", saved.token),
                )
        }) {
            return Err((
                StatusCode::FORBIDDEN,
                "Browser pairing expired. Rerun the installer, then reload Browser Hooks.",
            ));
        }
        Ok(())
    }
    fn pair(&self, origin: String, body: &Value) -> ApiResult<Value> {
        let mut pair = self.pair.lock().unwrap();
        let code = body["code"].as_str().unwrap_or("");
        if !pair
            .code
            .as_ref()
            .is_some_and(|expected| Instant::now() <= pair.deadline && equal(code, expected))
        {
            return Err((
                StatusCode::FORBIDDEN,
                "Automatic pairing expired. Rerun the installer, then reload Browser Hooks.",
            ));
        }
        let saved = Credentials {
            origin,
            token: random(32).map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Pairing failed"))?,
        };
        let value = serde_json::to_value(&saved).unwrap();
        private_json(&self.home.join("pairing.json"), &value)
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Cannot save pairing"))?;
        pair.saved = Some(saved);
        self.clear_code(&mut pair);
        self.rotated.send_modify(|version| *version += 1);
        Ok(value)
    }
    fn config(&self) -> Value {
        json!({"hooks":{"slack":self.slack.config()}})
    }
    pub fn address(&self) -> &str {
        &self.host
    }
    pub async fn shutdown(&self) {
        self.closing.send_replace(true);
        {
            let mut pair = self.pair.lock().unwrap();
            self.clear_code(&mut pair);
        }
        self.slack.close().await;
    }
}
async fn api(State(app): State<Arc<App>>, request: Request<Body>) -> Response {
    match dispatch(&app, request).await {
        Ok(value) => response(StatusCode::OK, value),
        Err((status, message)) => response(status, json!({"error":message})),
    }
}
async fn dispatch(app: &Arc<App>, request: Request<Body>) -> ApiResult<Value> {
    let (headers, method, path) = (
        request.headers().clone(),
        request.method().clone(),
        request.uri().to_string(),
    );
    app.check_host(&headers)?;
    if path == "/health" && method == Method::GET {
        return Ok(
            json!({"service":"browser-hooks","implementation":"rust","paired":app.pair.lock().unwrap().saved.is_some(),"hooks":{"slack":{"error":app.slack.error()}}}),
        );
    }
    let origin = app.check_origin(&headers)?;
    let body = if method == Method::POST {
        if header(&headers, "content-type")
            .split(';')
            .next()
            .unwrap_or("")
            .trim()
            != "application/json"
        {
            return Err((StatusCode::UNSUPPORTED_MEDIA_TYPE, "JSON required"));
        }
        let length: usize = header(&headers, "content-length")
            .parse()
            .map_err(|_| (StatusCode::PAYLOAD_TOO_LARGE, "Invalid request size"))?;
        if !(1..=2 * 1024 * 1024).contains(&length) {
            return Err((StatusCode::PAYLOAD_TOO_LARGE, "Invalid request size"));
        }
        let bytes = timeout(
            Duration::from_secs(5),
            to_bytes(request.into_body(), 2 * 1024 * 1024),
        )
        .await
        .map_err(|_| fail("Request timed out"))?
        .map_err(|_| fail("Invalid body"))?;
        if bytes.len() != length {
            return Err(fail("Invalid body length"));
        }
        let body: Value = serde_json::from_slice(&bytes).map_err(|_| fail("Invalid JSON"))?;
        if !body.is_object() {
            return Err(fail("Object required"));
        }
        body
    } else {
        Value::Null
    };
    if path == "/pair" && method == Method::POST {
        return app.pair(origin, &body);
    }
    app.authenticated(&headers, &origin)?;
    if method == Method::GET && path == "/config" {
        return Ok(app.config());
    }
    let path = path
        .strip_prefix("/slack/")
        .ok_or((StatusCode::NOT_FOUND, "Unknown hook"))?;
    app.slack.request(method, &format!("/{path}"), body)
}

async fn events(
    State(app): State<Arc<App>>,
    headers: HeaderMap,
    upgrade: Result<WebSocketUpgrade, axum::extract::ws::rejection::WebSocketUpgradeRejection>,
) -> Response {
    if let Err((status, message)) = app.check_host(&headers) {
        return response(status, json!({"error":message}));
    }
    let paired = app.pair.lock().unwrap().saved.clone();
    let origin = header(&headers, "origin");
    if !extension(origin) || !paired.as_ref().is_some_and(|p| p.origin == origin) {
        return response(
            StatusCode::FORBIDDEN,
            json!({"error":"Paired extension required"}),
        );
    }
    if !STANDARD
        .decode(header(&headers, "sec-websocket-key"))
        .is_ok_and(|key| key.len() == 16)
    {
        return response(
            StatusCode::BAD_REQUEST,
            json!({"error":"Invalid event upgrade"}),
        );
    }
    let Ok(upgrade) = upgrade else {
        return response(
            StatusCode::BAD_REQUEST,
            json!({"error":"Invalid event upgrade"}),
        );
    };
    let saved = paired.unwrap();
    let version = *app.rotated.borrow();
    upgrade
        .max_frame_size(4096)
        .max_message_size(4096)
        .on_upgrade(move |socket| stream(socket, app, saved.token, version))
}
async fn send(socket: &mut WebSocket, value: Value) -> bool {
    timeout(
        Duration::from_secs(5),
        socket.send(Message::Text(value.to_string().into())),
    )
    .await
    .is_ok_and(|v| v.is_ok())
}
async fn stream(mut socket: WebSocket, app: Arc<App>, token: String, version: u64) {
    let Ok(Some(Ok(Message::Text(auth)))) = timeout(Duration::from_secs(5), socket.recv()).await
    else {
        return;
    };
    let Ok(auth) = serde_json::from_str::<Value>(&auth) else {
        return;
    };
    if auth["type"] != "authenticate" || !auth["token"].as_str().is_some_and(|t| equal(t, &token)) {
        return;
    }
    let mut rotated = app.rotated.subscribe();
    let mut closing = app.closing.subscribe();
    if *rotated.borrow() != version || *closing.borrow() {
        return;
    }
    let mut events = app.slack.events();
    if !send(
        &mut socket,
        json!({"type":"settings","hooks":app.config()["hooks"]}),
    )
    .await
    {
        return;
    }
    loop {
        tokio::select! {
            biased;
            _=closing.changed()=>break,
            _=rotated.changed()=>break,
            message=timeout(Duration::from_secs(45),socket.recv())=>{
                match message{
                    Ok(Some(Ok(Message::Text(text))))=>{
                        if serde_json::from_str::<Value>(&text).ok()!=Some(json!({"type":"ping"})){break;}
                        if !send(&mut socket,json!({"type":"pong"})).await{break;}
                    }
                    Ok(Some(Ok(Message::Ping(data))))=>{
                        if !timeout(Duration::from_secs(5),socket.send(Message::Pong(data))).await.is_ok_and(|v|v.is_ok()){break;}
                    }
                    Ok(Some(Ok(Message::Pong(_))))=>{},
                    _=>break,
                }
            }
            event=events.recv()=>{
                let Ok(mut event)=event else{break;};
                event["hook"] = json!("slack");
                if !send(&mut socket,event).await{break;}
            }
        }
    }
}
pub async fn serve(home: PathBuf, port: u16, ttl: Duration) -> Result<(), String> {
    let (app, listener) = App::start(home, port, ttl).await?;
    let router = Router::new()
        .route("/events", get(events))
        .fallback(api)
        .with_state(app.clone());
    println!("READY {}", app.address());
    std::io::stdout()
        .flush()
        .map_err(|_| "Cannot report readiness")?;
    let shutdown = async move {
        let mut terminate =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                .expect("SIGTERM handler");
        tokio::select! {_=terminate.recv()=>{},_=tokio::signal::ctrl_c()=>{}}
        app.shutdown().await;
    };
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown)
        .await
        .map_err(|_| "Bridge transport failed".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn pairing_expires_without_requests_and_preserves_saved_credentials() {
        let temp = tempfile::tempdir().unwrap();
        let home = temp.path().to_path_buf();
        private_dir(&home.join("hooks/slack")).unwrap();
        let saved = json!({"origin":format!("chrome-extension://{}", "a".repeat(32)),"token":"synthetic-saved-token"});
        private_json(&home.join("pairing.json"), &saved).unwrap();
        let bytes = fs::read(home.join("pairing.json")).unwrap();
        private_json(&home.join("hooks/slack/config.json"), &json!({"workspace":home,"commands":{"hook":{"start":["/bin/echo"],"resume":["/bin/echo","{session_id}"]}}})).unwrap();
        let (app, _listener) = App::start(home.clone(), 0, Duration::from_millis(20))
            .await
            .unwrap();
        assert!(home.join("extension/bridge-pairing.json").exists());
        tokio::time::sleep(Duration::from_millis(60)).await;
        assert!(!home.join("extension/bridge-pairing.json").exists());
        assert!(app.pair.lock().unwrap().code.is_none());
        assert_eq!(fs::read(home.join("pairing.json")).unwrap(), bytes);
        assert_eq!(
            fs::metadata(home.join("pairing.json"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        app.shutdown().await;
    }
}
