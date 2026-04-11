use super::Provider;

pub struct GoogleProvider;

impl Provider for GoogleProvider {
    fn name(&self) -> &'static str {
        "google"
    }
}
