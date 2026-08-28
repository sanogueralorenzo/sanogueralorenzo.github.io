mod cli;
mod command;
mod help;
mod output;
mod prompt;
mod result;
mod runner;

use std::ffi::OsString;

use crate::noninteractive::cli::parse_wrapper_options;
use crate::noninteractive::help::{
    print_noninteractive_command_help, print_noninteractive_subcommand_help,
};
use crate::noninteractive::runner::run_wrapper;

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut iter = args.into_iter();
    let Some(command) = iter.next() else {
        print_noninteractive_command_help();
        return 0;
    };
    if command.to_string_lossy() != "noninteractive" {
        eprintln!("Internal error: expected 'noninteractive' route.");
        return 1;
    }

    let tail: Vec<OsString> = iter.collect();
    let Some(subcommand_raw) = tail.first() else {
        print_noninteractive_command_help();
        return 0;
    };

    let subcommand = subcommand_raw.to_string_lossy();
    if subcommand == "--help" || subcommand == "-h" {
        if tail.len() > 1 {
            eprintln!(
                "Unexpected arguments for noninteractive --help: {}",
                join_args(&tail[1..])
            );
            return 1;
        }
        print_noninteractive_command_help();
        return 0;
    }

    let mode = match subcommand.as_ref() {
        "run" | "resume" | "review" => subcommand.into_owned(),
        other => {
            eprintln!("Unknown noninteractive command: {other}");
            return 1;
        }
    };

    let wrapper_tail = &tail[1..];
    if let Some(first) = wrapper_tail.first() {
        let value = first.to_string_lossy();
        if value == "--help" || value == "-h" {
            if wrapper_tail.len() > 1 {
                eprintln!(
                    "Unexpected arguments for noninteractive {} --help: {}",
                    mode,
                    join_args(&wrapper_tail[1..])
                );
                return 1;
            }
            print_noninteractive_subcommand_help(&mode);
            return 0;
        }
    }

    let options = match parse_wrapper_options(wrapper_tail) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("{message}");
            return 1;
        }
    };

    run_wrapper(&mode, options)
}

fn join_args(args: &[OsString]) -> String {
    args.iter()
        .map(|value| value.to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join(" ")
}
