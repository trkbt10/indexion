mod config;
mod error;

pub use config::Config;
pub use error::Error;

pub fn init() -> Result<(), Error> {
    Ok(())
}
