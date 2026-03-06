mod cli;
mod config;

use cli::Cli;
use config::Config;

fn main() {
    let cli = Cli::parse();
    let config = Config::load();
    cli.run(&config);
}
