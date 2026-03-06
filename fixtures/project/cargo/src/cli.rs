use clap::Parser;

#[derive(Parser)]
pub struct Cli {
    pub command: String,
}

impl Cli {
    pub fn parse() -> Self {
        Parser::parse()
    }

    pub fn run(&self, config: &crate::config::Config) {
        println!("Running: {}", self.command);
    }
}
