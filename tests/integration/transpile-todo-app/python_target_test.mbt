///|
/// Snapshot: typescript todo-app fixture lowered into Python. Same engine,
/// different lower spec — the snapshot diff vs. the moonbit one should
/// reflect Python's structural differences, not engine logic.
async test "snapshot: ts todo-app -> python" {
  @transpile-todo-app.run_target_snapshot("python")
}
