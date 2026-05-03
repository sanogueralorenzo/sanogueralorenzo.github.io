use std::os::unix::process::ExitStatusExt;
use std::process::ExitStatus;

pub fn exit_code_from_status(status: &ExitStatus) -> u8 {
    if let Some(code) = status.code() {
        return u8::try_from(code).unwrap_or(1);
    }

    if let Some(signal) = status.signal() {
        return (128 + signal).clamp(0, 255) as u8;
    }

    1
}
