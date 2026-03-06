use anyhow::{anyhow, Context, Result};
use futures::future::BoxFuture;
use regex::Regex;
use reqwest::Client as HttpClient;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use teloxide::prelude::*;
use teloxide::types::{ChatAction, InputFile, KeyboardButton, KeyboardMarkup, Message};
use tokio::fs;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::sync::{oneshot, Mutex};
use tokio::task::JoinHandle;
use tokio::time::timeout;
use tracing::{error, info};

const HELP_TEXT: &str = "Agent Gateway, your remote AI tool\n\nTip: Voice notes work!";
const TELEGRAM_MESSAGE_LIMIT: usize = 4096;
const TELEGRAM_MESSAGE_CHUNK: usize = 3900;
const TURN_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const DEFAULT_THREADS_LIMIT: usize = 25;
const APPROVAL_REQUEST_TIMEOUT: Duration = Duration::from_secs(10 * 60);
const APPROVAL_PROMPT_MAX: usize = 3500;
const THREAD_SOURCE_KINDS: [&str; 3] = ["vscode", "cli", "appServer"];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ActionName {
    New,
    Resume,
    Delete,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ListedMode {
    Resume,
    Delete,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ApprovalPolicy {
    Never,
    OnRequest,
    OnFailure,
    Untrusted,
}

impl ApprovalPolicy {
    fn as_str(self) -> &'static str {
        match self {
            ApprovalPolicy::Never => "never",
            ApprovalPolicy::OnRequest => "on-request",
            ApprovalPolicy::OnFailure => "on-failure",
            ApprovalPolicy::Untrusted => "untrusted",
        }
    }

    fn parse(value: Option<&str>) -> Option<Self> {
        match value?.trim() {
            "never" => Some(Self::Never),
            "on-request" => Some(Self::OnRequest),
            "on-failure" => Some(Self::OnFailure),
            "untrusted" => Some(Self::Untrusted),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum SandboxMode {
    ReadOnly,
    WorkspaceWrite,
    DangerFullAccess,
}

impl SandboxMode {
    fn as_str(self) -> &'static str {
        match self {
            SandboxMode::ReadOnly => "read-only",
            SandboxMode::WorkspaceWrite => "workspace-write",
            SandboxMode::DangerFullAccess => "danger-full-access",
        }
    }

    fn parse(value: Option<&str>) -> Option<Self> {
        match value?.trim() {
            "read-only" => Some(Self::ReadOnly),
            "workspace-write" => Some(Self::WorkspaceWrite),
            "danger-full-access" => Some(Self::DangerFullAccess),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ApprovalDecision {
    Accept,
    AcceptForSession,
    Decline,
    Cancel,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ApprovalMethod {
    CommandExecution,
    FileChange,
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
struct ApprovalRequest {
    method: ApprovalMethod,
    thread_id: String,
    turn_id: String,
    item_id: String,
    approval_id: Option<String>,
    reason: Option<String>,
    command: Option<String>,
    cwd: Option<String>,
}

#[derive(Clone, Debug)]
struct AgentTextSnapshot {
    item_id: String,
    text: String,
}

type ApprovalHandler =
    Arc<dyn Fn(ApprovalRequest) -> BoxFuture<'static, ApprovalDecision> + Send + Sync>;
type SnapshotHandler = Arc<dyn Fn(AgentTextSnapshot) + Send + Sync>;

#[derive(Clone, Default)]
struct TurnRuntimeOptions {
    approval_handler: Option<ApprovalHandler>,
    on_agent_text_snapshot: Option<SnapshotHandler>,
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
struct ThreadSummary {
    id: String,
    cwd: String,
    preview: String,
    created_at: i64,
    updated_at: i64,
    path: Option<String>,
    source: String,
}

#[derive(Clone, Debug)]
struct ListedThread {
    thread: ThreadSummary,
    title: String,
}

#[derive(Clone, Debug)]
struct ListedFolderChoice {
    cwd: String,
    label: String,
}

#[derive(Clone, Debug)]
struct ConversationOptions {
    cwd: String,
    model: Option<String>,
    approval_policy: Option<ApprovalPolicy>,
    sandbox_mode: Option<SandboxMode>,
    network_access_enabled: Option<bool>,
    skip_git_repo_check: Option<bool>,
}

#[derive(Debug)]
struct TurnCompletion {
    response: String,
}

enum TimedTurnResult {
    Completed {
        response: String,
    },
    TimedOut {
        completion: JoinHandle<Result<TurnCompletion>>,
    },
}

enum TimedCreateTurnResult {
    Completed {
        conversation_id: String,
        response: String,
    },
    TimedOut {
        conversation_id: String,
        completion: JoinHandle<Result<TurnCompletion>>,
    },
}

#[derive(Clone)]
struct Config {
    telegram_bot_token: String,
    allowed_chat_ids: Option<HashSet<String>>,
    codex_home: PathBuf,
    codex_working_directory: PathBuf,
    codex_model: Option<String>,
    codex_approval_policy: Option<ApprovalPolicy>,
    codex_sandbox_mode: Option<SandboxMode>,
    codex_network_access_enabled: Option<bool>,
    project_root: PathBuf,
    start_image_path: PathBuf,
}

impl Config {
    fn from_env() -> Result<Self> {
        let telegram_bot_token = std::env::var("TELEGRAM_BOT_TOKEN")
            .context("Missing required env var: TELEGRAM_BOT_TOKEN")?;

        let project_root =
            std::env::current_dir().context("Failed to resolve current directory")?;
        let start_image_path = project_root.join("assets/start-logo.png");
        if !start_image_path.exists() {
            return Err(anyhow!(
                "Missing Telegram start image asset at: {}",
                start_image_path.display()
            ));
        }

        let home = dirs_home()?;
        let codex_home = std::env::var("CODEX_HOME")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .map(|v| expand_home_path(v.trim(), &home))
            .unwrap_or_else(|| home.join(".codex"));

        let codex_working_directory = std::env::var("CODEX_WORKING_DIRECTORY")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .map(|v| resolve_user_path(v.trim(), &project_root, &home))
            .unwrap_or(home);

        let allowed_chat_ids =
            parse_allowed_chat_ids(std::env::var("TELEGRAM_ALLOWED_CHAT_IDS").ok());

        let codex_model = std::env::var("CODEX_MODEL")
            .ok()
            .filter(|v| !v.trim().is_empty());
        let codex_approval_policy =
            ApprovalPolicy::parse(std::env::var("CODEX_APPROVAL_POLICY").ok().as_deref());
        let codex_sandbox_mode =
            SandboxMode::parse(std::env::var("CODEX_SANDBOX_MODE").ok().as_deref());
        let codex_network_access_enabled = parse_bool(
            std::env::var("CODEX_NETWORK_ACCESS_ENABLED")
                .ok()
                .as_deref(),
        );

        Ok(Self {
            telegram_bot_token,
            allowed_chat_ids,
            codex_home,
            codex_working_directory,
            codex_model,
            codex_approval_policy,
            codex_sandbox_mode,
            codex_network_access_enabled,
            project_root,
            start_image_path,
        })
    }

    fn conversation_options(&self) -> ConversationOptions {
        ConversationOptions {
            cwd: self.codex_working_directory.to_string_lossy().to_string(),
            model: self.codex_model.clone(),
            approval_policy: self.codex_approval_policy,
            sandbox_mode: self.codex_sandbox_mode,
            network_access_enabled: self.codex_network_access_enabled,
            skip_git_repo_check: Some(true),
        }
    }
}

#[derive(Clone)]
struct BindingStore {
    file_path: PathBuf,
    lock: Arc<Mutex<()>>,
}

impl BindingStore {
    fn new(file_path: PathBuf) -> Self {
        Self {
            file_path,
            lock: Arc::new(Mutex::new(())),
        }
    }

    async fn get(&self, chat_id: &str) -> Result<Option<String>> {
        let _guard = self.lock.lock().await;
        let bindings = self.read_all().await?;
        Ok(bindings.get(chat_id).cloned())
    }

    async fn set(&self, chat_id: &str, thread_id: &str) -> Result<()> {
        let _guard = self.lock.lock().await;
        let mut bindings = self.read_all().await?;
        bindings.insert(chat_id.to_string(), thread_id.to_string());
        self.write_all(&bindings).await
    }

    async fn remove(&self, chat_id: &str) -> Result<bool> {
        let _guard = self.lock.lock().await;
        let mut bindings = self.read_all().await?;
        let existed = bindings.remove(chat_id).is_some();
        if existed {
            self.write_all(&bindings).await?;
        }
        Ok(existed)
    }

    async fn ensure_file(&self) -> Result<()> {
        if let Some(parent) = self.file_path.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("Failed to create directory: {}", parent.display()))?;
        }

        if fs::metadata(&self.file_path).await.is_err() {
            fs::write(&self.file_path, b"{}\n").await.with_context(|| {
                format!(
                    "Failed to initialize bindings file: {}",
                    self.file_path.display()
                )
            })?;
        }
        Ok(())
    }

    async fn read_all(&self) -> Result<HashMap<String, String>> {
        self.ensure_file().await?;
        let raw = fs::read_to_string(&self.file_path).await.with_context(|| {
            format!("Failed to read bindings file: {}", self.file_path.display())
        })?;

        let parsed: Value = serde_json::from_str(&raw).unwrap_or(Value::Object(Default::default()));
        let Some(obj) = parsed.as_object() else {
            return Ok(HashMap::new());
        };

        let mut out = HashMap::new();
        for (key, value) in obj {
            if let Some(v) = value.as_str() {
                out.insert(key.clone(), v.to_string());
            }
        }
        Ok(out)
    }

    async fn write_all(&self, bindings: &HashMap<String, String>) -> Result<()> {
        self.ensure_file().await?;
        let tmp = self.file_path.with_extension(format!(
            "{}.{}.tmp",
            std::process::id(),
            chrono_like_timestamp()
        ));
        let encoded = serde_json::to_string_pretty(bindings)?;
        fs::write(&tmp, format!("{encoded}\n"))
            .await
            .with_context(|| format!("Failed to write temp bindings file: {}", tmp.display()))?;
        fs::rename(&tmp, &self.file_path).await.with_context(|| {
            format!(
                "Failed to replace bindings file: {}",
                self.file_path.display()
            )
        })?;
        Ok(())
    }
}

#[derive(Clone)]
struct PendingApproval {
    sender: Arc<Mutex<Option<oneshot::Sender<ApprovalDecision>>>>,
    timeout_task: Arc<Mutex<Option<JoinHandle<()>>>>,
}

#[derive(Clone)]
struct ApprovalService {
    pending: Arc<Mutex<HashMap<String, PendingApproval>>>,
    timeout: Duration,
    default_decision: ApprovalDecision,
}

impl ApprovalService {
    fn new(timeout: Duration, default_decision: ApprovalDecision) -> Self {
        Self {
            pending: Arc::new(Mutex::new(HashMap::new())),
            timeout,
            default_decision,
        }
    }

    async fn request_approval_from_telegram(
        &self,
        bot: &Bot,
        message: &Message,
        chat_id: &str,
        request: ApprovalRequest,
    ) -> ApprovalDecision {
        let prompt = limit_telegram_text(&format_approval_prompt(&request), APPROVAL_PROMPT_MAX);

        self.clear_pending_with_default(chat_id).await;

        let (tx, rx) = oneshot::channel::<ApprovalDecision>();
        let sender = Arc::new(Mutex::new(Some(tx)));
        let timeout_task = {
            let pending = Arc::clone(&self.pending);
            let sender = Arc::clone(&sender);
            let chat_key = chat_id.to_string();
            let timeout = self.timeout;
            let default_decision = self.default_decision;
            tokio::spawn(async move {
                tokio::time::sleep(timeout).await;
                let _ = pending.lock().await.remove(&chat_key);
                if let Some(tx) = sender.lock().await.take() {
                    let _ = tx.send(default_decision);
                }
            })
        };

        self.pending.lock().await.insert(
            chat_id.to_string(),
            PendingApproval {
                sender,
                timeout_task: Arc::new(Mutex::new(Some(timeout_task))),
            },
        );

        let send_result = send_text(
            bot,
            message.chat.id,
            &prompt,
            Some(approval_keyboard()),
            false,
        )
        .await;

        if send_result.is_err() {
            self.clear_pending(chat_id).await;
            return self.default_decision;
        }

        match rx.await {
            Ok(decision) => decision,
            Err(_) => self.default_decision,
        }
    }

    async fn resolve_approval_from_text(
        &self,
        bot: &Bot,
        message: &Message,
        chat_id: &str,
        text: &str,
    ) -> Result<bool> {
        let decision = parse_approval_decision_text(text);
        if decision.is_none() {
            return Ok(false);
        }

        let pending = {
            let mut guard = self.pending.lock().await;
            guard.remove(chat_id)
        };

        let Some(pending) = pending else {
            return Ok(false);
        };

        if let Some(handle) = pending.timeout_task.lock().await.take() {
            handle.abort();
        }

        if let Some(tx) = pending.sender.lock().await.take() {
            let _ = tx.send(decision.expect("checked is_some"));
        }

        send_text(
            bot,
            message.chat.id,
            "Approval sent",
            Some(quick_actions_keyboard()),
            false,
        )
        .await?;

        Ok(true)
    }

    async fn clear_pending(&self, chat_id: &str) {
        if let Some(existing) = self.pending.lock().await.remove(chat_id) {
            if let Some(handle) = existing.timeout_task.lock().await.take() {
                handle.abort();
            }
            let _ = existing.sender.lock().await.take();
        }
    }

    async fn clear_pending_with_default(&self, chat_id: &str) {
        if let Some(existing) = self.pending.lock().await.remove(chat_id) {
            if let Some(handle) = existing.timeout_task.lock().await.take() {
                handle.abort();
            }
            if let Some(tx) = existing.sender.lock().await.take() {
                let _ = tx.send(self.default_decision);
            }
        }
    }
}

#[derive(Clone)]
struct GatewayState {
    pending_new_session_chats: Arc<Mutex<HashSet<String>>>,
    pending_new_session_cwds: Arc<Mutex<HashMap<String, String>>>,
    last_listed_sessions: Arc<Mutex<HashMap<String, Vec<ListedThread>>>>,
    last_listed_modes: Arc<Mutex<HashMap<String, ListedMode>>>,
    last_listed_folder_choices: Arc<Mutex<HashMap<String, Vec<ListedFolderChoice>>>>,
    chat_locks: Arc<Mutex<HashMap<String, Arc<Mutex<()>>>>>,
}

impl GatewayState {
    fn new() -> Self {
        Self {
            pending_new_session_chats: Arc::new(Mutex::new(HashSet::new())),
            pending_new_session_cwds: Arc::new(Mutex::new(HashMap::new())),
            last_listed_sessions: Arc::new(Mutex::new(HashMap::new())),
            last_listed_modes: Arc::new(Mutex::new(HashMap::new())),
            last_listed_folder_choices: Arc::new(Mutex::new(HashMap::new())),
            chat_locks: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

#[derive(Clone)]
struct Gateway {
    http: HttpClient,
    config: Config,
    store: BindingStore,
    approvals: ApprovalService,
    state: GatewayState,
}

impl Gateway {
    fn new(bot: Bot, config: Config) -> Self {
        let _ = bot;
        Self {
            http: HttpClient::new(),
            config,
            store: BindingStore::new(PathBuf::from("runtime/bindings.json")),
            approvals: ApprovalService::new(APPROVAL_REQUEST_TIMEOUT, ApprovalDecision::Decline),
            state: GatewayState::new(),
        }
    }

    async fn handle_message(self: Arc<Self>, bot: Bot, message: Message) -> Result<()> {
        let chat_id = message.chat.id.0.to_string();
        if !self.is_chat_allowed(&chat_id) {
            return Ok(());
        }

        if let Some(text) = message.text() {
            self.handle_text_message(&bot, &message, &chat_id, text)
                .await?;
            return Ok(());
        }

        if message.voice().is_some() {
            self.handle_voice_message(&bot, &message, &chat_id).await?;
        }

        Ok(())
    }

    fn is_chat_allowed(&self, chat_id: &str) -> bool {
        match &self.config.allowed_chat_ids {
            Some(allowed) => allowed.contains(chat_id),
            None => true,
        }
    }

    async fn handle_text_message(
        &self,
        bot: &Bot,
        message: &Message,
        chat_id: &str,
        input: &str,
    ) -> Result<()> {
        let text = input.trim();
        if text.is_empty() {
            return Ok(());
        }

        if self
            .approvals
            .resolve_approval_from_text(bot, message, chat_id, text)
            .await?
        {
            return Ok(());
        }

        if self
            .try_resume_pick_by_text(bot, message, chat_id, text)
            .await?
        {
            return Ok(());
        }

        if self
            .try_new_folder_pick_by_text(bot, message, chat_id, text)
            .await?
        {
            return Ok(());
        }

        if let Some(action) = map_action_from_text(text) {
            match action {
                ActionOrUtility::Start => {
                    self.send_start_response(bot, message).await?;
                }
                ActionOrUtility::Help => {
                    self.send_help_response(bot, message.chat.id).await?;
                }
                ActionOrUtility::Action(action_name) => {
                    let result = self
                        .with_chat_lock(chat_id, async {
                            self.execute_action(bot, message.chat.id, chat_id, action_name)
                                .await
                        })
                        .await;

                    if let Err(error) = result {
                        send_text(
                            bot,
                            message.chat.id,
                            &format_failure("Action failed.", &error.to_string()),
                            None,
                            false,
                        )
                        .await?;
                    }
                }
            }
            return Ok(());
        }

        if text.starts_with('/') {
            return Ok(());
        }

        self.with_chat_lock(chat_id, async {
            send_chat_action(bot, message.chat.id).await?;
            self.run_prompt_through_codex(bot, message, chat_id, text)
                .await
        })
        .await
    }

    async fn handle_voice_message(
        &self,
        bot: &Bot,
        message: &Message,
        chat_id: &str,
    ) -> Result<()> {
        let result = self
            .with_chat_lock(chat_id, async {
                send_chat_action(bot, message.chat.id).await?;
                let transcript = self.transcribe_voice_message(bot, message).await?;
                self.run_prompt_through_codex(bot, message, chat_id, &transcript)
                    .await
            })
            .await;

        if let Err(error) = result {
            send_text(
                bot,
                message.chat.id,
                &format_failure("Voice transcription failed.", &error.to_string()),
                None,
                false,
            )
            .await?;
        }

        Ok(())
    }

    async fn send_help_response(&self, bot: &Bot, chat_id: ChatId) -> Result<()> {
        send_text(
            bot,
            chat_id,
            HELP_TEXT,
            Some(quick_actions_keyboard()),
            false,
        )
        .await
    }

    async fn send_start_response(&self, bot: &Bot, message: &Message) -> Result<()> {
        bot.send_photo(
            message.chat.id,
            InputFile::file(self.config.start_image_path.clone()),
        )
        .await?;
        self.send_help_response(bot, message.chat.id).await
    }

    async fn with_chat_lock<T, F>(&self, chat_id: &str, fut: F) -> Result<T>
    where
        F: std::future::Future<Output = Result<T>>,
    {
        let chat_lock = {
            let mut locks = self.state.chat_locks.lock().await;
            locks
                .entry(chat_id.to_string())
                .or_insert_with(|| Arc::new(Mutex::new(())))
                .clone()
        };

        let _guard = chat_lock.lock().await;
        fut.await
    }

    async fn execute_action(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        action: ActionName,
    ) -> Result<()> {
        match action {
            ActionName::New => self.reply_folder_choices(bot, chat_id, chat_key).await,
            ActionName::Resume => {
                self.reply_threads_list(
                    bot,
                    chat_id,
                    chat_key,
                    DEFAULT_THREADS_LIMIT,
                    ListedMode::Resume,
                )
                .await
            }
            ActionName::Delete => {
                self.reply_threads_list(
                    bot,
                    chat_id,
                    chat_key,
                    DEFAULT_THREADS_LIMIT,
                    ListedMode::Delete,
                )
                .await
            }
        }
    }

    async fn try_resume_pick_by_text(
        &self,
        bot: &Bot,
        message: &Message,
        chat_key: &str,
        text: &str,
    ) -> Result<bool> {
        let listed = {
            let guard = self.state.last_listed_sessions.lock().await;
            guard.get(chat_key).cloned()
        };

        let Some(listed) = listed else {
            return Ok(false);
        };

        if listed.is_empty() {
            return Ok(false);
        }

        let labels = build_thread_selection_labels(
            &listed
                .iter()
                .map(|session| session.title.clone())
                .collect::<Vec<_>>(),
        );

        let Some(index) = parse_selection_from_options(text, &labels) else {
            return Ok(false);
        };

        let mode = {
            let guard = self.state.last_listed_modes.lock().await;
            guard.get(chat_key).copied().unwrap_or(ListedMode::Resume)
        };

        match mode {
            ListedMode::Resume => {
                self.pick_thread_by_index(bot, message.chat.id, chat_key, index)
                    .await?
            }
            ListedMode::Delete => {
                self.delete_thread_by_index(bot, message.chat.id, chat_key, index)
                    .await?
            }
        }

        Ok(true)
    }

    async fn try_new_folder_pick_by_text(
        &self,
        bot: &Bot,
        message: &Message,
        chat_key: &str,
        text: &str,
    ) -> Result<bool> {
        let listed = {
            let guard = self.state.last_listed_folder_choices.lock().await;
            guard.get(chat_key).cloned()
        };

        let Some(listed) = listed else {
            return Ok(false);
        };

        if listed.is_empty() {
            return Ok(false);
        }

        let labels = build_folder_selection_labels(
            &listed
                .iter()
                .map(|choice| choice.label.clone())
                .collect::<Vec<_>>(),
        );

        let Some(index) = parse_selection_from_options(text, &labels) else {
            return Ok(false);
        };

        self.pick_folder_choice_by_index(bot, message.chat.id, chat_key, index)
            .await?;

        Ok(true)
    }

    async fn pick_thread_by_index(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        index: usize,
    ) -> Result<()> {
        let selected = {
            let listed = self.state.last_listed_sessions.lock().await;
            listed
                .get(chat_key)
                .and_then(|items| items.get(index.saturating_sub(1)))
                .cloned()
        };

        let Some(selected) = selected else {
            return Ok(());
        };

        self.state
            .pending_new_session_chats
            .lock()
            .await
            .remove(chat_key);
        self.state
            .pending_new_session_cwds
            .lock()
            .await
            .remove(chat_key);
        self.state
            .last_listed_sessions
            .lock()
            .await
            .remove(chat_key);
        self.state.last_listed_modes.lock().await.remove(chat_key);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .remove(chat_key);

        self.bind_chat_to_thread(chat_key, &selected.thread.id)
            .await?;

        send_text(
            bot,
            chat_id,
            &format_action_title("Resumed", &selected.title),
            Some(quick_actions_keyboard()),
            false,
        )
        .await?;

        if let Some(latest) =
            load_latest_assistant_message_by_thread_id(&selected.thread.id, &self.config.codex_home)
                .await?
        {
            send_text_chunks(bot, chat_id, &format!("Latest message:\n\n{latest}")).await?;
        }

        Ok(())
    }

    async fn delete_thread_by_index(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        index: usize,
    ) -> Result<()> {
        let selected = {
            let listed = self.state.last_listed_sessions.lock().await;
            listed
                .get(chat_key)
                .and_then(|items| items.get(index.saturating_sub(1)))
                .cloned()
        };

        let Some(selected) = selected else {
            return Ok(());
        };

        let deleted =
            delete_session_by_thread_id(&selected.thread.id, &self.config.codex_home).await?;
        let bound_id = self.store.get(chat_key).await?;

        self.state
            .last_listed_sessions
            .lock()
            .await
            .remove(chat_key);
        self.state.last_listed_modes.lock().await.remove(chat_key);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .remove(chat_key);

        if bound_id.as_deref() == Some(selected.thread.id.as_str()) {
            self.state
                .pending_new_session_chats
                .lock()
                .await
                .insert(chat_key.to_string());
            self.state.pending_new_session_cwds.lock().await.insert(
                chat_key.to_string(),
                if selected.thread.cwd.trim().is_empty() {
                    self.config.conversation_options().cwd
                } else {
                    selected.thread.cwd.clone()
                },
            );
            self.store.remove(chat_key).await?;
        }

        if deleted {
            if bound_id.as_deref() == Some(selected.thread.id.as_str()) {
                send_text(
                    bot,
                    chat_id,
                    &format!(
                        "{}\n\nSend a message to start a new thread.",
                        format_action_title("Deleted", &selected.title)
                    ),
                    Some(quick_actions_keyboard()),
                    false,
                )
                .await?;
            } else {
                send_text(
                    bot,
                    chat_id,
                    &format_action_title("Deleted", &selected.title),
                    Some(quick_actions_keyboard()),
                    false,
                )
                .await?;
            }
        }

        Ok(())
    }

    async fn pick_folder_choice_by_index(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        index: usize,
    ) -> Result<()> {
        let selected = {
            let listed = self.state.last_listed_folder_choices.lock().await;
            listed
                .get(chat_key)
                .and_then(|items| items.get(index.saturating_sub(1)))
                .cloned()
        };

        let Some(selected) = selected else {
            return Ok(());
        };

        self.clear_chat_binding_state(chat_key).await?;
        self.state
            .pending_new_session_chats
            .lock()
            .await
            .insert(chat_key.to_string());
        self.state
            .pending_new_session_cwds
            .lock()
            .await
            .insert(chat_key.to_string(), selected.cwd.clone());
        self.state
            .last_listed_sessions
            .lock()
            .await
            .remove(chat_key);
        self.state.last_listed_modes.lock().await.remove(chat_key);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .remove(chat_key);

        send_text(
            bot,
            chat_id,
            &format!("New: Send message\nFolder: {}", selected.label),
            Some(quick_actions_keyboard()),
            false,
        )
        .await
    }

    async fn clear_chat_binding_state(&self, chat_key: &str) -> Result<()> {
        self.state
            .last_listed_sessions
            .lock()
            .await
            .remove(chat_key);
        self.state.last_listed_modes.lock().await.remove(chat_key);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .remove(chat_key);
        self.state
            .pending_new_session_cwds
            .lock()
            .await
            .remove(chat_key);
        self.store.remove(chat_key).await?;
        Ok(())
    }

    async fn reply_threads_list(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        limit: usize,
        mode: ListedMode,
    ) -> Result<()> {
        let threads = list_threads(limit).await?;
        if threads.is_empty() {
            send_text(bot, chat_id, "No Codex sessions found.", None, false).await?;
            return Ok(());
        }

        let desktop_titles = load_desktop_thread_titles(&self.config.codex_home).await?;
        let sessions: Vec<ListedThread> = threads
            .into_iter()
            .map(|thread| {
                let title = resolve_session_title(&thread, &desktop_titles);
                ListedThread { thread, title }
            })
            .collect();

        self.state
            .last_listed_sessions
            .lock()
            .await
            .insert(chat_key.to_string(), sessions.clone());
        self.state
            .last_listed_modes
            .lock()
            .await
            .insert(chat_key.to_string(), mode);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .remove(chat_key);

        let prompt = match mode {
            ListedMode::Delete => "Choose thread to delete",
            ListedMode::Resume => "Choose thread",
        };

        let keyboard = thread_selection_keyboard(
            &sessions
                .iter()
                .map(|session| session.title.clone())
                .collect::<Vec<_>>(),
            false,
        );

        send_text(bot, chat_id, prompt, Some(keyboard), false).await
    }

    async fn reply_folder_choices(&self, bot: &Bot, chat_id: ChatId, chat_key: &str) -> Result<()> {
        self.state
            .pending_new_session_chats
            .lock()
            .await
            .remove(chat_key);
        self.state
            .pending_new_session_cwds
            .lock()
            .await
            .remove(chat_key);

        let threads = list_threads(DEFAULT_THREADS_LIMIT.max(80)).await?;
        let default_cwd = self.config.conversation_options().cwd;
        let folder_choices = list_folder_choices(&threads, &default_cwd)
            .into_iter()
            .take(12)
            .collect::<Vec<_>>();

        self.state
            .last_listed_sessions
            .lock()
            .await
            .remove(chat_key);
        self.state.last_listed_modes.lock().await.remove(chat_key);
        self.state
            .last_listed_folder_choices
            .lock()
            .await
            .insert(chat_key.to_string(), folder_choices.clone());

        let keyboard = new_folder_selection_keyboard(
            &folder_choices
                .iter()
                .map(|choice| choice.label.clone())
                .collect::<Vec<_>>(),
        );

        send_text(bot, chat_id, "Choose folder", Some(keyboard), false).await
    }

    async fn run_prompt_through_codex(
        &self,
        bot: &Bot,
        message: &Message,
        chat_key: &str,
        text: &str,
    ) -> Result<()> {
        let draft = DraftSession::new(
            self.http.clone(),
            self.config.telegram_bot_token.clone(),
            message.chat.id,
            true,
            Duration::from_millis(500),
        );

        let thread_id = self.store.get(chat_key).await?;
        let approval_service = self.approvals.clone();
        let bot_clone = bot.clone();
        let message_clone = message.clone();
        let chat_key_owned = chat_key.to_string();
        let draft_for_handler = draft.clone();

        let runtime_options = TurnRuntimeOptions {
            approval_handler: Some(Arc::new(move |request| {
                let approval_service = approval_service.clone();
                let bot = bot_clone.clone();
                let message = message_clone.clone();
                let chat_id = chat_key_owned.clone();
                Box::pin(async move {
                    approval_service
                        .request_approval_from_telegram(&bot, &message, &chat_id, request)
                        .await
                })
            })),
            on_agent_text_snapshot: Some(Arc::new(move |snapshot| {
                let draft_for_handler = draft_for_handler.clone();
                tokio::spawn(async move {
                    let _ = draft_for_handler.push_snapshot(snapshot).await;
                });
            })),
        };

        let finalize_turn = |turn: TimedTurnResult,
                             delayed_intro: &'static str,
                             bot: Bot,
                             chat_id: ChatId,
                             draft: DraftSession| async move {
            draft.stop(true).await;
            reply_from_timed_turn(bot, chat_id, turn, delayed_intro, draft).await
        };

        let turn_result: Result<()> = async {
            if thread_id.is_none() {
                let pending = self
                    .state
                    .pending_new_session_chats
                    .lock()
                    .await
                    .contains(chat_key);
                if pending {
                    let mut options = self.config.conversation_options();
                    if let Some(selected_cwd) = self
                        .state
                        .pending_new_session_cwds
                        .lock()
                        .await
                        .get(chat_key)
                        .cloned()
                    {
                        options.cwd = selected_cwd;
                    }

                    let initialized = create_and_send_first_message_with_timeout_continuation(
                        options,
                        text.to_string(),
                        runtime_options.clone(),
                    )
                    .await?;

                    let conversation_id = match &initialized {
                        TimedCreateTurnResult::Completed {
                            conversation_id, ..
                        } => conversation_id.clone(),
                        TimedCreateTurnResult::TimedOut {
                            conversation_id, ..
                        } => conversation_id.clone(),
                    };

                    self.bind_chat_to_thread(chat_key, &conversation_id).await?;
                    self.state
                        .pending_new_session_chats
                        .lock()
                        .await
                        .remove(chat_key);
                    self.state
                        .pending_new_session_cwds
                        .lock()
                        .await
                        .remove(chat_key);

                    match initialized {
                        TimedCreateTurnResult::Completed { response, .. } => {
                            finalize_turn(
                                TimedTurnResult::Completed { response },
                                "Delayed:",
                                bot.clone(),
                                message.chat.id,
                                draft.clone(),
                            )
                            .await?;
                        }
                        TimedCreateTurnResult::TimedOut { completion, .. } => {
                            finalize_turn(
                                TimedTurnResult::TimedOut { completion },
                                "Delayed:",
                                bot.clone(),
                                message.chat.id,
                                draft.clone(),
                            )
                            .await?;
                        }
                    }

                    return Ok(());
                }

                draft.stop(false).await;
                self.send_help_response(bot, message.chat.id).await?;
                return Ok(());
            }

            let bound_thread = thread_id.expect("checked is_some");

            match send_message_with_timeout_continuation(
                bound_thread.clone(),
                text.to_string(),
                runtime_options.clone(),
            )
            .await
            {
                Ok(turn) => {
                    finalize_turn(
                        turn,
                        "Delayed:",
                        bot.clone(),
                        message.chat.id,
                        draft.clone(),
                    )
                    .await?;
                    return Ok(());
                }
                Err(error) => {
                    if !is_no_rollout_found_error(&error) {
                        return Err(error);
                    }
                }
            }

            match send_message_without_resume_with_timeout_continuation(
                bound_thread,
                text.to_string(),
                runtime_options.clone(),
            )
            .await
            {
                Ok(turn) => {
                    finalize_turn(
                        turn,
                        "Delayed:",
                        bot.clone(),
                        message.chat.id,
                        draft.clone(),
                    )
                    .await?;
                    Ok(())
                }
                Err(_) => {
                    draft.stop(true).await;
                    self.recover_from_unavailable_thread(
                        bot,
                        message.chat.id,
                        chat_key,
                        text,
                        runtime_options,
                        draft.clone(),
                    )
                    .await
                }
            }
        }
        .await;

        if let Err(error) = turn_result {
            draft.stop(false).await;
            send_text(
                bot,
                message.chat.id,
                &format_failure("Codex error.", &error.to_string()),
                None,
                false,
            )
            .await?;
        }

        Ok(())
    }

    async fn recover_from_unavailable_thread(
        &self,
        bot: &Bot,
        chat_id: ChatId,
        chat_key: &str,
        text: &str,
        runtime_options: TurnRuntimeOptions,
        draft: DraftSession,
    ) -> Result<()> {
        let options = self.config.conversation_options();
        let initialized = create_and_send_first_message_with_timeout_continuation(
            options,
            text.to_string(),
            runtime_options,
        )
        .await?;

        let conversation_id = match &initialized {
            TimedCreateTurnResult::Completed {
                conversation_id, ..
            } => conversation_id.clone(),
            TimedCreateTurnResult::TimedOut {
                conversation_id, ..
            } => conversation_id.clone(),
        };

        self.bind_chat_to_thread(chat_key, &conversation_id).await?;

        let title = self.resolve_thread_title(&conversation_id).await?;

        match initialized {
            TimedCreateTurnResult::Completed { response, .. } => {
                reply_completed_output(bot, chat_id, &response, &draft).await?;
            }
            TimedCreateTurnResult::TimedOut { completion, .. } => {
                reply_delayed_notice(bot, chat_id).await?;
                queue_background_reply(
                    bot.clone(),
                    chat_id,
                    completion,
                    format!("Delayed for \"{title}\":"),
                );
            }
        }

        Ok(())
    }

    async fn bind_chat_to_thread(&self, chat_id: &str, thread_id: &str) -> Result<()> {
        self.store.set(chat_id, thread_id).await?;
        let _ = force_session_source(
            thread_id,
            &self.config.codex_home,
            "vscode",
            "Codex Desktop",
        )
        .await;
        Ok(())
    }

    async fn resolve_thread_title(&self, thread_id: &str) -> Result<String> {
        let desktop_titles = load_desktop_thread_titles(&self.config.codex_home).await?;
        if let Some(title) = desktop_titles.get(thread_id) {
            return Ok(title.clone());
        }

        if let Some(thread) = find_thread_by_id(thread_id, 800).await? {
            if !thread.preview.trim().is_empty() {
                return Ok(clean_preview(&thread.preview));
            }
        }

        Ok("Untitled thread".to_string())
    }

    async fn transcribe_voice_message(&self, bot: &Bot, message: &Message) -> Result<String> {
        let voice = message
            .voice()
            .ok_or_else(|| anyhow!("No voice payload found."))?;

        let file = bot
            .get_file(voice.file.id.clone())
            .await
            .context("Failed to fetch Telegram voice file metadata")?;

        let file_path = file.path;
        if file_path.trim().is_empty() {
            return Err(anyhow!(
                "Telegram did not return a file path for this voice message."
            ));
        }

        let download_url = format!(
            "https://api.telegram.org/file/bot{}/{}",
            self.config.telegram_bot_token, file_path
        );

        let response = self
            .http
            .get(download_url)
            .send()
            .await
            .context("Failed to download voice file from Telegram")?;

        if !response.status().is_success() {
            return Err(anyhow!(
                "Failed to download voice file from Telegram (HTTP {}).",
                response.status().as_u16()
            ));
        }

        let data = response.bytes().await?;
        let temp_dir = tempfile::Builder::new()
            .prefix("tg-voice-")
            .tempdir()
            .context("Failed to create temporary directory")?;
        let local_file = temp_dir.path().join(
            Path::new(&file_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("voice.oga"),
        );

        fs::write(&local_file, data).await.with_context(|| {
            format!("Failed to write temp voice file: {}", local_file.display())
        })?;

        let script_path = self
            .config
            .project_root
            .join("scripts/transcribe-whispercpp.sh");
        let output = Command::new("bash")
            .arg(script_path)
            .arg(&local_file)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output()
            .await
            .context("Failed to run transcriber script")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let detail = if stderr.is_empty() {
                "Transcriber returned empty output.".to_string()
            } else {
                stderr
            };
            return Err(anyhow!(detail));
        }

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if stdout.is_empty() {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if stderr.is_empty() {
                return Err(anyhow!("Transcriber returned empty output."));
            }
            return Err(anyhow!("Transcriber returned empty output.\n\n{}", stderr));
        }

        Ok(stdout)
    }
}

#[derive(Clone)]
struct DraftSession {
    state: Arc<Mutex<DraftSessionState>>,
}

struct DraftSessionState {
    token: String,
    chat_id: ChatId,
    http: HttpClient,
    enabled: bool,
    throttle: Duration,
    disabled: bool,
    streamers: HashMap<String, DraftStreamerState>,
    used_draft_ids: HashSet<i32>,
    turn_seed: String,
    latest_agent_item_id: Option<String>,
    latest_delivered_draft: Option<String>,
}

#[derive(Clone)]
struct DraftStreamerState {
    draft_id: i32,
    pending: Option<String>,
    last_sent: Option<String>,
    last_sent_at: Option<Instant>,
    has_queued_initial_snapshot: bool,
}

impl DraftSession {
    fn new(
        http: HttpClient,
        token: String,
        chat_id: ChatId,
        enabled: bool,
        throttle: Duration,
    ) -> Self {
        Self {
            state: Arc::new(Mutex::new(DraftSessionState {
                token,
                chat_id,
                http,
                enabled,
                throttle,
                disabled: false,
                streamers: HashMap::new(),
                used_draft_ids: HashSet::new(),
                turn_seed: format!("{}-{}", chrono_like_timestamp(), std::process::id()),
                latest_agent_item_id: None,
                latest_delivered_draft: None,
            })),
        }
    }

    async fn push_snapshot(&self, snapshot: AgentTextSnapshot) -> Result<()> {
        let item_id = snapshot.item_id.trim().to_string();
        if item_id.is_empty() {
            return Ok(());
        }

        let (draft_id, text, token, chat_id, http) = {
            let mut state = self.state.lock().await;
            if !state.enabled || state.disabled {
                return Ok(());
            }

            state.latest_agent_item_id = Some(item_id.clone());

            if !state.streamers.contains_key(&item_id) {
                let seed = format!("{}:{item_id}", state.turn_seed);
                let draft_id = allocate_draft_id(&seed, &mut state.used_draft_ids);
                state.streamers.insert(
                    item_id.clone(),
                    DraftStreamerState {
                        draft_id,
                        pending: None,
                        last_sent: None,
                        last_sent_at: None,
                        has_queued_initial_snapshot: false,
                    },
                );
            }
            let throttle = state.throttle;
            let streamer = state
                .streamers
                .get_mut(&item_id)
                .expect("streamer must exist");

            let normalized = normalize_snapshot(&snapshot.text, TELEGRAM_MESSAGE_LIMIT);
            if normalized.is_empty() || streamer.last_sent.as_deref() == Some(normalized.as_str()) {
                return Ok(());
            }

            streamer.pending = Some(normalized.clone());

            let should_send_now = if !streamer.has_queued_initial_snapshot {
                streamer.has_queued_initial_snapshot = true;
                true
            } else {
                streamer
                    .last_sent_at
                    .map(|last| last.elapsed() >= throttle)
                    .unwrap_or(true)
            };

            if !should_send_now {
                return Ok(());
            }

            let Some(next_text) = streamer.pending.take() else {
                return Ok(());
            };
            streamer.last_sent = Some(next_text.clone());
            streamer.last_sent_at = Some(Instant::now());

            (
                streamer.draft_id,
                next_text,
                state.token.clone(),
                state.chat_id,
                state.http.clone(),
            )
        };

        if let Err(error) = send_message_draft(&http, &token, chat_id, draft_id, &text, None).await
        {
            let mut state = self.state.lock().await;
            state.disabled = true;
            let _ = error;
        }

        Ok(())
    }

    async fn stop(&self, flush_pending: bool) {
        let mut state = self.state.lock().await;

        if !flush_pending {
            for streamer in state.streamers.values_mut() {
                streamer.pending = None;
            }
            state.latest_delivered_draft = None;
            return;
        }

        let mut sends: Vec<(i32, String)> = Vec::new();
        for streamer in state.streamers.values_mut() {
            if let Some(pending) = streamer.pending.take() {
                if streamer.last_sent.as_deref() != Some(pending.as_str()) {
                    streamer.last_sent = Some(pending.clone());
                    streamer.last_sent_at = Some(Instant::now());
                    sends.push((streamer.draft_id, pending));
                }
            }
        }

        let token = state.token.clone();
        let chat_id = state.chat_id;
        let http = state.http.clone();
        let latest_item_id = state.latest_agent_item_id.clone();
        drop(state);

        for (draft_id, text) in sends {
            let _ = send_message_draft(&http, &token, chat_id, draft_id, &text, None).await;
        }

        let mut state = self.state.lock().await;
        if let Some(item_id) = latest_item_id {
            state.latest_delivered_draft = state
                .streamers
                .get(&item_id)
                .and_then(|s| s.last_sent.clone())
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty());
        } else {
            state.latest_delivered_draft = None;
        }
    }

    async fn should_suppress_final_output(&self, text: &str) -> bool {
        let state = self.state.lock().await;
        let normalized = text.trim();
        !normalized.is_empty()
            && state
                .latest_delivered_draft
                .as_deref()
                .map(|draft| draft == normalized)
                .unwrap_or(false)
    }
}

enum ActionOrUtility {
    Action(ActionName),
    Start,
    Help,
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let config = Config::from_env()?;

    let bot = Bot::new(config.telegram_bot_token.clone());
    let me = bot.get_me().await.context("Telegram auth failed")?;

    info!(
        "Telegram Codex bridge is running. Codex home: {}. Session source override: vscode",
        config.codex_home.display()
    );

    if let Some(allowed) = &config.allowed_chat_ids {
        info!(
            "Telegram chat allowlist is active ({} chat ids).",
            allowed.len()
        );
    }

    info!(
        "Telegram auth OK: @{}",
        me.username.clone().unwrap_or_else(|| me.first_name.clone())
    );

    let _ = bot.delete_webhook().drop_pending_updates(true).send().await;

    let gateway = Arc::new(Gateway::new(bot.clone(), config));

    info!(
        "Telegram polling started as @{}",
        me.username.clone().unwrap_or_else(|| me.first_name.clone())
    );

    teloxide::repl(bot.clone(), move |bot: Bot, msg: Message| {
        let gateway = Arc::clone(&gateway);
        async move {
            if let Err(error) = gateway.handle_message(bot, msg).await {
                error!("Telegram bot error: {error}");
            }
            respond(())
        }
    })
    .await;

    Ok(())
}

async fn send_message_draft(
    http: &HttpClient,
    token: &str,
    chat_id: ChatId,
    draft_id: i32,
    text: &str,
    message_thread_id: Option<i32>,
) -> Result<()> {
    let url = format!("https://api.telegram.org/bot{token}/sendMessageDraft");
    let mut payload = json!({
        "chat_id": chat_id.0,
        "draft_id": draft_id,
        "text": text,
    });
    if let Some(thread_id) = message_thread_id {
        payload["message_thread_id"] = json!(thread_id);
    }

    let response = http.post(url).json(&payload).send().await?;
    let body: Value = response
        .json()
        .await
        .unwrap_or_else(|_| json!({ "ok": false }));
    if body.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        return Ok(());
    }

    Err(anyhow!("sendMessageDraft failed"))
}

async fn send_text(
    bot: &Bot,
    chat_id: ChatId,
    text: &str,
    keyboard: Option<KeyboardMarkup>,
    one_time_keyboard: bool,
) -> Result<()> {
    let mut request = bot.send_message(chat_id, text.to_string());
    if let Some(mut markup) = keyboard {
        if one_time_keyboard {
            markup = markup.one_time_keyboard();
        }
        request = request.reply_markup(markup);
    }
    request.await?;
    Ok(())
}

async fn send_text_chunks(bot: &Bot, chat_id: ChatId, text: &str) -> Result<()> {
    for chunk in split_text_for_telegram(text) {
        send_text(bot, chat_id, &chunk, None, false).await?;
    }
    Ok(())
}

async fn send_chat_action(bot: &Bot, chat_id: ChatId) -> Result<()> {
    bot.send_chat_action(chat_id, ChatAction::Typing).await?;
    Ok(())
}

async fn reply_from_timed_turn(
    bot: Bot,
    chat_id: ChatId,
    turn: TimedTurnResult,
    delayed_intro: &str,
    draft: DraftSession,
) -> Result<()> {
    match turn {
        TimedTurnResult::Completed { response } => {
            reply_completed_output(&bot, chat_id, &response, &draft).await?;
        }
        TimedTurnResult::TimedOut { completion } => {
            reply_delayed_notice(&bot, chat_id).await?;
            queue_background_reply(bot, chat_id, completion, delayed_intro.to_string());
        }
    }
    Ok(())
}

fn queue_background_reply(
    bot: Bot,
    chat_id: ChatId,
    completion: JoinHandle<Result<TurnCompletion>>,
    intro: String,
) {
    tokio::spawn(async move {
        let completion_result = completion.await;
        match completion_result {
            Ok(Ok(turn_completion)) => {
                let response = if turn_completion.response.trim().is_empty() {
                    "(Empty Codex response)".to_string()
                } else {
                    turn_completion.response
                };
                let output = format!("{intro}\n\n{response}");
                let _ = send_text_chunks(&bot, chat_id, &output).await;
            }
            Ok(Err(error)) => {
                let _ =
                    send_text(&bot, chat_id, &format!("Codex error: {error}"), None, false).await;
            }
            Err(error) => {
                let _ =
                    send_text(&bot, chat_id, &format!("Codex error: {error}"), None, false).await;
            }
        }
    });
}

async fn reply_completed_output(
    bot: &Bot,
    chat_id: ChatId,
    response: &str,
    draft: &DraftSession,
) -> Result<()> {
    let output = if response.is_empty() {
        "(Empty Codex response)".to_string()
    } else {
        response.to_string()
    };

    if draft.should_suppress_final_output(&output).await {
        return Ok(());
    }

    send_text_chunks(bot, chat_id, &output).await
}

async fn reply_delayed_notice(bot: &Bot, chat_id: ChatId) -> Result<()> {
    send_text(
        bot,
        chat_id,
        "Still working, I will send a message when ready",
        None,
        false,
    )
    .await
}

fn split_text_for_telegram(text: &str) -> Vec<String> {
    if text.len() <= TELEGRAM_MESSAGE_LIMIT {
        return vec![text.to_string()];
    }

    let mut chunks = Vec::new();
    let mut remaining = text.to_string();

    while remaining.len() > TELEGRAM_MESSAGE_CHUNK {
        let mut split_at = remaining[..TELEGRAM_MESSAGE_CHUNK].rfind('\n').unwrap_or(0);

        if split_at < TELEGRAM_MESSAGE_CHUNK / 2 {
            split_at = remaining[..TELEGRAM_MESSAGE_CHUNK].rfind(' ').unwrap_or(0);
        }
        if split_at == 0 {
            split_at = TELEGRAM_MESSAGE_CHUNK;
        }

        let head = remaining[..split_at].trim_end().to_string();
        if !head.is_empty() {
            chunks.push(head);
        }

        remaining = remaining[split_at..].trim_start().to_string();
    }

    if !remaining.is_empty() {
        chunks.push(remaining);
    }

    if chunks.is_empty() {
        vec![String::new()]
    } else {
        chunks
    }
}

fn is_no_rollout_found_error(error: &anyhow::Error) -> bool {
    error.to_string().contains("no rollout found for thread id")
}

fn limit_telegram_text(value: &str, max: usize) -> String {
    if value.len() <= max {
        return value.to_string();
    }
    format!("{}...", &value[..max.saturating_sub(3)])
}

fn format_failure(prefix: &str, message: &str) -> String {
    format!("{prefix}\n\n{message}")
}

fn format_action_title(action: &str, title: &str) -> String {
    format!("{action}: {title}")
}

fn clean_preview(text: &str) -> String {
    let one_line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if one_line.is_empty() {
        return String::new();
    }
    if one_line.len() <= 80 {
        return one_line;
    }
    format!("{}...", &one_line[..77])
}

fn format_folder_label(folder: &str) -> String {
    let normalized = folder.replace(['_', '-'], " ");
    let normalized = normalized.trim();
    if normalized.is_empty() {
        return "Unknown Folder".to_string();
    }

    normalized
        .split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_ascii_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn quick_actions_keyboard() -> KeyboardMarkup {
    KeyboardMarkup::new(vec![
        vec![KeyboardButton::new("New Chat")],
        vec![KeyboardButton::new("Resume Chat")],
        vec![KeyboardButton::new("Delete Chat")],
    ])
    .resize_keyboard()
    .persistent()
}

fn approval_keyboard() -> KeyboardMarkup {
    KeyboardMarkup::new(vec![
        vec![KeyboardButton::new("Accept")],
        vec![KeyboardButton::new("Accept Session")],
        vec![KeyboardButton::new("Decline")],
        vec![KeyboardButton::new("Cancel")],
    ])
    .resize_keyboard()
    .one_time_keyboard()
}

fn thread_selection_keyboard(thread_titles: &[String], include_new_button: bool) -> KeyboardMarkup {
    let mut rows: Vec<Vec<KeyboardButton>> = Vec::new();
    if include_new_button {
        rows.push(vec![KeyboardButton::new("New Chat")]);
    }

    for label in build_thread_selection_labels(thread_titles) {
        rows.push(vec![KeyboardButton::new(label)]);
    }

    KeyboardMarkup::new(rows)
        .resize_keyboard()
        .one_time_keyboard()
}

fn new_folder_selection_keyboard(folder_labels: &[String]) -> KeyboardMarkup {
    let rows = build_folder_selection_labels(folder_labels)
        .into_iter()
        .map(|label| vec![KeyboardButton::new(label)])
        .collect::<Vec<_>>();
    KeyboardMarkup::new(rows)
        .resize_keyboard()
        .one_time_keyboard()
}

fn build_thread_selection_labels(thread_titles: &[String]) -> Vec<String> {
    thread_titles
        .iter()
        .enumerate()
        .map(|(idx, title)| {
            format!(
                "{}. {}",
                idx + 1,
                format_thread_button_label(title.as_str())
            )
        })
        .collect()
}

fn build_folder_selection_labels(folder_labels: &[String]) -> Vec<String> {
    folder_labels
        .iter()
        .enumerate()
        .map(|(idx, label)| format!("{}. {}", idx + 1, label))
        .collect()
}

fn parse_selection_from_options(text: &str, option_labels: &[String]) -> Option<usize> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Some(explicit) = parse_standalone_selection_index(trimmed) {
        if explicit >= 1 && explicit <= option_labels.len() {
            return Some(explicit);
        }
    }

    let normalized = normalize_for_comparison(trimmed);
    option_labels
        .iter()
        .position(|label| normalize_for_comparison(label) == normalized)
        .map(|idx| idx + 1)
}

fn parse_approval_decision_text(text: &str) -> Option<ApprovalDecision> {
    match text.trim().to_lowercase().as_str() {
        "accept" => Some(ApprovalDecision::Accept),
        "accept session" => Some(ApprovalDecision::AcceptForSession),
        "decline" => Some(ApprovalDecision::Decline),
        "cancel" => Some(ApprovalDecision::Cancel),
        _ => None,
    }
}

fn format_thread_button_label(title: &str) -> String {
    let one_line = title.split_whitespace().collect::<Vec<_>>().join(" ");
    if one_line.is_empty() {
        return "Untitled".to_string();
    }
    if one_line.len() <= 36 {
        return one_line;
    }
    format!("{}...", &one_line[..33])
}

fn parse_standalone_selection_index(text: &str) -> Option<usize> {
    let re = Regex::new(r"^(\d+)\.?$").ok()?;
    let captures = re.captures(text)?;
    captures.get(1)?.as_str().parse::<usize>().ok()
}

fn normalize_for_comparison(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn map_action_from_text(input: &str) -> Option<ActionOrUtility> {
    let normalized = normalize_input_command(input);
    match normalized.as_str() {
        "new" | "n" | "new chat" => Some(ActionOrUtility::Action(ActionName::New)),
        "resume" | "r" | "resume chat" => Some(ActionOrUtility::Action(ActionName::Resume)),
        "delete" | "d" | "delete chat" => Some(ActionOrUtility::Action(ActionName::Delete)),
        "help" | "h" => Some(ActionOrUtility::Help),
        "start" => Some(ActionOrUtility::Start),
        _ => None,
    }
}

fn normalize_input_command(input: &str) -> String {
    let trimmed = input.trim().to_lowercase();
    if let Some(stripped) = trimmed.strip_prefix('/') {
        let command = stripped
            .split_whitespace()
            .next()
            .unwrap_or("")
            .split('@')
            .next()
            .unwrap_or("");
        return command.to_string();
    }
    trimmed
}

fn format_approval_prompt(request: &ApprovalRequest) -> String {
    let mut lines = Vec::new();
    match request.method {
        ApprovalMethod::FileChange => lines.push("Approval needed: file changes".to_string()),
        ApprovalMethod::CommandExecution => {
            lines.push("Approval needed: command execution".to_string())
        }
    }

    if let Some(command) = &request.command {
        lines.push(format!("Command: {command}"));
    }
    if let Some(cwd) = &request.cwd {
        lines.push(format!("Folder: {cwd}"));
    }
    if let Some(reason) = &request.reason {
        lines.push(format!("Reason: {reason}"));
    }

    lines.push(String::new());
    lines.push("Choose an action:".to_string());
    lines.join("\n")
}

fn list_folder_choices(threads: &[ThreadSummary], default_cwd: &str) -> Vec<ListedFolderChoice> {
    let mut by_updated = threads.to_vec();
    by_updated.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));

    let mut seen = HashSet::new();
    let mut choices = Vec::new();

    for thread in by_updated {
        let cwd = thread.cwd.trim().to_string();
        if cwd.is_empty() || seen.contains(&cwd) {
            continue;
        }
        seen.insert(cwd.clone());
        choices.push(ListedFolderChoice {
            cwd: cwd.clone(),
            label: to_folder_button_label(&cwd),
        });
    }

    if !default_cwd.trim().is_empty() && !seen.contains(default_cwd.trim()) {
        choices.insert(
            0,
            ListedFolderChoice {
                cwd: default_cwd.trim().to_string(),
                label: to_folder_button_label(default_cwd.trim()),
            },
        );
    }

    choices
}

fn to_folder_button_label(cwd: &str) -> String {
    let base = Path::new(cwd)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(cwd);
    let formatted = format_folder_label(base);
    if formatted.len() <= 24 {
        return formatted;
    }
    format!("{}...", &formatted[..21])
}

fn resolve_session_title(
    thread: &ThreadSummary,
    desktop_titles: &HashMap<String, String>,
) -> String {
    if let Some(title) = desktop_titles.get(&thread.id) {
        return title.clone();
    }

    let preview = clean_preview(&thread.preview);
    if !preview.is_empty() {
        return preview;
    }

    "Untitled thread".to_string()
}

fn parse_allowed_chat_ids(value: Option<String>) -> Option<HashSet<String>> {
    let value = value?;
    let ids = value
        .split(',')
        .map(|item| item.trim())
        .filter(|item| !item.is_empty())
        .map(|item| item.to_string())
        .collect::<HashSet<_>>();
    Some(ids)
}

fn parse_bool(value: Option<&str>) -> Option<bool> {
    match value?.trim() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn resolve_user_path(value: &str, project_root: &Path, home: &Path) -> PathBuf {
    let expanded = expand_home_path(value, home);
    if expanded.is_absolute() {
        expanded
    } else {
        project_root.join(expanded)
    }
}

fn expand_home_path(input: &str, home: &Path) -> PathBuf {
    let home_str = home.to_string_lossy();
    if input == "~" {
        return home.to_path_buf();
    }
    if let Some(rest) = input.strip_prefix("~/") {
        return PathBuf::from(format!("{home_str}/{rest}"));
    }
    if input == "$HOME" {
        return home.to_path_buf();
    }
    if let Some(rest) = input.strip_prefix("$HOME/") {
        return PathBuf::from(format!("{home_str}/{rest}"));
    }
    if input == "${HOME}" {
        return home.to_path_buf();
    }
    if let Some(rest) = input.strip_prefix("${HOME}/") {
        return PathBuf::from(format!("{home_str}/{rest}"));
    }

    PathBuf::from(input)
}

fn dirs_home() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME env var is missing"))
}

fn chrono_like_timestamp() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or_default()
}

fn normalize_snapshot(text: &str, max_length: usize) -> String {
    if text.len() <= max_length {
        return text.to_string();
    }
    let keep = max_length.saturating_sub(3).max(1);
    format!("...{}", &text[text.len().saturating_sub(keep)..])
}

fn allocate_draft_id(seed: &str, used: &mut HashSet<i32>) -> i32 {
    let mut hash: u32 = 2_166_136_261;
    for b in seed.as_bytes() {
        hash ^= *b as u32;
        hash = hash.wrapping_mul(16_777_619);
    }

    let mut candidate = ((hash >> 1) as i32).max(1);
    while used.contains(&candidate) {
        candidate = if candidate >= 2_147_483_646 {
            1
        } else {
            candidate + 1
        };
    }

    used.insert(candidate);
    candidate
}

async fn list_threads(limit: usize) -> Result<Vec<ThreadSummary>> {
    let mut client = AppServerConnection::new(TurnRuntimeOptions::default()).await?;
    client.initialize().await?;

    let page_size = limit.max(1);
    let mut threads = Vec::new();
    let mut cursor: Option<String> = None;

    while threads.len() < page_size {
        let remaining = page_size - threads.len();
        let result = client
            .send_request(
                "thread/list",
                build_thread_list_params(remaining, cursor.clone()),
            )
            .await?;

        let (page, next_cursor) = parse_thread_list_page(&result);
        threads.extend(page);
        if next_cursor.is_none() {
            break;
        }
        cursor = next_cursor;
    }

    client.close().await;
    Ok(threads)
}

async fn find_thread_by_id(thread_id: &str, max_to_scan: usize) -> Result<Option<ThreadSummary>> {
    let mut client = AppServerConnection::new(TurnRuntimeOptions::default()).await?;
    client.initialize().await?;

    let scan_limit = max_to_scan.max(1);
    let mut scanned = 0usize;
    let mut cursor: Option<String> = None;

    while scanned < scan_limit {
        let page_limit = (scan_limit - scanned).min(100);
        let result = client
            .send_request(
                "thread/list",
                build_thread_list_params(page_limit, cursor.clone()),
            )
            .await?;

        let (threads, next_cursor) = parse_thread_list_page(&result);

        if let Some(matched) = threads.iter().find(|thread| thread.id == thread_id) {
            client.close().await;
            return Ok(Some(matched.clone()));
        }

        scanned += threads.len();
        if next_cursor.is_none() || threads.is_empty() {
            client.close().await;
            return Ok(None);
        }
        cursor = next_cursor;
    }

    client.close().await;
    Ok(None)
}

async fn send_message_with_timeout_continuation(
    conversation_id: String,
    text: String,
    runtime_options: TurnRuntimeOptions,
) -> Result<TimedTurnResult> {
    send_message_with_timeout_continuation_internal(conversation_id, text, true, runtime_options)
        .await
}

async fn send_message_without_resume_with_timeout_continuation(
    conversation_id: String,
    text: String,
    runtime_options: TurnRuntimeOptions,
) -> Result<TimedTurnResult> {
    send_message_with_timeout_continuation_internal(conversation_id, text, false, runtime_options)
        .await
}

async fn send_message_with_timeout_continuation_internal(
    conversation_id: String,
    text: String,
    resume_first: bool,
    runtime_options: TurnRuntimeOptions,
) -> Result<TimedTurnResult> {
    let mut client = AppServerConnection::new(runtime_options).await?;
    client.initialize().await?;

    let mut completion = tokio::spawn(async move {
        let response = run_turn(&mut client, &conversation_id, &text, resume_first).await?;
        client.close().await;
        Ok(TurnCompletion { response })
    });

    match timeout(TURN_TIMEOUT, &mut completion).await {
        Ok(joined) => {
            let completion_result = joined.context("turn task join failed")??;
            Ok(TimedTurnResult::Completed {
                response: completion_result.response,
            })
        }
        Err(_) => Ok(TimedTurnResult::TimedOut { completion }),
    }
}

async fn create_and_send_first_message_with_timeout_continuation(
    options: ConversationOptions,
    text: String,
    runtime_options: TurnRuntimeOptions,
) -> Result<TimedCreateTurnResult> {
    let mut client = AppServerConnection::new(runtime_options).await?;
    client.initialize().await?;

    let conversation_id = start_conversation_on_client(&mut client, options).await?;
    let turn_conversation_id = conversation_id.clone();

    let mut completion = tokio::spawn(async move {
        let response = run_turn(&mut client, &turn_conversation_id, &text, false).await?;
        client.close().await;
        Ok(TurnCompletion { response })
    });

    match timeout(TURN_TIMEOUT, &mut completion).await {
        Ok(joined) => {
            let result = joined.context("turn task join failed")??;
            Ok(TimedCreateTurnResult::Completed {
                conversation_id,
                response: result.response,
            })
        }
        Err(_) => Ok(TimedCreateTurnResult::TimedOut {
            conversation_id,
            completion,
        }),
    }
}

struct AppServerConnection {
    child: Child,
    stdin: ChildStdin,
    stdout: tokio::io::Lines<BufReader<ChildStdout>>,
    next_id: u64,
    queued_notifications: VecDeque<Value>,
    runtime_options: TurnRuntimeOptions,
}

impl AppServerConnection {
    async fn new(runtime_options: TurnRuntimeOptions) -> Result<Self> {
        let mut child = Command::new("codex")
            .args(["app-server", "--listen", "stdio://"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("Failed to start codex app-server")?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("Failed to capture app-server stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("Failed to capture app-server stdout"))?;

        Ok(Self {
            child,
            stdin,
            stdout: BufReader::new(stdout).lines(),
            next_id: 1,
            queued_notifications: VecDeque::new(),
            runtime_options,
        })
    }

    async fn initialize(&mut self) -> Result<()> {
        self.send_request(
            "initialize",
            json!({
                "clientInfo": {
                    "name": "telegram-gateway",
                    "title": null,
                    "version": "1.0"
                },
                "capabilities": {
                    "experimentalApi": true
                }
            }),
        )
        .await?;

        self.send_notification("initialized", None).await
    }

    async fn close(&mut self) {
        if self.child.id().is_none() {
            return;
        }

        if let Some(id) = self.child.id() {
            let _ = id;
        }

        let _ = self.child.start_kill();
        let _ = timeout(Duration::from_millis(1500), self.child.wait()).await;
    }

    async fn send_request(&mut self, method: &str, params: Value) -> Result<Value> {
        let id = self.next_id;
        self.next_id += 1;

        self.write_json(&json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        }))
        .await?;

        loop {
            let message = self.read_next_message().await?;

            if is_server_request(&message) {
                self.handle_server_request(message).await?;
                continue;
            }

            if is_notification(&message) {
                self.queued_notifications.push_back(message);
                continue;
            }

            if message
                .get("id")
                .and_then(Value::as_u64)
                .map(|message_id| message_id == id)
                .unwrap_or(false)
            {
                if let Some(error) = message.get("error") {
                    let message = error
                        .get("message")
                        .and_then(Value::as_str)
                        .unwrap_or("Unknown app-server error")
                        .to_string();
                    return Err(anyhow!(message));
                }

                return Ok(message
                    .get("result")
                    .cloned()
                    .unwrap_or_else(|| Value::Object(Default::default())));
            }
        }
    }

    async fn send_notification(&mut self, method: &str, params: Option<Value>) -> Result<()> {
        let mut payload = json!({
            "jsonrpc": "2.0",
            "method": method,
        });
        if let Some(value) = params {
            payload["params"] = value;
        }
        self.write_json(&payload).await
    }

    async fn next_notification(&mut self) -> Result<Value> {
        if let Some(notification) = self.queued_notifications.pop_front() {
            return Ok(notification);
        }

        loop {
            let message = self.read_next_message().await?;
            if is_server_request(&message) {
                self.handle_server_request(message).await?;
                continue;
            }
            if is_notification(&message) {
                return Ok(message);
            }
        }
    }

    async fn write_json(&mut self, value: &Value) -> Result<()> {
        let mut line = serde_json::to_string(value)?;
        line.push('\n');
        self.stdin.write_all(line.as_bytes()).await?;
        self.stdin.flush().await?;
        Ok(())
    }

    async fn read_next_message(&mut self) -> Result<Value> {
        loop {
            let maybe_line = self.stdout.next_line().await?;
            let Some(line) = maybe_line else {
                return Err(anyhow!("app-server process exited"));
            };
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            match serde_json::from_str::<Value>(trimmed) {
                Ok(value) => return Ok(value),
                Err(_) => continue,
            }
        }
    }

    async fn handle_server_request(&mut self, request: Value) -> Result<()> {
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let method = request
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let params = request.get("params").cloned().unwrap_or(Value::Null);

        let response = match method {
            "execCommandApproval" | "applyPatchApproval" => {
                let decision = self
                    .request_decision_from_handler(to_legacy_approval_request(method, &params))
                    .await;
                Ok(json!({
                    "decision": map_legacy_approval_decision(decision)
                }))
            }
            "item/commandExecution/requestApproval" | "item/fileChange/requestApproval" => {
                let decision = self
                    .request_decision_from_handler(to_v2_approval_request(method, &params))
                    .await;
                Ok(json!({
                    "decision": map_approval_decision(decision)
                }))
            }
            "item/tool/requestUserInput" => {
                let answers = build_empty_tool_input_answers(
                    params
                        .get("questions")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default(),
                );
                Ok(json!({ "answers": answers }))
            }
            "item/tool/call" => Ok(json!({
                "success": false,
                "contentItems": [{
                    "type": "inputText",
                    "text": "Dynamic tool calls are not supported by this Telegram gateway."
                }]
            })),
            "account/chatgptAuthTokens/refresh" => Err(anyhow!(
                "ChatGPT auth token refresh is not supported in this gateway runtime."
            )),
            _ => Err(anyhow!("Unsupported server request method: {method}")),
        };

        match response {
            Ok(result) => {
                self.write_json(&json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": result,
                }))
                .await?;
            }
            Err(error) => {
                self.write_json(&json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": {
                        "code": -32000,
                        "message": error.to_string(),
                    }
                }))
                .await?;
            }
        }

        Ok(())
    }

    async fn request_decision_from_handler(
        &self,
        request: Option<ApprovalRequest>,
    ) -> ApprovalDecision {
        let Some(request) = request else {
            return ApprovalDecision::Decline;
        };

        let Some(handler) = &self.runtime_options.approval_handler else {
            return ApprovalDecision::Decline;
        };

        handler(request).await
    }
}

async fn run_turn(
    client: &mut AppServerConnection,
    conversation_id: &str,
    text: &str,
    resume_first: bool,
) -> Result<String> {
    if resume_first {
        client
            .send_request(
                "thread/resume",
                json!({
                    "threadId": conversation_id,
                }),
            )
            .await?;
    }

    let started = client
        .send_request(
            "turn/start",
            json!({
                "threadId": conversation_id,
                "input": [
                    {
                        "type": "text",
                        "text": text,
                    }
                ]
            }),
        )
        .await?;

    let started_turn = started
        .get("turn")
        .cloned()
        .unwrap_or_else(|| Value::Object(Default::default()));

    let current_turn_id = started_turn
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    let status = started_turn
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("");

    if status == "failed" {
        return Err(anyhow!(get_turn_failure_message(&started_turn)));
    }
    if status == "interrupted" {
        return Err(anyhow!("Turn was interrupted before completion."));
    }
    if status == "completed" {
        return Ok(String::new());
    }
    if !status.is_empty() && status != "inProgress" {
        return Err(anyhow!("Turn started with unexpected status: {status}"));
    }

    let mut last_agent_message = String::new();
    let mut agent_snapshots: HashMap<String, String> = HashMap::new();

    loop {
        let notification = client.next_notification().await?;
        let method = notification
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let params = notification
            .get("params")
            .cloned()
            .unwrap_or_else(|| Value::Object(Default::default()));

        let event_thread_id = params
            .get("threadId")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if event_thread_id != conversation_id {
            continue;
        }

        if method == "item/agentMessage/delta" {
            let event_turn_id = params
                .get("turnId")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if event_turn_id != current_turn_id {
                continue;
            }

            if let Some(delta) = params.get("delta").and_then(Value::as_str) {
                let item_id = params
                    .get("itemId")
                    .and_then(Value::as_str)
                    .unwrap_or("agent-message")
                    .to_string();
                let next_snapshot = format!(
                    "{}{}",
                    agent_snapshots.get(&item_id).cloned().unwrap_or_default(),
                    delta
                );
                agent_snapshots.insert(item_id.clone(), next_snapshot.clone());
                last_agent_message = next_snapshot.clone();
                if let Some(handler) = &client.runtime_options.on_agent_text_snapshot {
                    handler(AgentTextSnapshot {
                        item_id,
                        text: next_snapshot,
                    });
                }
            }
            continue;
        }

        if method == "item/completed" {
            let event_turn_id = params
                .get("turnId")
                .and_then(Value::as_str)
                .unwrap_or_default();
            if event_turn_id != current_turn_id {
                continue;
            }

            let item = params
                .get("item")
                .cloned()
                .unwrap_or_else(|| Value::Object(Default::default()));
            if item.get("type").and_then(Value::as_str) != Some("agentMessage") {
                continue;
            }

            if let Some(text) = item.get("text").and_then(Value::as_str) {
                let item_id = item
                    .get("id")
                    .and_then(Value::as_str)
                    .or_else(|| params.get("itemId").and_then(Value::as_str))
                    .unwrap_or("agent-message")
                    .to_string();

                last_agent_message = text.to_string();
                agent_snapshots.insert(item_id.clone(), text.to_string());
                if let Some(handler) = &client.runtime_options.on_agent_text_snapshot {
                    handler(AgentTextSnapshot {
                        item_id,
                        text: text.to_string(),
                    });
                }
            }
            continue;
        }

        if method != "turn/completed" {
            continue;
        }

        let turn = params
            .get("turn")
            .cloned()
            .unwrap_or_else(|| Value::Object(Default::default()));
        let event_turn_id = turn.get("id").and_then(Value::as_str).unwrap_or_default();
        if event_turn_id != current_turn_id {
            continue;
        }

        let status = turn.get("status").and_then(Value::as_str).unwrap_or("");
        if status == "completed" {
            return Ok(last_agent_message.trim().to_string());
        }
        if status == "interrupted" {
            let trimmed = last_agent_message.trim().to_string();
            if trimmed.is_empty() {
                return Err(anyhow!("Turn was interrupted before producing a response."));
            }
            return Ok(trimmed);
        }
        if status == "failed" {
            return Err(anyhow!(get_turn_failure_message(&turn)));
        }
        if status == "inProgress" {
            continue;
        }

        return Err(anyhow!(
            "Turn ended with unexpected status: {}",
            if status.is_empty() { "unknown" } else { status }
        ));
    }
}

async fn start_conversation_on_client(
    client: &mut AppServerConnection,
    options: ConversationOptions,
) -> Result<String> {
    let result = client
        .send_request("thread/start", build_thread_start_params(options))
        .await?;

    let conversation_id = result
        .get("thread")
        .and_then(Value::as_object)
        .and_then(|thread| thread.get("id"))
        .and_then(Value::as_str)
        .map(|s| s.to_string());

    conversation_id.ok_or_else(|| anyhow!("app-server thread/start did not return a thread id"))
}

fn build_thread_start_params(options: ConversationOptions) -> Value {
    let mut params = json!({ "cwd": options.cwd });

    if let Some(model) = options.model {
        params["model"] = json!(model);
    }
    if let Some(approval_policy) = options.approval_policy {
        params["approvalPolicy"] = json!(approval_policy.as_str());
    }
    if let Some(sandbox_mode) = options.sandbox_mode {
        params["sandbox"] = json!(sandbox_mode.as_str());
    }

    if let Some(config) =
        build_config_overrides(options.network_access_enabled, options.skip_git_repo_check)
    {
        params["config"] = config;
    }

    params
}

fn build_config_overrides(
    network_access_enabled: Option<bool>,
    skip_git_repo_check: Option<bool>,
) -> Option<Value> {
    let mut overrides = serde_json::Map::new();

    if let Some(network) = network_access_enabled {
        overrides.insert(
            "sandbox_workspace_write".to_string(),
            json!({ "network_access": network }),
        );
    }

    if let Some(skip) = skip_git_repo_check {
        overrides.insert("ignore_git_repo_check".to_string(), json!(skip));
    }

    if overrides.is_empty() {
        None
    } else {
        Some(Value::Object(overrides))
    }
}

fn parse_thread_list_page(result: &Value) -> (Vec<ThreadSummary>, Option<String>) {
    let data = result
        .get("data")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let next_cursor = result
        .get("nextCursor")
        .and_then(Value::as_str)
        .map(|s| s.to_string())
        .filter(|s| !s.trim().is_empty());

    let mut threads = Vec::new();

    for entry in data {
        let Some(thread_obj) = entry.as_object() else {
            continue;
        };

        let id = thread_obj
            .get("id")
            .and_then(Value::as_str)
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let cwd = thread_obj
            .get("cwd")
            .and_then(Value::as_str)
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let preview = thread_obj
            .get("preview")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let created_at = thread_obj.get("createdAt").and_then(Value::as_i64);
        let updated_at = thread_obj.get("updatedAt").and_then(Value::as_i64);

        if id.is_none() || cwd.is_none() || created_at.is_none() || updated_at.is_none() {
            continue;
        }

        threads.push(ThreadSummary {
            id: id.expect("validated"),
            cwd: cwd.expect("validated"),
            preview,
            created_at: created_at.expect("validated"),
            updated_at: updated_at.expect("validated"),
            path: thread_obj
                .get("path")
                .and_then(Value::as_str)
                .map(|s| s.to_string()),
            source: normalize_source(thread_obj.get("source").cloned()),
        });
    }

    (threads, next_cursor)
}

fn build_thread_list_params(limit: usize, cursor: Option<String>) -> Value {
    json!({
        "limit": limit.max(1),
        "sortKey": "updated_at",
        "sourceKinds": THREAD_SOURCE_KINDS,
        "cursor": cursor,
    })
}

fn normalize_source(source: Option<Value>) -> String {
    let Some(source) = source else {
        return "unknown".to_string();
    };

    if let Some(source_str) = source.as_str() {
        return source_str.to_string();
    }

    let Some(obj) = source.as_object() else {
        return "unknown".to_string();
    };

    if let Some((kind, value)) = obj.iter().next() {
        if let Some(v) = value.as_str() {
            return format!("{kind}:{v}");
        }
        return kind.to_string();
    }

    "unknown".to_string()
}

fn is_server_request(message: &Value) -> bool {
    message.get("method").is_some() && message.get("id").is_some()
}

fn is_notification(message: &Value) -> bool {
    message.get("method").is_some() && message.get("id").is_none()
}

fn to_v2_approval_request(method: &str, params: &Value) -> Option<ApprovalRequest> {
    let method = match method {
        "item/commandExecution/requestApproval" => ApprovalMethod::CommandExecution,
        "item/fileChange/requestApproval" => ApprovalMethod::FileChange,
        _ => return None,
    };

    let thread_id = params.get("threadId")?.as_str()?.trim().to_string();
    let turn_id = params.get("turnId")?.as_str()?.trim().to_string();
    let item_id = params.get("itemId")?.as_str()?.trim().to_string();

    if thread_id.is_empty() || turn_id.is_empty() || item_id.is_empty() {
        return None;
    }

    Some(ApprovalRequest {
        method,
        thread_id,
        turn_id,
        item_id,
        approval_id: params
            .get("approvalId")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
        reason: params
            .get("reason")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
        command: params
            .get("command")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
        cwd: params
            .get("cwd")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
    })
}

fn to_legacy_approval_request(method: &str, params: &Value) -> Option<ApprovalRequest> {
    let method = match method {
        "execCommandApproval" => ApprovalMethod::CommandExecution,
        "applyPatchApproval" => ApprovalMethod::FileChange,
        _ => return None,
    };

    let thread_id = params
        .get("conversationId")
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    let call_id = params
        .get("callId")
        .and_then(Value::as_str)?
        .trim()
        .to_string();

    if thread_id.is_empty() || call_id.is_empty() {
        return None;
    }

    let command = params
        .get("command")
        .and_then(Value::as_array)
        .map(|parts| {
            parts
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(" ")
        })
        .filter(|value| !value.is_empty());

    Some(ApprovalRequest {
        method,
        thread_id,
        turn_id: call_id.clone(),
        item_id: call_id,
        approval_id: params
            .get("approvalId")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
        reason: params
            .get("reason")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
        command,
        cwd: params
            .get("cwd")
            .and_then(Value::as_str)
            .map(|s| s.to_string()),
    })
}

fn map_legacy_approval_decision(decision: ApprovalDecision) -> &'static str {
    match decision {
        ApprovalDecision::Accept => "approved",
        ApprovalDecision::AcceptForSession => "approved_for_session",
        ApprovalDecision::Cancel => "abort",
        ApprovalDecision::Decline => "denied",
    }
}

fn map_approval_decision(decision: ApprovalDecision) -> &'static str {
    match decision {
        ApprovalDecision::Accept => "accept",
        ApprovalDecision::AcceptForSession => "acceptForSession",
        ApprovalDecision::Decline => "decline",
        ApprovalDecision::Cancel => "cancel",
    }
}

