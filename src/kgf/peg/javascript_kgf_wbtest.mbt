// Tests for the real javascript.kgf and javascript-jsx.kgf specs — regressions
// for multiline imports (same grammar bug as typescript). Loads the KGFs from
// disk so spec changes surface here intentionally.

///|
fn load_javascript_kgf() -> String {
  @fs.read_file_to_string("kgfs/programming/javascript.kgf") catch {
    _ => panic()
  }
}

///|
/// javascript-jsx extends javascript, so the raw file lacks the inherited
/// sections; resolve the inheritance the way the registry does.
fn load_javascript_jsx_spec() -> @types.KGFSpec {
  let jsx = @fs.read_file_to_string("kgfs/programming/javascript-jsx.kgf") catch {
    _ => panic()
  }
  let base = @parser.parse_kgf_source(load_javascript_kgf())
  @parser.parse_kgf_source(jsx).merge_onto(base).to_spec()
}

///|
fn run_javascript_pipeline(source : String) -> @graph.CodeGraph {
  run_full_pipeline(load_javascript_kgf(), source, "test.js")
}

///|
fn run_javascript_jsx_pipeline(source : String) -> @graph.CodeGraph {
  run_full_pipeline_spec(load_javascript_jsx_spec(), source, "test.jsx")
}

///|
fn js_module_deps(graph : @graph.CodeGraph) -> Array[String] {
  let result : Array[String] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      result.push(edge.attrs.get("via").unwrap_or(""))
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Multiline `import { ... }` — same bug as typescript, verified fixed.
// ---------------------------------------------------------------------------

///|
test "javascript kgf: multiline import { ... } parses into dependency edge" {
  let source =
    #|import {
    #|  one,
    #|  two,
    #|} from "./mod";
  let graph = run_javascript_pipeline(source)
  let deps = js_module_deps(graph)
  assert_true(deps.iter().any(fn(v) { v == "./mod" }))
}

///|
test "javascript kgf: multiline default+named import" {
  let source =
    #|import Default, {
    #|  one,
    #|  two
    #|} from "./mod";
  let graph = run_javascript_pipeline(source)
  let deps = js_module_deps(graph)
  assert_true(deps.iter().any(fn(v) { v == "./mod" }))
}

///|
test "javascript-jsx kgf: multiline import { ... } parses into dependency edge" {
  let source =
    #|import {
    #|  one,
    #|  two,
    #|} from "./mod";
  let graph = run_javascript_jsx_pipeline(source)
  let deps = js_module_deps(graph)
  assert_true(deps.iter().any(fn(v) { v == "./mod" }))
}
