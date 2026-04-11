use serde::Serialize;

#[derive(Serialize)]
pub struct ResultJson {
    status: String,
    exit_code: i32,
    thread_id: Option<String>,
    final_message: String,
    stderr: String,
}

impl ResultJson {
    pub fn from_execution(
        exit_code: i32,
        thread_id: Option<String>,
        final_message: String,
        stderr: String,
    ) -> Self {
        Self {
            status: if exit_code == 0 {
                "completed".to_string()
            } else {
                "failed".to_string()
            },
            exit_code,
            thread_id,
            final_message,
            stderr,
        }
    }
}
