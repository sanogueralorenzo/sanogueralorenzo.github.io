use palette_indexer::Index;
use serde::Deserialize;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

#[derive(Deserialize)]
struct Request {
    query: String,
}

fn main() {
    let mut roots = Vec::new();
    let mut max_entries = 100_000usize;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--root" => {
                if let Some(root) = args.next() {
                    roots.push(PathBuf::from(root));
                }
            }
            "--max-entries" => {
                if let Some(value) = args.next() {
                    max_entries = value.parse().unwrap_or(max_entries);
                }
            }
            _ => {}
        }
    }

    let index = Index::build(&roots, max_entries);
    let stdin = io::stdin();
    for line in stdin.lock().lines().flatten() {
        let Ok(request) = serde_json::from_str::<Request>(&line) else {
            continue;
        };
        let results = index.search(&request.query);
        if let Ok(json) = serde_json::to_string(&results) {
            println!("{}", json);
            let _ = io::stdout().flush();
        }
    }
}
