///|
/// Snapshot: typescript todo-app fixture lifted to canonical IR and
/// lowered into MoonBit. Locks in unresolved-marker kinds + counts so
/// any regression in the lift/lower architecture is caught.
async test "snapshot: ts todo-app -> moonbit" {
  @transpile-todo-app.run_target_snapshot("moonbit")
}
