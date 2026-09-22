///|
/// Regression tests for multi-token label reads in the KGF specs.
///
/// The PEG publishes two things for every grammar label (see `FLabel` in
/// `src/kgf/peg/eval_recursive.mbt`): `<label>`, the value of the LAST token
/// the capture matched, and `<label>_text`, the accumulated text of every
/// token it matched. For a capture that can only ever match one token the two
/// agree. For a capture bound to a RULE — a doc block, a dotted module path, a
/// hyphenated node name, a parenthesised operator — they do not, and reading
/// the bare label silently keeps the tail and drops everything in front of it.
///
/// Nothing fails at runtime: the label resolves, the edge is emitted, the
/// attribute is just wrong. `kgf check` reports each such read as a warning;
/// these tests pin the OBSERVABLE consequence of the fix, so the specs cannot
/// regress back to the truncating read without a test going red.
///
/// Two of the cases below are grammar bugs rather than label reads, kept here
/// because they were found by the same sweep: a PHP enum case that bound only
/// `Ident` so PascalCase names never matched, and a Haskell type rule with no
/// type application so a class body ended after its first method.
///
/// The helpers mirror those in `declares_wbtest.mbt` and carry an `lbl_`
/// prefix so the files can coexist in this package.

///|
/// Run the full KGF pipeline (lex, parse, semantics) on inline source and
/// return the resulting graph, or None when the parse fails outright.
fn lbl_graph(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> @graph.CodeGraph? {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return None }
  let start_rule = spec.get_start_rule()
  let parse_result = match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return None
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @semantics.SemEvalCtx::new(spec, graph, path, "", lang, fn(_) {
    false
  })
  for event in parse_result.get_events() {
    @semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  Some(graph)
}

///|
/// The declares edges of inline source as (from, name, kind, doc) tuples, in
/// emission order.
fn lbl_declares(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[(String, String, String, String)] {
  let result : Array[(String, String, String, String)] = []
  let graph = match lbl_graph(registry, lang, source, path) {
    Some(g) => g
    None => return result
  }
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    result.push(
      (
        edge.from,
        edge.attrs.get("name").unwrap_or(""),
        edge.attrs.get("kind").unwrap_or(""),
        edge.attrs.get("doc").unwrap_or(""),
      ),
    )
  }
  result
}

///|
/// The exact `doc` attribute recorded for one declared name, or "" when the
/// name has no declares edge. Unlike a `contains` check this pins the WHOLE
/// text, which is the point: a truncating read produced a doc that still
/// contained the last line.
fn lbl_doc_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in lbl_declares(registry, lang, source, path) {
    if row.1 == name {
      return row.3
    }
  }
  ""
}

///|
/// The `from` endpoint — the PARENT — of the declares edge for `name`, or ""
/// when nothing declares it.
fn lbl_parent_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in lbl_declares(registry, lang, source, path) {
    if row.1 == name {
      return row.0
    }
  }
  ""
}

///|
/// The declared names of inline source mapped to their `kind`.
fn lbl_names(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  for row in lbl_declares(registry, lang, source, path) {
    names.set(row.1, row.2)
  }
  names
}

