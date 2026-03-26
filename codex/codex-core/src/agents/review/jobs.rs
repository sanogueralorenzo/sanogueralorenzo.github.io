use super::PullRequestReference;
use super::ReviewJobOutput;
use super::ReviewJobSnapshot;
use super::ReviewJobStatus;
use super::ReviewMenuState;
use super::ReviewRunResult;
use crate::agents::StateLayout;
use crate::agents::now_utc;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ReviewJobEvent {
    timestamp: String,
    kind: String,
    step: String,
    message: String,
}

pub(super) struct ReviewJobStore {
    pub(super) snapshot: ReviewJobSnapshot,
    job_path: PathBuf,
    events_path: PathBuf,
}

pub(super) fn run_review_step<T, F>(
    job: &mut ReviewJobStore,
    status: ReviewJobStatus,
    step: &str,
    message: &str,
    operation: F,
) -> Result<T>
where
    F: FnOnce() -> Result<T>,
{
    job.set_status(status, step, message)?;
    match operation() {
        Ok(value) => Ok(value),
        Err(error) => {
            job.fail(step, &error)?;
            Err(error)
        }
    }
}

impl ReviewJobStore {
    pub(super) fn create(
        layout: &StateLayout,
        pull_request: &str,
        pr_ref: &PullRequestReference,
    ) -> Result<Self> {
        let id = Uuid::new_v4().to_string();
        let review_dir = layout.root.join("reviews").join(&id);
        fs::create_dir_all(&review_dir)
            .with_context(|| format!("failed to create {}", review_dir.display()))?;

        let snapshot = ReviewJobSnapshot {
            id,
            pull_request: pull_request.to_string(),
            owner: pr_ref.owner.clone(),
            repo: pr_ref.repo.clone(),
            number: pr_ref.number,
            url: None,
            status: ReviewJobStatus::Queued,
            current_step: "queued".to_string(),
            created_at: now_utc(),
            started_at: None,
            finished_at: None,
            posted_comments: 0,
            failed_comments: 0,
            failed_comment_details: Vec::new(),
            summary: None,
            error: None,
        };
        let job_path = review_dir.join("job.json");
        let events_path = review_dir.join("events.jsonl");
        let store = Self {
            snapshot,
            job_path,
            events_path,
        };
        store.write_snapshot()?;
        store.append_event("queued", "queued", "Review job created.")?;
        Ok(store)
    }

    pub(super) fn set_pull_request_url(&mut self, url: &str) -> Result<()> {
        self.snapshot.url = Some(url.to_string());
        self.write_snapshot()
    }

    fn set_status(&mut self, status: ReviewJobStatus, step: &str, message: &str) -> Result<()> {
        if self.snapshot.started_at.is_none() && status != ReviewJobStatus::Queued {
            self.snapshot.started_at = Some(now_utc());
        }
        self.snapshot.status = status;
        self.snapshot.current_step = step.to_string();
        self.write_snapshot()?;
        self.append_event("step", step, message)
    }

    pub(super) fn complete(
        &mut self,
        result: &ReviewRunResult,
        completion_step: &str,
    ) -> Result<()> {
        self.snapshot.status = ReviewJobStatus::Completed;
        self.snapshot.current_step = completion_step.to_string();
        self.snapshot.finished_at = Some(now_utc());
        self.snapshot.posted_comments = result.posted_comments;
        self.snapshot.failed_comments = result.failed_comments;
        self.snapshot.failed_comment_details = result.failed_comment_details.clone();
        self.snapshot.summary = Some(result.summary.clone());
        self.snapshot.error = None;
        self.snapshot.url = Some(result.url.clone());
        self.write_snapshot()?;
        self.append_event("completed", completion_step, "Review job completed.")
    }

    fn fail(&mut self, step: &str, error: &anyhow::Error) -> Result<()> {
        self.snapshot.status = ReviewJobStatus::Failed;
        self.snapshot.current_step = step.to_string();
        if self.snapshot.started_at.is_none() {
            self.snapshot.started_at = Some(now_utc());
        }
        self.snapshot.finished_at = Some(now_utc());
        self.snapshot.error = Some(error.to_string());
        self.write_snapshot()?;
        self.append_event("failed", step, &error.to_string())
    }

