use serde::Deserialize;

#[derive(Deserialize)]
pub struct Config {
    pub name: String,
}

impl Config {
    pub fn load() -> Self {
        Config {
            name: "default".to_string(),
        }
    }
}