fn build_empty_tool_input_answers(questions: Vec<Value>) -> Value {
    let mut answers = serde_json::Map::new();
    for question in questions {
        let Some(id) = question.get("id").and_then(Value::as_str) else {
            continue;
        };
        if id.trim().is_empty() {
            continue;
        }
        answers.insert(id.to_string(), json!({ "answers": [] }));
    }
    Value::Object(answers)
}

fn get_turn_failure_message(turn: &Value) -> String {
    let error = turn
        .get("error")
        .cloned()
        .unwrap_or_else(|| Value::Object(Default::default()));
    let message = error.get("message").and_then(Value::as_str).unwrap_or("");
    let details = error
        .get("additionalDetails")
        .and_then(Value::as_str)
        .unwrap_or("");

    if !message.is_empty() && !details.is_empty() {
        return format!("{message}\n{details}");
    }
    if !message.is_empty() {
        return message.to_string();
    }

    "Turn failed.".to_string()
}

async fn load_desktop_thread_titles(codex_home: &Path) -> Result<HashMap<String, String>> {
    let file_path = codex_home.join(".codex-global-state.json");
    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(HashMap::new()),
    };

    let parsed: Value = match serde_json::from_str(&raw) {
        Ok(value) => value,
        Err(_) => return Ok(HashMap::new()),
    };

    let titles = parsed
        .get("thread-titles")
        .and_then(Value::as_object)
        .and_then(|obj| obj.get("titles"))
        .and_then(Value::as_object);

    let Some(titles) = titles else {
        return Ok(HashMap::new());
    };

    let mut out = HashMap::new();
    for (thread_id, title) in titles {
        if let Some(title) = title.as_str() {
            let trimmed = title.trim();
            if !trimmed.is_empty() {
                out.insert(thread_id.clone(), trimmed.to_string());
            }
        }
    }

    Ok(out)
}

