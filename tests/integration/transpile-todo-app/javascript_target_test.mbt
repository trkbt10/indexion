///|
/// Snapshot: typescript todo-app fixture lowered to JavaScript. Type
/// information is dropped at lower time (JS has none) — the snapshot
/// records this as a structural simplification, not a defect.
async test "snapshot: ts todo-app -> javascript" {
  @transpile-todo-app.run_target_snapshot("javascript")
}
