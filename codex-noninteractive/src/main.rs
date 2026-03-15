mod cli;
mod runner;

fn main() {
    if let Err(error) = runner::run() {
        eprintln!("Error: {error:#}");
        std::process::exit(1);
    }
}