async fn force_session_source(
    thread_id: &str,
    codex_home: &Path,
    source: &str,
    originator: &str,
) -> Result<bool> {
    let sessions_root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&sessions_root, thread_id).await? else {
        return Ok(false);
    };

    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(false),
    };

    let mut lines = raw.lines().map(ToString::to_string).collect::<Vec<_>>();
    if lines.is_empty() || lines[0].trim().is_empty() {
        return Ok(false);
    }

    let mut first: Value = match serde_json::from_str(&lines[0]) {
        Ok(value) => value,
        Err(_) => return Ok(false),
    };

    let Some(payload) = first.get_mut("payload").and_then(Value::as_object_mut) else {
        return Ok(false);
    };

    let current_source = payload
        .get("source")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let current_originator = payload
        .get("originator")
        .and_then(Value::as_str)
        .unwrap_or_default();

    if current_source == source && current_originator == originator {
        return Ok(true);
    }

    payload.insert("source".to_string(), json!(source));
    payload.insert("originator".to_string(), json!(originator));

    lines[0] = serde_json::to_string(&first)?;
    fs::write(&file_path, lines.join("\n"))
        .await
        .with_context(|| format!("Failed to update session file: {}", file_path.display()))?;

    Ok(true)
}

async fn delete_session_by_thread_id(thread_id: &str, codex_home: &Path) -> Result<bool> {
    let root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&root, thread_id).await? else {
        return Ok(false);
    };

    match fs::remove_file(&file_path).await {
        Ok(_) => {
            prune_empty_parent_dirs(file_path.parent().unwrap_or(&root), &root).await?;
            Ok(true)
        }
        Err(error) => {
            if error.kind() == std::io::ErrorKind::NotFound {
                return Ok(false);
            }
            Err(error.into())
        }
    }
}

