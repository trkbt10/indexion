//! example-cli — library surface.
//!
//! The binary (`main.rs`) wires config + cli together; the library here
//! exposes the reusable pieces so downstream crates can embed them.

pub mod cli;
pub mod config;
pub mod runner;

pub use cli::Cli;
pub use config::Config;
pub use runner::Runner;
