pub fn print_noninteractive_command_help() {
    println!("Usage:");
    println!("  codex-core noninteractive run|resume|review ...");
    println!();
    println!("Description:");
    println!("  Run standardized non-interactive Codex wrappers.");
    println!();
    println!("Subcommands:");
    println!("  run     Start a new codex exec turn with standardized wrapper output.");
    println!("  resume  Resume a codex exec thread with standardized wrapper output.");
    println!("  review  Run codex exec review with standardized wrapper output.");
}

pub fn print_noninteractive_subcommand_help(mode: &str) {
    match mode {
        "run" => {
            println!("Usage:");
            println!("  codex-core noninteractive run [wrapper-options] [-- codex-exec-options]");
            println!();
            println!("Description:");
            println!("  Runs `codex exec --json` with standardized wrapper behavior.");
        }
        "resume" => {
            println!("Usage:");
            println!(
                "  codex-core noninteractive resume [wrapper-options] [-- codex-exec-resume-options]"
            );
            println!();
            println!("Description:");
            println!("  Runs `codex exec resume --json` with standardized wrapper behavior.");
        }
        "review" => {
            println!("Usage:");
            println!(
                "  codex-core noninteractive review [wrapper-options] [-- codex-exec-review-options]"
            );
            println!();
            println!("Description:");
            println!("  Runs `codex exec review --json` with standardized wrapper behavior.");
        }
        _ => {
            print_noninteractive_command_help();
            return;
        }
    }

    println!();
    println!("Wrapper options:");
    println!("  --prompt <TEXT>        Prompt text");
    println!("  --prompt-file <PATH>   Read prompt from file");
    println!("  --prompt-stdin         Read prompt from stdin");
    println!("  --result-json <PATH>   Write normalized result JSON");
    println!("  -o, --output-last-message <PATH>");
    println!("                         Persist final message path (forwarded to codex)");
    println!("  --raw-jsonl            Print raw codex JSONL events to stdout");
    println!("  --emit-events          Mirror raw JSONL events to stderr");
    println!();
    println!("Notes:");
    println!("  - Prompt options are mutually exclusive.");
    println!("  - Remaining args are forwarded to upstream `codex exec` subcommands.");
}