async fn load_latest_assistant_message_by_thread_id(
    thread_id: &str,
    codex_home: &Path,
) -> Result<Option<String>> {
    let sessions_root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&sessions_root, thread_id).await? else {
        return Ok(None);
    };

    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(None),
    };

    let mut latest: Option<String> = None;
    for line in raw.lines() {
        if let Some(text) = extract_assistant_text_from_session_line(line) {
            latest = Some(text);
        }
    }

    Ok(latest)
}

async fn find_session_file_by_thread_id(dir: &Path, thread_id: &str) -> Result<Option<PathBuf>> {
    let mut stack = vec![dir.to_path_buf()];

    while let Some(current) = stack.pop() {
        let mut entries = match fs::read_dir(&current).await {
            Ok(items) => items,
            Err(_) => continue,
        };

        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let file_type = match entry.file_type().await {
                Ok(file_type) => file_type,
                Err(_) => continue,
            };

            if file_type.is_dir() {
                stack.push(path);
                continue;
            }

            if file_type.is_file() {
                let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                    continue;
                };
                if !name.ends_with(".jsonl") {
                    continue;
                }

                if extract_id_from_name(name).as_deref() == Some(thread_id) {
                    return Ok(Some(path));
                }
            }
        }
    }

    Ok(None)
}

