use example_cli::{Cli, Config, Runner};

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let config = Config::load();
    let runner = Runner::new(&cli, &config);
    let report = runner.execute().await;
    println!("Running: {} in {}", report.command, report.project);
}
