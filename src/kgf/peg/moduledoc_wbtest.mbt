// Tests for ModuleDoc disambiguation using the REAL moonbit.kgf spec.
// These tests load kgfs/programming/moonbit.kgf and verify doc comment association
// against actual MoonBit source code fixtures.
// If the KGF spec changes, these tests will break — that's intentional.

///|
/// Load the real MoonBit KGF spec from disk.
fn load_moonbit_kgf() -> String {
  @fs.read_file_to_string("kgfs/programming/moonbit.kgf") catch {
    _ => panic()
  }
}

///|
/// Run the full KGF pipeline with the real MoonBit spec.
fn run_moonbit_pipeline(source : String) -> @graph.CodeGraph {
  run_full_pipeline(load_moonbit_kgf(), source, "test.mbt")
}

///|
/// Extract declares edges as (name, kind, doc) tuples from a graph.
fn get_declares_edges(
  graph : @graph.CodeGraph,
) -> Array[(String, String, String)] {
  let result : Array[(String, String, String)] = []
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares {
      let name = edge.attrs.get("name").unwrap_or("")
      let kind = edge.attrs.get("kind").unwrap_or("")
      let doc = edge.attrs.get("doc").unwrap_or("")
      result.push((name, kind, doc))
    }
  }
  result
}

///|
/// Find a declares edge by name.
fn find_edge(
  edges : Array[(String, String, String)],
  name : String,
) -> (String, String, String)? {
  edges.iter().find_first(fn(e) { e.0 == name })
}

// ---------------------------------------------------------------------------
// Fixture: doc block immediately before declaration → declaration doc
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: doc block before pub fn is declaration doc, not ModuleDoc" {
  let source =
    #|///|
    #|/// Simple glob pattern matching.
    #|pub fn glob_match(path : String, pattern : String) -> Bool {
    #|  true
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "glob_match")
  // The doc comment must be attached to the function declaration
  assert_true(edge is Some(_))
  assert_true(edge.unwrap().2.contains("Simple glob pattern matching"))
  // No ModuleDoc note should exist
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 0)
}

///|
test "moonbit kgf: doc block before pub struct is declaration doc, not ModuleDoc" {
  let source =
    #|///|
    #|/// PEG represents a compiled PEG grammar.
    #|pub struct PEG {
    #|  tokens : Int
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "PEG")
  assert_true(edge is Some(_))
  assert_true(edge.unwrap().2.contains("PEG represents a compiled PEG grammar"))
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 0)
}

///|
test "moonbit kgf: doc block before pub enum is declaration doc, not ModuleDoc" {
  let source =
    #|///|
    #|/// Detected operating system platform.
    #|pub enum Platform {
    #|  MacOS
    #|  Linux
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "Platform")
  assert_true(edge is Some(_))
  assert_true(edge.unwrap().2.contains("Detected operating system platform"))
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 0)
}

// ---------------------------------------------------------------------------
// Fixture: doc block + blank line → ModuleDoc, then declaration with own doc
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: doc block with blank line is ModuleDoc, declaration keeps own doc" {
  let source =
    #|///|
    #|/// Platform detection and OS-level primitives.
    #|/// Pure OS knowledge.
    #|
    #|///|
    #|/// Detected operating system platform.
    #|pub enum Platform {
    #|  MacOS
    #|  Linux
    #|}
  let graph = run_moonbit_pipeline(source)
  // ModuleDoc should capture the first block
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 1)
  assert_true(notes[0].content.contains("Platform detection"))
  assert_true(notes[0].content.contains("Pure OS knowledge"))
  // Declaration should have its own doc
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "Platform")
  assert_true(edge is Some(_))
  assert_true(edge.unwrap().2.contains("Detected operating system platform"))
}

// ---------------------------------------------------------------------------
// Fixture: multiple declarations each keep their own doc
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: multiple pub fn declarations each keep their own doc" {
  let source =
    #|///|
    #|/// First function documentation.
    #|pub fn first() -> Unit {
    #|  ()
    #|}
    #|
    #|///|
    #|/// Second function documentation.
    #|pub fn second() -> Unit {
    #|  ()
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let first = find_edge(edges, "first")
  let second = find_edge(edges, "second")
  assert_true(first is Some(_))
  assert_true(second is Some(_))
  assert_true(first.unwrap().2.contains("First function documentation"))
  assert_true(second.unwrap().2.contains("Second function documentation"))
  // No ModuleDoc (both blocks are attached to declarations)
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 0)
}

// ---------------------------------------------------------------------------
// Fixture: undocumented declaration has empty doc
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: declaration without doc comment has empty doc attr" {
  let source =
    #|///|
    #|/// Documented function.
    #|pub fn documented() -> Unit {
    #|  ()
    #|}
    #|
    #|pub fn undocumented() -> Unit {
    #|  ()
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let documented = find_edge(edges, "documented")
  let undocumented = find_edge(edges, "undocumented")
  assert_true(documented is Some(_))
  assert_true(undocumented is Some(_))
  assert_true(documented.unwrap().2.contains("Documented function"))
  assert_eq(undocumented.unwrap().2, "")
}

