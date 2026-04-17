use serde::Serialize;
use tokio::time::{sleep, Duration};

use crate::cli::Cli;
use crate::config::Config;

#[derive(Serialize)]
pub struct Report {
    pub command: String,
    pub project: String,
}

pub struct Runner<'a> {
    pub cli: &'a Cli,
    pub config: &'a Config,
}

impl<'a> Runner<'a> {
    pub fn new(cli: &'a Cli, config: &'a Config) -> Self {
        Self { cli, config }
    }

    pub async fn execute(&self) -> Report {
        sleep(Duration::from_millis(10)).await;
        Report {
            command: self.cli.command.clone(),
            project: self.config.name.clone(),
        }
    }
}
