mod adapters;
mod cli;
mod commands;
mod services;
mod shared;

fn main() {
    if let Err(error) = commands::run() {
        eprintln!("Error: {error:#}");
        std::process::exit(1);
    }
}
