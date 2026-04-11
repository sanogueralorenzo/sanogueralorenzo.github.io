use crate::noninteractive::cli::WrapperOptions;
use crate::noninteractive::output::cleanup_managed_file;
use std::fs;
use std::io::Read;
use std::path::Path;

pub fn load_prompt_bytes(
    options: &WrapperOptions,
    managed_output_last_message: bool,
    output_last_message: &Path,
) -> Result<Option<Vec<u8>>, u8> {
    if options.prompt_stdin {
        let mut buffer = Vec::new();
        if let Err(error) = std::io::stdin().read_to_end(&mut buffer) {
            eprintln!("Failed to read prompt from stdin: {error}");
            cleanup_managed_file(managed_output_last_message, output_last_message);
            return Err(1);
        }
        return Ok(Some(buffer));
    }

    let Some(path) = &options.prompt_file else {
        return Ok(None);
    };

    match fs::read(path) {
        Ok(contents) => Ok(Some(contents)),
        Err(error) => {
            eprintln!("Failed to read prompt file '{}': {error}", path.display());
            cleanup_managed_file(managed_output_last_message, output_last_message);
            Err(1)
        }
    }
}
