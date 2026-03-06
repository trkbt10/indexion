use axum::response::Json;
use serde_json::{json, Value};

pub async fn root() -> &'static str {
    "Hello, World!"
}

pub async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}
