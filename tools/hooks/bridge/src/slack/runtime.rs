use super::{
    config::{Config, Event},
    conversation::Conversation,
    errors::{HookError, WorkResult},
    process::{self, Cancel},
    storage::{Job, Request, Storage, job_id, thread_key},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    path::Path,
    sync::{Arc, Mutex},
};
use tokio::sync::{Notify, Semaphore, broadcast, watch};

struct Item {
    job: Job,
    cancel: Cancel,
}
struct Inner {
    storage: Storage,
    queues: HashMap<String, VecDeque<Item>>,
    cancels: HashMap<String, Cancel>,
    closed: bool,
    last_error: Option<HookError>,
}
pub struct Runtime {
    pub config: Config,
    inner: Mutex<Inner>,
    pub events: broadcast::Sender<Value>,
    limit: Semaphore,
    idle: Notify,
}
impl Runtime {
    pub fn new(config: Config, folder: &Path) -> Result<Arc<Self>, String> {
        let storage = Storage::open(folder)?;
        let (events, _) = broadcast::channel(128);
        Ok(Arc::new(Self {
            config,
            inner: Mutex::new(Inner {
                storage,
                queues: HashMap::new(),
                cancels: HashMap::new(),
                closed: false,
                last_error: None,
            }),
            events,
            limit: Semaphore::new(8),
            idle: Notify::new(),
        }))
    }
    fn queue(inner: &mut Inner, job: Job) -> bool {
        let (cancel, _) = watch::channel(false);
        inner.cancels.insert(job.id.clone(), cancel.clone());
        let new = !inner.queues.contains_key(&job.thread);
        inner
            .queues
            .entry(job.thread.clone())
            .or_default()
            .push_back(Item { job, cancel });
        new
    }
    fn spawn(self: &Arc<Self>, thread: String) {
        let runtime = self.clone();
        tokio::spawn(async move {
            runtime.drain(thread).await;
        });
    }
    pub fn resume(self: &Arc<Self>) -> Result<(), String> {
        let mut inner = self.inner.lock().unwrap();
        let requests = inner.storage.queued()?;
        let mut threads = Vec::new();
        for job in requests {
            let thread = job.thread.clone();
            if Self::queue(&mut inner, job) {
                threads.push(thread);
            }
        }
        drop(inner);
        for thread in threads {
            self.spawn(thread);
        }
        Ok(())
    }
    pub fn recover(&self, value: Value) -> Result<Value, String> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Scope {
            team: String,
            user: String,
        }
        let scope: Scope = serde_json::from_value(value).map_err(|_| "Invalid recovery scope")?;
        let jobs = self.inner.lock().unwrap().storage.recover(&scope.team,&scope.user)?
            .into_iter().map(|job| json!({
                "job":job.id,
                "stop":job.input.request.eq_ignore_ascii_case("stop"),
                "event":{"channel":job.input.event.channel,"ts":job.input.event.ts,"thread_ts":job.input.event.thread_ts},
            })).collect::<Vec<_>>();
        Ok(json!({"jobs":jobs}))
    }
    pub fn history(&self, value: Value) -> Result<Value, String> {
        let event: Event = serde_json::from_value(value).map_err(|_| "Invalid message envelope")?;
        event.validate()?;
        let (command, project, _) = self.config.route(&event.text)?;
        let thread = thread_key(&event);
        let inner = self.inner.lock().unwrap();
        let conversation = Conversation::select(
            inner.storage.session(&thread)?,
            &command,
            project.as_deref(),
            &self.config.workspace,
        );
        let pending = inner.storage.pending(&thread)?;
        Ok(json!({"after":conversation.history_after(&pending)}))
    }
    pub fn status(&self, job: &str) -> Result<Option<Value>, String> {
        self.inner.lock().unwrap().storage.status(job)
    }
    pub fn last_error(&self) -> Value {
        self.inner
            .lock()
            .unwrap()
            .last_error
            .as_ref()
            .map(HookError::public)
            .unwrap_or(Value::Null)
    }
    pub fn submit(self: &Arc<Self>, value: Value) -> Result<Value, String> {
        let event: Event = serde_json::from_value(value).map_err(|_| "Invalid message envelope")?;
        event.validate()?;
        let id = job_id(&event);
        let thread = thread_key(&event);
        let mut inner = self.inner.lock().unwrap();
        if inner.closed {
            return Err("Bridge is stopping".into());
        }
        if let Some(previous) = inner.storage.status(&id)? {
            return Ok(previous);
        }
        let (command, project, request) = self.config.route(&event.text)?;
        let input = Request {
            event,
            command,
            project,
            request,
            workspace: self.config.workspace.clone(),
        };
        if input.request.eq_ignore_ascii_case("stop") {
            let stopped = inner.storage.stop(&id, &thread, &input)?;
            for job in stopped {
                if let Some(cancel) = inner.cancels.get(&job) {
                    cancel.send_replace(true);
                }
                let _ = self.events.send(json!({"type":"job","job":job}));
            }
            return inner
                .storage
                .status(&id)?
                .ok_or("Stop receipt is missing".into());
        }
        inner.storage.admit(&id, &thread, &input)?;
        let new = Self::queue(
            &mut inner,
            Job {
                id: id.clone(),
                thread: thread.clone(),
                input,
            },
        );
        drop(inner);
        if new {
            self.spawn(thread);
        }
        Ok(json!({"job":id,"status":"queued"}))
    }
    async fn drain(self: Arc<Self>, thread: String) {
        let _permit = self.limit.acquire().await.unwrap();
        loop {
            let item = {
                let mut inner = self.inner.lock().unwrap();
                let queue = inner.queues.get_mut(&thread).unwrap();
                match queue.pop_front() {
                    Some(item) => item,
                    None => {
                        inner.queues.remove(&thread);
                        return;
                    }
                }
            };
            if let Err(error) = self.run(&item).await {
                let mut inner = self.inner.lock().unwrap();
                let error = if inner.closed {
                    HookError::new("interrupted")
                } else {
                    error
                };
                if !*item.cancel.borrow() || inner.closed {
                    eprintln!("{}", error.public()["message"].as_str().unwrap());
                    inner.last_error = Some(error.clone());
                    if let Err(message) = inner.storage.fail(&item.job.id, &error) {
                        eprintln!("{message}");
                    }
                }
            }
            self.inner.lock().unwrap().cancels.remove(&item.job.id);
            let _ = self.events.send(json!({"type":"job","job":item.job.id}));
            self.idle.notify_one();
        }
    }
    async fn run(&self, item: &Item) -> WorkResult<()> {
        if *item.cancel.borrow() {
            return Ok(());
        }
        let job = &item.job;
        let input = &job.input;
        let (conversation, known) = {
            let inner = self.inner.lock().unwrap();
            if inner.closed {
                return Ok(());
            }
            if !inner
                .storage
                .start(&job.id)
                .map_err(|_| HookError::new("command_failed"))?
            {
                return Ok(());
            }
            let saved = inner
                .storage
                .session(&job.thread)
                .map_err(|_| HookError::new("command_failed"))?;
            let conversation = Conversation::select(
                saved,
                &input.command,
                input.project.as_deref(),
                &input.workspace,
            );
            let known = inner
                .storage
                .known_replies(
                    &job.thread,
                    conversation.resume().map(|s| s.session_id.as_str()),
                )
                .map_err(|_| HookError::new("command_failed"))?;
            (conversation, known)
        };
        let prompt = conversation.prompt(input, &known)?;
        let reply = process::execute(
            &input.command,
            &prompt,
            &conversation.workspace,
            conversation.resume().map(|s| s.session_id.as_str()),
            &item.cancel,
            |returned| {
                self.inner
                    .lock()
                    .unwrap()
                    .storage
                    .checkpoint(&job.id, &job.thread, &conversation.checkpoint(returned))
                    .map_err(|_| HookError::new("command_failed"))
            },
        )
        .await?;
        let session = conversation.completed(&reply.session, &input.event.ts);
        let answer = conversation.answer(reply);
        let mut inner = self.inner.lock().unwrap();
        if *item.cancel.borrow() {
            return Ok(());
        }
        inner
            .storage
            .complete(&job.id, &job.thread, &session, &answer)
            .map_err(|_| HookError::new("command_failed"))?;
        inner.last_error = None;
        Ok(())
    }
    pub fn claim(&self, job: &str) -> Result<Value, String> {
        Ok(json!({"claimed":self.inner.lock().unwrap().storage.claim(job)?}))
    }
    pub fn delivered(&self, job: &str, ts: &str) -> Result<Value, String> {
        if !super::config::timestamp(ts) {
            return Err("Invalid reply timestamp".into());
        }
        Ok(json!({"ok":self.inner.lock().unwrap().storage.delivered(job,ts)?}))
    }
    pub async fn close(&self) {
        {
            let mut inner = self.inner.lock().unwrap();
            inner.closed = true;
            for cancel in inner.cancels.values() {
                cancel.send_replace(true);
            }
        }
        loop {
            let notified = self.idle.notified();
            if self.inner.lock().unwrap().cancels.is_empty() {
                break;
            }
            notified.await;
        }
    }
}
