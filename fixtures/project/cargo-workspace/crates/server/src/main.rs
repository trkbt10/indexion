use axum::{routing::get, Router};
use example_core::Config;

mod handlers;

#[tokio::main]
async fn main() -> Result<(), example_core::Error> {
    let config = Config::default();

    let app = Router::new()
        .route("/", get(handlers::root))
        .route("/health", get(handlers::health));

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", config.port))
        .await
        .map_err(example_core::Error::Io)?;

    axum::serve(listener, app).await.map_err(example_core::Error::Io)
}
