use clap::Parser;
use example_core::{Config, init};

mod commands;

#[derive(Parser)]
#[command(name = "example", version, about)]
struct Cli {
    #[command(subcommand)]
    command: commands::Command,
}

fn main() -> Result<(), example_core::Error> {
    let cli = Cli::parse();
    init()?;
    commands::run(cli.command)
}
