#[derive(Clone, Copy)]
pub enum OutputFormat {
    Human,
    Plain,
    Json,
}

impl OutputFormat {
    pub fn from_flags(json: bool, plain: bool) -> Self {
        if json {
            return Self::Json;
        }
        if plain {
            return Self::Plain;
        }
        Self::Human
    }
}