    fn write_snapshot(&self) -> Result<()> {
        let payload = serde_json::to_string_pretty(&self.snapshot)
            .context("failed to serialize review job snapshot")?;
        fs::write(&self.job_path, payload)
            .with_context(|| format!("failed to write {}", self.job_path.display()))
    }

    fn append_event(&self, kind: &str, step: &str, message: &str) -> Result<()> {
        let event = ReviewJobEvent {
            timestamp: now_utc(),
            kind: kind.to_string(),
            step: step.to_string(),
            message: message.to_string(),
        };
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.events_path)
            .with_context(|| format!("failed to open {}", self.events_path.display()))?;
        let payload =
            serde_json::to_string(&event).context("failed to serialize review job event")?;
        writeln!(file, "{payload}")
            .with_context(|| format!("failed to write {}", self.events_path.display()))
    }
}

pub(super) fn list_review_jobs_data(layout: &StateLayout) -> Result<Vec<ReviewJobSnapshot>> {
    let reviews_dir = layout.root.join("reviews");
    if !reviews_dir.exists() {
        return Ok(Vec::new());
    }

    let mut jobs = Vec::new();
    for entry in fs::read_dir(&reviews_dir)
        .with_context(|| format!("failed to read {}", reviews_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let job_path = path.join("job.json");
        if !job_path.exists() {
            continue;
        }
        jobs.push(load_review_job_snapshot(&job_path)?);
    }

    jobs.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(jobs)
}

pub(super) fn load_review_job_data(
    layout: &StateLayout,
    review_id: &str,
) -> Result<ReviewJobSnapshot> {
    let review_id = review_id.trim();
    if review_id.is_empty() {
        anyhow::bail!("Missing review job id");
    }
    let job_path = layout.root.join("reviews").join(review_id).join("job.json");
    if !job_path.exists() {
        anyhow::bail!("Review job not found: {review_id}");
    }
    load_review_job_snapshot(&job_path)
}

fn load_review_job_snapshot(job_path: &Path) -> Result<ReviewJobSnapshot> {
    let content = fs::read_to_string(job_path)
        .with_context(|| format!("failed to read {}", job_path.display()))?;
    serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", job_path.display()))
}

pub(super) fn into_review_job_output(job: ReviewJobSnapshot) -> ReviewJobOutput {
    let status = derive_review_menu_state(&job);
    ReviewJobOutput {
        id: job.id,
        pull_request: job.pull_request,
        owner: job.owner,
        repo: job.repo,
        number: job.number,
        url: job.url,
        status,
        current_step: job.current_step,
        created_at: job.created_at,
        started_at: job.started_at,
        finished_at: job.finished_at,
        posted_comments: job.posted_comments,
        failed_comments: job.failed_comments,
        failed_comment_details: job.failed_comment_details,
        summary: job.summary,
        error: job.error,
    }
}

pub(super) fn review_menu_state_label(menu_state: &ReviewMenuState) -> &'static str {
    match menu_state {
        ReviewMenuState::Published => "published",
        ReviewMenuState::NeedsAttention => "needs_attention",
        ReviewMenuState::InProgress => "in_progress",
    }
}

fn derive_review_menu_state(job: &ReviewJobSnapshot) -> ReviewMenuState {
    match job.status {
        ReviewJobStatus::Queued | ReviewJobStatus::Running | ReviewJobStatus::PostingComments => {
            ReviewMenuState::InProgress
        }
        ReviewJobStatus::Failed => ReviewMenuState::NeedsAttention,
        ReviewJobStatus::Completed => {
            if job.current_step == "pending_review_created" {
                ReviewMenuState::InProgress
            } else if job.failed_comments > 0 {
                ReviewMenuState::NeedsAttention
            } else {
                ReviewMenuState::Published
            }
        }
    }
}

