use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub name: String,
    pub port: u16,
    pub debug: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            name: "example".to_string(),
            port: 8080,
            debug: false,
        }
    }
}