fn extract_id_from_name(file_name: &str) -> Option<String> {
    let stem = file_name.strip_suffix(".jsonl")?;
    let regex =
        Regex::new(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
            .ok()?;
    regex.find(stem).map(|m| m.as_str().to_string())
}

fn extract_assistant_text_from_session_line(line: &str) -> Option<String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    let parsed: Value = serde_json::from_str(trimmed).ok()?;
    if parsed.get("type")?.as_str()? != "response_item" {
        return None;
    }

    let payload = parsed.get("payload")?;
    if payload.get("type")?.as_str()? != "message" {
        return None;
    }
    if payload.get("role")?.as_str()? != "assistant" {
        return None;
    }

    let content = payload.get("content")?.as_array()?;
    let mut parts = Vec::new();
    for item in content {
        if let Some(text) = item.get("text").and_then(Value::as_str) {
            let trimmed_text = text.trim();
            if !trimmed_text.is_empty() {
                parts.push(trimmed_text.to_string());
            }
        }
    }

    if parts.is_empty() {
        None
    } else {
        Some(parts.join("\n\n"))
    }
}

async fn prune_empty_parent_dirs(start_dir: &Path, sessions_root: &Path) -> Result<()> {
    let mut current = start_dir.to_path_buf();

    while is_same_dir_or_child(sessions_root, &current) && current != sessions_root {
        let mut entries = match fs::read_dir(&current).await {
            Ok(items) => items,
            Err(_) => return Ok(()),
        };

        if entries.next_entry().await?.is_some() {
            return Ok(());
        }

        if fs::remove_dir(&current).await.is_err() {
            return Ok(());
        }

        let Some(parent) = current.parent() else {
            break;
        };
        current = parent.to_path_buf();
    }

    Ok(())
}

