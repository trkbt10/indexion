///|
/// Snapshot: typescript todo-app fixture lowered to C. C lacks generics,
/// so `Array<T>` mappings are CONVERSION-class. The snapshot captures
/// per-file emit_parse_errors against the C KGF spec.
async test "snapshot: ts todo-app -> c" {
  @transpile-todo-app.run_target_snapshot("c")
}
