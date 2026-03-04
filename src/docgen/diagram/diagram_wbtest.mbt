// Tests for diagram module.

///|
test "generate_dep_diagram: creates valid mermaid" {
  let deps = [
    @query.ModuleDep::new("src/main.ts", "src/utils.ts"),
    @query.ModuleDep::new("src/main.ts", "src/config.ts"),
  ]
  let diagram = generate_dep_diagram(deps)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph LR"))
  assert_true(diagram.contains("-->"))
  assert_true(diagram.contains("```"))
}

///|
test "generate_dep_diagram: empty deps returns empty string" {
  let deps : Array[@query.ModuleDep] = []
  let diagram = generate_dep_diagram(deps)
  assert_eq(diagram, "")
}

///|
test "generate_dep_diagram: shortens module names" {
  let deps = [
    @query.ModuleDep::new("src/components/button.ts", "src/utils/helpers.ts"),
  ]
  let diagram = generate_dep_diagram(deps)
  assert_true(diagram.contains("button.ts"))
  assert_true(diagram.contains("helpers.ts"))
}

///|
test "generate_call_diagram: creates valid mermaid" {
  let calls = [
    @query.CallInfo::new("main::init", "utils::setup", "main.ts"),
    @query.CallInfo::new("main::init", "utils::run", "main.ts"),
  ]
  let diagram = generate_call_diagram(calls)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph TD"))
  assert_true(diagram.contains("-->"))
}

///|
test "generate_call_diagram: filters by focus" {
  let calls = [
    @query.CallInfo::new("a", "b", "file"),
    @query.CallInfo::new("b", "c", "file"),
    @query.CallInfo::new("x", "y", "file"),
  ]
  let diagram = generate_call_diagram(calls, focus=Some("b"))
  // Should include a->b and b->c but not x->y
  assert_true(diagram.contains("-->"))
}

///|
test "generate_call_diagram: empty calls returns empty string" {
  let calls : Array[@query.CallInfo] = []
  let diagram = generate_call_diagram(calls)
  assert_eq(diagram, "")
}

///|
test "generate_hierarchy_diagram: creates classDiagram" {
  let rels = [
    @query.TypeRelation::new("Dog", "Animal", "extends"),
    @query.TypeRelation::new("Cat", "Animal", "extends"),
    @query.TypeRelation::new("Dog", "Walkable", "implements"),
  ]
  let diagram = generate_hierarchy_diagram(rels)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("classDiagram"))
  assert_true(diagram.contains("<|--")) // extends arrow
  assert_true(diagram.contains("<|..")) // implements arrow
}

///|
test "generate_hierarchy_diagram: empty returns empty string" {
  let rels : Array[@query.TypeRelation] = []
  let diagram = generate_hierarchy_diagram(rels)
  assert_eq(diagram, "")
}

///|
test "shorten_module_name: keeps meaningful path segments" {
  // Skips src/ but keeps rest
  assert_eq(
    shorten_module_name("src/components/Button.tsx"),
    "components/Button.tsx",
  )
  assert_eq(shorten_module_name("utils"), "utils")
  // pkg: prefix is stripped, org/project/src skipped
  assert_eq(
    shorten_module_name("pkg:trkbt10/indexion/src/kgf/types"),
    "kgf/types",
  )
  // moon.pkg shows parent
  assert_eq(
    shorten_module_name("src/kgf/types/moon.pkg", source_patterns=["moon.pkg"]),
    "kgf/types",
  )
}

///|
test "shorten_symbol_name: extracts after ::" {
  assert_eq(shorten_symbol_name("file.ts::MyClass"), "MyClass")
  assert_eq(shorten_symbol_name("pkg::module::func"), "func")
  assert_eq(shorten_symbol_name("simple"), "simple")
}

///|
test "escape_mermaid: handles special chars" {
  let escaped = escape_mermaid("Hello[World]")
  assert_false(escaped.contains("["))
  assert_false(escaped.contains("]"))
}

///|
test "sanitize_class_name: keeps alphanumeric and underscore" {
  assert_eq(sanitize_class_name("MyClass_123"), "MyClass_123")
  assert_eq(sanitize_class_name("pkg::Type"), "pkgType")
}

///|
test "generate_dep_diagram_with_circular: includes circular refs" {
  let deps = [
    @query.ModuleDep::new("src/a.ts", "src/b.ts"),
    @query.ModuleDep::new("src/b.ts", "src/c.ts"),
  ]
  let circulars = [@query.CircularDep::new("src/c.ts", "src/a.ts")]
  let diagram = generate_dep_diagram_with_circular(deps, circulars)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("graph LR"))
  assert_true(diagram.contains("-->"))
  // Circular should have special arrow
  assert_true(diagram.contains("-.->|circular|"))
  // Should have red styling for circular edges
  assert_true(diagram.contains("stroke:red"))
}

///|
test "generate_dep_diagram_with_circular: only circulars" {
  let deps : Array[@query.ModuleDep] = []
  let circulars = [@query.CircularDep::new("src/a.ts", "src/b.ts")]
  let diagram = generate_dep_diagram_with_circular(deps, circulars)
  assert_true(diagram.contains("```mermaid"))
  assert_true(diagram.contains("-.->|circular|"))
}

///|
test "generate_dep_diagram_with_circular: empty returns empty" {
  let deps : Array[@query.ModuleDep] = []
  let circulars : Array[@query.CircularDep] = []
  let diagram = generate_dep_diagram_with_circular(deps, circulars)
  assert_eq(diagram, "")
}
