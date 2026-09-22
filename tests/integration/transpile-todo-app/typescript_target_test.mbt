///|
/// Snapshot: typescript todo-app fixture lifted to canonical IR and
/// lowered back into TypeScript. The round-trip surfaces what the engine
/// CAN preserve mechanically vs. what depends on body content.
async test "snapshot: ts todo-app -> typescript (round-trip)" {
  @transpile-todo-app.run_target_snapshot("typescript")
}
