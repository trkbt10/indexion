use clap::Subcommand;
use example_core::{Config, Error};

#[derive(Subcommand)]
pub enum Command {
    Init,
    Run { config: Option<String> },
}

pub fn run(cmd: Command) -> Result<(), Error> {
    match cmd {
        Command::Init => {
            println!("Initialized");
            Ok(())
        }
        Command::Run { config } => {
            let cfg = Config::default();
            println!("Running with config: {:?}", cfg);
            Ok(())
        }
    }
}
