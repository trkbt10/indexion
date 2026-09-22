///|
/// Snapshot: typescript todo-app fixture lowered into Rust. Demonstrates
/// the engine has zero per-pair logic by reusing the same machinery for
/// a third target.
async test "snapshot: ts todo-app -> rust" {
  @transpile-todo-app.run_target_snapshot("rust")
}
