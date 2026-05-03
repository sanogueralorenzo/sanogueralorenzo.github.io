pub(crate) mod adapters;
pub(crate) mod cli;
mod commands;
pub(crate) mod services;
pub(crate) mod shared;

use std::ffi::OsString;

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut normalized = Vec::with_capacity(args.len() + 1);
    normalized.push(OsString::from("codex-core sessions"));
    if args.first().and_then(|value| value.to_str()) == Some("sessions") {
        normalized.extend(args.into_iter().skip(1));
    } else {
        normalized.extend(args);
    }

    commands::run_from(normalized)
}