pub(super) fn review_job_output_summary_label(job: &ReviewJobOutput) -> String {
    let base = format!("{}/{}#{}", job.owner, job.repo, job.number);
    match &job.summary {
        Some(summary) if !summary.trim().is_empty() => format!("{base} {summary}"),
        _ => base,
    }
}

#[cfg(test)]
mod tests {
    use super::super::ReviewCommentFailure;
    use super::*;

    #[test]
    fn loads_review_jobs_newest_first() {
        let root = unique_test_dir();
        let reviews_dir = root.join("reviews");
        fs::create_dir_all(reviews_dir.join("first")).unwrap();
        fs::create_dir_all(reviews_dir.join("second")).unwrap();

        fs::write(
            reviews_dir.join("first").join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "first".to_string(),
                pull_request: "owner/repo#1".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 1,
                url: None,
                status: ReviewJobStatus::Completed,
                current_step: "completed".to_string(),
                created_at: "2026-01-01T00:00:00Z".to_string(),
                started_at: None,
                finished_at: None,
                posted_comments: 1,
                failed_comments: 0,
                failed_comment_details: Vec::new(),
                summary: None,
                error: None,
            })
            .unwrap(),
        )
        .unwrap();
        fs::write(
            reviews_dir.join("second").join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "second".to_string(),
                pull_request: "owner/repo#2".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 2,
                url: None,
                status: ReviewJobStatus::Running,
                current_step: "running_codex_exec".to_string(),
                created_at: "2026-01-02T00:00:00Z".to_string(),
                started_at: None,
                finished_at: None,
                posted_comments: 0,
                failed_comments: 0,
                failed_comment_details: Vec::new(),
                summary: None,
                error: None,
            })
            .unwrap(),
        )
        .unwrap();

        let layout = StateLayout {
            root: root.clone(),
            tasks_dir: root.join("tasks"),
            config_file: root.join("config.json"),
        };

        let jobs = list_review_jobs_data(&layout).unwrap();
        assert_eq!(jobs.len(), 2);
        assert_eq!(jobs[0].id, "second");
        assert_eq!(jobs[1].id, "first");

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn loads_one_review_job_by_id() {
        let root = unique_test_dir();
        let review_dir = root.join("reviews").join("job-123");
        fs::create_dir_all(&review_dir).unwrap();
        fs::write(
            review_dir.join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "job-123".to_string(),
                pull_request: "owner/repo#3".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 3,
                url: Some("https://github.com/owner/repo/pull/3".to_string()),
                status: ReviewJobStatus::Failed,
                current_step: "posting_comments".to_string(),
                created_at: "2026-01-03T00:00:00Z".to_string(),
                started_at: Some("2026-01-03T00:00:01Z".to_string()),
                finished_at: Some("2026-01-03T00:00:02Z".to_string()),
                posted_comments: 0,
                failed_comments: 1,
                failed_comment_details: vec![ReviewCommentFailure {
                    title: "Example".to_string(),
                    path: Some("src/lib.rs".to_string()),
                    start_line: 10,
                    end_line: 10,
                    reason: "No changed diff line matched this finding on either side of the PR."
                        .to_string(),
                }],
                summary: Some("patch is incorrect".to_string()),
                error: Some("comment post failed".to_string()),
            })
            .unwrap(),
        )
        .unwrap();

        let layout = StateLayout {
            root: root.clone(),
            tasks_dir: root.join("tasks"),
            config_file: root.join("config.json"),
        };

        let job = load_review_job_data(&layout, "job-123").unwrap();
        assert_eq!(job.id, "job-123");
        assert_eq!(job.status, ReviewJobStatus::Failed);
        assert_eq!(job.failed_comment_details.len(), 1);

        let _ = fs::remove_dir_all(root);
    }

    fn unique_test_dir() -> PathBuf {
        std::env::temp_dir().join(format!("codex-core-review-tests-{}", Uuid::new_v4()))
    }
}