// ---------------------------------------------------------------------------
// Fixture: standalone doc block (file has only module doc, no declarations)
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: standalone doc block becomes ModuleDoc" {
  let source =
    #|///|
    #|/// This is a standalone module overview.
    #|
    #|
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  // No declaration edges (filtered: Documentation kind from StandaloneDoc is not a real decl)
  let real_edges = edges
    .iter()
    .filter(fn(e) { e.1 != "Documentation" })
    .collect()
  assert_eq(real_edges.length(), 0)
  // ModuleDoc note should exist
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 1)
  assert_true(notes[0].content.contains("standalone module overview"))
}

// ---------------------------------------------------------------------------
// Fixture: realistic file with module doc + mixed declaration types
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: realistic file with module doc and mixed declarations" {
  let source =
    #|///|
    #|/// MCP type definitions.
    #|/// Core types for the protocol.
    #|
    #|///|
    #|/// JSON Schema for input parameters.
    #|pub struct InputSchema {
    #|  properties : Int
    #|}
    #|
    #|///|
    #|/// Create a new schema.
    #|pub fn new_schema() -> Unit {
    #|  ()
    #|}
    #|
    #|///|
    #|/// Protocol version enum.
    #|pub enum Version {
    #|  V1
    #|  V2
    #|}
  let graph = run_moonbit_pipeline(source)
  // ModuleDoc
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 1)
  assert_true(notes[0].content.contains("MCP type definitions"))
  assert_true(notes[0].content.contains("Core types for the protocol"))
  // Declarations
  let edges = get_declares_edges(graph)
  let schema = find_edge(edges, "InputSchema")
  let new_fn = find_edge(edges, "new_schema")
  let version = find_edge(edges, "Version")
  assert_true(schema is Some(_))
  assert_true(new_fn is Some(_))
  assert_true(version is Some(_))
  assert_true(schema.unwrap().2.contains("JSON Schema for input parameters"))
  assert_true(new_fn.unwrap().2.contains("Create a new schema"))
  assert_true(version.unwrap().2.contains("Protocol version enum"))
}

// ---------------------------------------------------------------------------
// Fixture: ///| marker only (no /// text lines) before declaration
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: bare doc marker before declaration is not ModuleDoc" {
  let source =
    #|///|
    #|pub fn marker_only() -> Unit {
    #|  ()
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "marker_only")
  assert_true(edge is Some(_))
  // Doc is empty because ///| has skip_value and there are no DocLine tokens
  assert_eq(edge.unwrap().2, "")
  // Not captured as ModuleDoc
  let notes = graph.get_notes("module_doc", "test.mbt")
  assert_eq(notes.length(), 0)
}

// ---------------------------------------------------------------------------
// Fixture: multi-line doc comment preserved in full
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: multi-line doc comment text is fully preserved" {
  let source =
    #|///|
    #|/// Simple glob pattern matching.
    #|/// Supports:
    #|/// - * matches any sequence of characters
    #|/// - ** matches any sequence including /
    #|/// - ? matches single character
    #|pub fn glob_match(path : String) -> Bool {
    #|  true
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "glob_match")
  assert_true(edge is Some(_))
  let doc = edge.unwrap().2
  assert_true(doc.contains("Simple glob pattern matching"))
  assert_true(doc.contains("Supports:"))
  assert_true(doc.contains("* matches any sequence of characters"))
  assert_true(doc.contains("? matches single character"))
}

// ---------------------------------------------------------------------------
// Fixture: exact doc text after trim — no leading/trailing whitespace
// ---------------------------------------------------------------------------

///|
test "moonbit kgf: single-line doc text is trimmed exactly" {
  let source =
    #|///|
    #|/// Create a new value.
    #|pub fn new_value() -> Unit {
    #|  ()
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "new_value")
  assert_true(edge is Some(_))
  let doc = edge.unwrap().2
  // trim() in semantics strips leading \n and spaces from _text accumulation
  assert_eq(doc, "Create a new value.")
}

///|
test "moonbit kgf: multi-line doc preserves internal newlines" {
  let source =
    #|///|
    #|/// Line one.
    #|/// Line two.
    #|/// Line three.
    #|pub fn multi() -> Unit {
    #|  ()
    #|}
  let graph = run_moonbit_pipeline(source)
  let edges = get_declares_edges(graph)
  let edge = find_edge(edges, "multi")
  assert_true(edge is Some(_))
  let doc = edge.unwrap().2
  // trim() strips leading \n+space, internal structure preserved
  assert_eq(doc, "Line one.\n Line two.\n Line three.")
}
