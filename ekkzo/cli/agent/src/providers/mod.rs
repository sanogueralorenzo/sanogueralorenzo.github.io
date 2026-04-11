mod mock;

pub trait Provider: Send + Sync {
    fn name(&self) -> &'static str;
}

pub fn available_provider_names() -> Vec<&'static str> {
    vec!["mock"]
}

pub fn create_provider(name: &str) -> Option<Box<dyn Provider>> {
    match name {
        "mock" => Some(Box::new(mock::MockProvider)),
        _ => None,
    }
}