fn is_same_dir_or_child(parent: &Path, target: &Path) -> bool {
    if let Ok(relative) = target.strip_prefix(parent) {
        return relative.components().next().is_some() || target == parent;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_selection_accepts_numeric_labels() {
        let options = vec![
            "1. First Choice".to_string(),
            "2. Second Choice".to_string(),
            "3. Third Choice".to_string(),
        ];

        assert_eq!(parse_selection_from_options("2", &options), Some(2));
        assert_eq!(parse_selection_from_options("3.", &options), Some(3));
        assert_eq!(
            parse_selection_from_options("2. Second Choice", &options),
            Some(2)
        );
        assert_eq!(parse_selection_from_options("9", &options), None);
    }

    #[test]
    fn split_text_for_telegram_chunks_long_messages() {
        let input = "x".repeat(TELEGRAM_MESSAGE_LIMIT + 500);
        let chunks = split_text_for_telegram(&input);

        assert!(chunks.len() >= 2);
        assert!(chunks
            .iter()
            .all(|chunk| chunk.len() <= TELEGRAM_MESSAGE_CHUNK));
        assert_eq!(chunks.join(""), input);
    }

    #[test]
    fn action_mapper_understands_slash_commands_and_shortcuts() {
        assert!(matches!(
            map_action_from_text("/new"),
            Some(ActionOrUtility::Action(ActionName::New))
        ));
        assert!(matches!(
            map_action_from_text("resume chat"),
            Some(ActionOrUtility::Action(ActionName::Resume))
        ));
        assert!(matches!(
            map_action_from_text("/h"),
            Some(ActionOrUtility::Help)
        ));
        assert!(matches!(
            map_action_from_text("start"),
            Some(ActionOrUtility::Start)
        ));
    }
}