///|
/// The `via` attrs of the moduleDependsOn edges of inline source, in order.
fn lbl_depends_via(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[String] {
  let result : Array[String] = []
  let graph = match lbl_graph(registry, lang, source, path) {
    Some(g) => g
    None => return result
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.ModuleDependsOn {
      result.push(edge.attrs.get("via").unwrap_or(""))
    }
  }
  result
}

// ─── Multi-line doc blocks ──────────────────────────────────

///|
/// A MoonBit `///` doc block is several DocLine tokens. The visibility guard
/// used to read the bare `$vis`, which for `pub(all)` is the closing paren —
/// truthy only by accident. Reading `$vis_text` keeps every form of the
/// modifier declaring, and the doc arrives whole rather than as its last line.
test "labels: moonbit pub(all) declares and keeps both doc lines" {
  let registry = get_fixture_registry()
  let source =
    #|///|
    #|/// First line of doc.
    #|/// Second line of doc.
    #|pub(all) struct Cfg {
    #|  name : String
    #|}
  let doc = lbl_doc_of(registry, "moonbit", source, "cfg.mbt", "Cfg")
  assert_eq(doc, "First line of doc.\n Second line of doc.")
}

///|
/// `pub(readonly)` and a bare `pub` are the other two shapes of the modifier,
/// and a declaration with NO modifier must stay out of the public surface.
test "labels: moonbit visibility forms all declare, private stays out" {
  let registry = get_fixture_registry()
  let source =
    #|///|
    #|pub(readonly) type Alias = Int
    #|
    #|///|
    #|pub fn run() -> Unit {
    #|  ()
    #|}
    #|
    #|///|
    #|fn helper() -> Int {
    #|  1
    #|}
  let names = lbl_names(registry, "moonbit", source, "vis.mbt")
  assert_true(names.get("Alias") == Some("Type"))
  assert_true(names.get("run") == Some("Function"))
  assert_true(!names.contains("helper"))
}

///|
/// A Zig `///` doc block is several DocComment tokens joined by newlines. The
/// whole block belongs to the declaration, not just its last line.
test "labels: zig doc block keeps every line" {
  let registry = get_fixture_registry()
  let source =
    #|/// First line of doc.
    #|/// Second line of doc.
    #|pub fn add(a: i32, b: i32) i32 {
    #|    return a + b;
    #|}
  let doc = lbl_doc_of(registry, "zig", source, "add.zig", "add")
  assert_eq(doc, " First line of doc.\n Second line of doc.")
}

// ─── Qualified names and import paths ───────────────────────

///|
/// `open Core.Std` is a dotted `ModulePath` of three tokens. The bare read
/// kept only `Std`, turning a dependency on `Core.Std` into one on `Std`.
test "labels: ocaml open and include keep the whole dotted path" {
  let registry = get_fixture_registry()
  let source =
    #|open Core.Std
    #|include Base.List
  let via = lbl_depends_via(registry, "ocaml", source, "m.ml")
  assert_eq(via.length(), 2)
  assert_eq(via[0], "Core.Std")
  assert_eq(via[1], "Base.List")
}

///|
/// `use App\Support\Collections\TaskList;` is a `QualifiedName` of seven
/// tokens. The bare read kept only `TaskList`, so every import in a namespaced
/// project collapsed to its last segment.
///
/// The `import` attr and the semantics block each emit one edge for the same
/// `use`, so the path appears more than once; what this pins is that EVERY
/// occurrence is the whole name, never the bare `TaskList` tail.
test "labels: php use keeps the whole qualified name" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|namespace App\Domain;
    #|
    #|use App\Support\Collections\TaskList;
  let via = lbl_depends_via(registry, "php", source, "e.php")
  assert_true(via.length() > 0)
  for v in via {
    assert_eq(v, "App\\Support\\Collections\\TaskList")
  }
}

///|
/// A Mermaid node name may be hyphenated (`line-item`), which lexes as
/// Ident MINUS Ident because MINUS is also half of every `--` link. The
/// semantics already rebuilt the name from `_text`; the attrs did not, so a
/// subgraph was registered under its last segment alone.
test "labels: mermaid hyphenated names arrive whole" {
  let registry = get_fixture_registry()
  let source =
    #|flowchart TD
    #|  subgraph order-pipeline
    #|    line-item --> delivery-address
    #|  end
  let names = lbl_names(registry, "mermaid", source, "h.mmd")
  assert_true(names.get("order-pipeline") == Some("Subgraph"))
  assert_true(!names.contains("pipeline"))
}

///|
/// An Elixir module name is a dotted `ModulePath`. The semantics already read
/// `$id_text`; the attrs `def` registered the symbol under `Scheduler` alone.
test "labels: elixir defmodule keeps the whole dotted name" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule MyApp.Scheduler do
    #|  @moduledoc "Schedules things."
    #|
    #|  def run(x) do
    #|    x
    #|  end
    #|end
  let names = lbl_names(registry, "elixir", source, "scheduler.ex")
  assert_true(names.get("MyApp.Scheduler") == Some("Module"))
  assert_true(!names.contains("Scheduler"))
}

///|
/// A Lua function name covers `f`, `M.f` and `M:f`; the label binds the LAST
/// identifier, so the attrs `def` registered `TaskManager:add` as `add`.
test "labels: lua dotted and colon function names arrive whole" {
  let registry = get_fixture_registry()
  let source =
    #|--- Creates a manager.
    #|function TaskManager.new()
    #|end
    #|
    #|--- Adds a task.
    #|function TaskManager:add(title)
    #|end
  let names = lbl_names(registry, "lua", source, "tm.lua")
  assert_true(names.get("TaskManager.new") == Some("Function"))
  assert_true(names.get("TaskManager:add") == Some("Function"))
  assert_true(!names.contains("new"))
  assert_true(!names.contains("add"))
}

