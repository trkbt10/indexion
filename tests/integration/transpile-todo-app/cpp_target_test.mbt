///|
/// Snapshot: typescript todo-app fixture lowered to C++. Tests the engine
/// against a target with both classes and templates.
async test "snapshot: ts todo-app -> cpp" {
  @transpile-todo-app.run_target_snapshot("cpp")
}
