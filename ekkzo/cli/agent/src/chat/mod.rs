pub mod adapters;
pub mod contracts;

pub fn run(provider_name: &str, args: &[String]) -> Result<(), String> {
    adapters::run_with_provider(provider_name, args)
}