// ─── Grammar bugs found by the same sweep ───────────────────

///|
/// A PHP enum case name is an ordinary identifier: `case Pending` lexes as
/// TypeIdent and `case lower_case` as Ident. The rule bound `Ident` only, so
/// every PascalCase case — which is the convention — failed to match and the
/// body fell through to a nameless `Enum::` edge. The `NL?` is what lets a
/// doc comment sit on its own line above the `case`, as it does everywhere
/// else in this spec.
test "labels: php enum case names are captured, whatever their casing" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|enum Status: string {
    #|    /** Not started yet. */
    #|    case Pending = 'pending';
    #|    case Done = 'done';
    #|    case lower_case = 'x';
    #|}
  let names = lbl_names(registry, "php", source, "status.php")
  assert_true(names.get("Status") == Some("Enum"))
  assert_true(names.get("Pending") == Some("EnumCase"))
  assert_true(names.get("Done") == Some("EnumCase"))
  assert_true(names.get("lower_case") == Some("EnumCase"))
  // The `NL` / comment alternatives of EnumMember bind no case name and must
  // not emit a nameless case of their own.
  assert_true(!names.contains(""))
  assert_eq(
    lbl_doc_of(registry, "php", source, "status.php", "Pending"),
    "Not started yet.",
  )
  assert_eq(
    lbl_parent_of(registry, "php", source, "status.php", "Pending"),
    "status.php::Status",
  )
}

///|
/// Haskell types are applied by juxtaposition: `f a`, `Map Int Task`. The type
/// rule joined atoms only through an operator, so `empty :: f a` matched just
/// `f`, the stranded `a` broke the `( NL ClassMember )+` repetition, and the
/// class body ended after its FIRST method — `insert` was then picked up as a
/// top-level FunctionDecl. An operator method spans three tokens
/// (`LPAREN Operator RPAREN`), so its name comes from `_text`.
test "labels: haskell class keeps every method, including operators" {
  let registry = get_fixture_registry()
  let source =
    #|module Demo.Container where
    #|
    #|-- | A container class.
    #|class Container f where
    #|  -- | Empty container.
    #|  empty :: f a
    #|  -- | Insert an element.
    #|  insert :: a -> f a -> f a
    #|  (<+>) :: f a -> f a -> f a
    #|
    #|-- | Top level function.
    #|topFn :: Int -> Int
    #|topFn x = x
  let names = lbl_names(registry, "haskell", source, "C.hs")
  assert_true(names.get("empty") == Some("Method"))
  assert_true(names.get("insert") == Some("Method"))
  assert_true(names.get("(<+>)") == Some("Method"))
  assert_true(names.get("topFn") == Some("Function"))
  // Every method belongs to the class, not to the file.
  assert_eq(
    lbl_parent_of(registry, "haskell", source, "C.hs", "insert"),
    "C.hs::Container",
  )
  assert_eq(
    lbl_parent_of(registry, "haskell", source, "C.hs", "(<+>)"),
    "C.hs::Container",
  )
  // The function written after the class belongs to the file again.
  assert_eq(lbl_parent_of(registry, "haskell", source, "C.hs", "topFn"), "C.hs")
}

///|
/// A Haskell record field's type is a type application too (`Map Int Task`).
/// Without it the record braces broke apart and the fields leaked out as
/// top-level functions — declared twice, once wrongly.
test "labels: haskell record fields stay fields" {
  let registry = get_fixture_registry()
  let source =
    #|module Demo.Store where
    #|
    #|-- | In-memory store.
    #|data TaskStore = TaskStore
    #|  { storeTasks :: Map Int Task
    #|  , storeNextId :: Int
    #|  } deriving (Show)
  let rows = lbl_declares(registry, "haskell", source, "S.hs")
  let mut store_tasks = 0
  for row in rows {
    if row.1 == "storeTasks" {
      store_tasks = store_tasks + 1
      assert_eq(row.2, "Field")
    }
  }
  assert_eq(store_tasks, 1)
}

// ─── Container members ──────────────────────────────────────

///|
/// In Zig a container body holds methods and constants as well as fields:
/// `pub fn complete` inside `const Task = struct { ... }` is a method of
/// `Task`. The three declaration rules ignored the `current_container` that
/// the headers already publish, so each member was declared a second time at
/// file level under a bare name.
test "labels: zig container members attach to their container" {
  let registry = get_fixture_registry()
  let source =
    #|/// A task.
    #|pub const Task = struct {
    #|    completed: bool,
    #|
    #|    /// Mark the task as completed.
    #|    pub fn complete(self: *Task) void {}
    #|
    #|    /// A container constant.
    #|    pub const MAX = 10;
    #|};
    #|
    #|/// Top-level function.
    #|pub fn helper() void {}
  assert_eq(
    lbl_parent_of(registry, "zig", source, "s.zig", "complete"),
    "s.zig::Task",
  )
  assert_eq(
    lbl_parent_of(registry, "zig", source, "s.zig", "MAX"),
    "s.zig::Task",
  )
  assert_eq(
    lbl_parent_of(registry, "zig", source, "s.zig", "completed"),
    "s.zig::Task",
  )
  // A genuinely file-level declaration still hangs off the file: no container
  // frame is open there, so `outer` is empty.
  assert_eq(lbl_parent_of(registry, "zig", source, "s.zig", "helper"), "s.zig")
  assert_eq(lbl_parent_of(registry, "zig", source, "s.zig", "Task"), "s.zig")
}

///|
/// An OCaml `let` written inside a `struct ... end` is a member of that
/// module. It used to hang off the file, so two modules defining the same
/// helper collided at file level.
test "labels: ocaml let inside a module attaches to that module" {
  let registry = get_fixture_registry()
  let source =
    #|(** Outer module doc. *)
    #|module Inner = struct
    #|  (** Adds two numbers. *)
    #|  let add a b = a + b
    #|
    #|  let sub a b = a - b
    #|end
    #|
    #|let top_level x = x
  assert_eq(
    lbl_parent_of(registry, "ocaml", source, "m.ml", "add"),
    "m.ml::Inner",
  )
  assert_eq(
    lbl_parent_of(registry, "ocaml", source, "m.ml", "sub"),
    "m.ml::Inner",
  )
  // A `let` written after the module's `end` belongs to the file again: the
  // module's scope frame is popped by `ModuleDecl`.
  assert_eq(
    lbl_parent_of(registry, "ocaml", source, "m.ml", "top_level"),
    "m.ml",
  )
  assert_eq(lbl_parent_of(registry, "ocaml", source, "m.ml", "Inner"), "m.ml")
}

// ─── Manifest values ────────────────────────────────────────

///|
/// A TOML value is `Scalar / InlineTable / ArrayValue` and so can span many
/// tokens. Every read the spec makes is of a scalar, where `_text` is that
/// same single token — this pins that reading `_text` throughout did not
/// change what a manifest reports.
test "labels: cargo manifest values are read whole" {
  let registry = get_fixture_registry()
  let source =
    #|[package]
    #|name = "demo-app"
    #|version = "0.2.1"
    #|keywords = ["cli", "demo"]
    #|
    #|[dependencies]
    #|serde = "1.0"
    #|clap = { version = "4.0", features = ["derive"] }
    #|
  let graph = match lbl_graph(registry, "cargo-toml", source, "Cargo.toml") {
    Some(g) => g
    None => {
      assert_true(false)
      return
    }
  }
  let mut name = ""
  let mut version = ""
  let keywords : Array[String] = []
  let deps : Array[String] = []
  for edge in graph.get_edges() {
    if edge_kind_is(edge.kind, "projectName") {
      name = edge.to
    } else if edge_kind_is(edge.kind, "projectVersion") {
      version = edge.to
    } else if edge_kind_is(edge.kind, "projectKeyword") {
      keywords.push(edge.to)
    } else if edge_kind_is(edge.kind, "dependsOn") {
      deps.push(edge.to)
    }
  }
  assert_eq(name, "demo-app")
  assert_eq(version, "0.2.1")
  assert_eq(keywords.length(), 2)
  assert_eq(keywords[0], "cli")
  assert_eq(keywords[1], "demo")
  assert_eq(deps.length(), 2)
  assert_eq(deps[0], "crate:serde")
  assert_eq(deps[1], "crate:clap")
}
