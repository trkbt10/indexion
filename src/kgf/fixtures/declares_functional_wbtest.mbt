///|
/// Regression tests for the functional, dynamic and schema KGF specs
/// (haskell, ocaml, elixir, scala, julia, lua, protobuf).
///
/// Each test pins one root cause that used to make a spec produce wrong or
/// missing edges on ordinary source. Three failure modes recur, and all three
/// are silent:
///
/// - **Partial parse.** The start rule matches only a prefix; every
///   declaration after the stopping point is dropped while the file still
///   looks analysed.
/// - **Full parse, no edges.** An opaque body rule was able to consume its own
///   terminator (`end`), so every declaration failed to match and fell through
///   to the catch-all. The parse reports SUCCESS and the file yields nothing.
/// - **Lexer shadowing.** A generic `Operator` token defined before `EQ` or
///   `COLON` swallowed every bare `=` / `:`, so the grammar slots that needed
///   them could never match.
///
/// The tests therefore assert on the declarations that FOLLOW the construct
/// that used to break, not only on the construct itself.
///
/// Helpers carry a `fnl_` prefix so they cannot clash with the ones in
/// declares_wbtest.mbt or declares_systems_scripting_wbtest.mbt, which share
/// this package.

///|
/// Run the full KGF pipeline (lex, parse, semantics) on inline source and
/// return the resulting graph, or None when the parse fails outright.
fn fnl_eval_source_graph(
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
/// The declared names of inline source, mapped to their `kind` attribute.
/// An empty map means the source produced no declares edges at all.
fn fnl_declared_names(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  let graph = match fnl_eval_source_graph(registry, lang, source, path) {
    Some(g) => g
    None => return names
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares {
      names.set(
        edge.attrs.get("name").unwrap_or(""),
        edge.attrs.get("kind").unwrap_or(""),
      )
    }
  }
  names
}

///|
/// How many declares edges carry `name`. Used to pin the duplicate-edge
/// regressions: a declaration that matches two grammar alternatives, or whose
/// enclosing rule backtracks and re-reduces it, emits the same symbol twice.
fn fnl_count_named(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> Int {
  let graph = match fnl_eval_source_graph(registry, lang, source, path) {
    Some(g) => g
    None => return 0
  }
  let mut count = 0
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("name").unwrap_or("") == name {
      count = count + 1
    }
  }
  count
}

///|
/// The `from` endpoint of the declares edge for `name`, or "" when there is
/// none. A member (method, field, variant, enum case, rpc) must hang off its
/// parent's symbol id rather than off the file.
fn fnl_parent_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  let graph = match fnl_eval_source_graph(registry, lang, source, path) {
    Some(g) => g
    None => return ""
  }
  let mut found = ""
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("name").unwrap_or("") == name {
      found = edge.from
    }
  }
  found
}

///|
/// The `doc` attribute recorded for one declared name, or "" when the name has
/// no declares edge or carries no doc.
fn fnl_doc_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  let graph = match fnl_eval_source_graph(registry, lang, source, path) {
    Some(g) => g
    None => return ""
  }
  let mut found = ""
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("name").unwrap_or("") == name {
      let doc = edge.attrs.get("doc").unwrap_or("")
      if doc != "" {
        found = doc
      }
    }
  }
  found
}

///|
/// The `via` attributes of the moduleDependsOn edges of inline source, in
/// emission order. `via` must carry the WHOLE module path: a label bound to a
/// multi-token rule holds only its last token, so a dotted path reported just
/// its final segment until the specs switched to `$path_text`.
fn fnl_depends_via(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[String] {
  let result : Array[String] = []
  let graph = match fnl_eval_source_graph(registry, lang, source, path) {
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

///|
/// True when the start rule consumed every token. A partial parse is the
/// dangerous failure mode: the prefix still matches, so the file looks
/// analysed while everything after the stopping point is silently missing.
fn fnl_parses_fully(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
) -> Bool {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return false }
  let (_, diagnostic) = @peg.run_parse_with_diagnostics(
    peg,
    spec,
    spec.get_start_rule(),
    tokens,
  )
  diagnostic.is_fully_consumed()
}

///|
/// True when every character of the source matched some token rule. A
/// character that matches nothing is skipped silently, so the grammar sees a
/// token stream that no longer says what the author wrote.
fn fnl_lexes_cleanly(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
) -> Bool {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let (_, diagnostics) = lexer.tokenize_with_diagnostics(source)
  diagnostics.length() == 0
}

// ─── Haskell ────────────────────────────────────────────────

///|
/// A module header with a MULTI-LINE export list used not to match at all:
/// `ExportList` had no `NL*` slots, so the newlines between entries, and the
/// one before `where`, broke the rule. `ModuleDecl` then fell through to the
/// catch-all and the file got no Module edge whatsoever.
test "declares: haskell module header with multi-line export list" {
  let registry = get_fixture_registry()
  let source =
    #|-- | Task scheduling.
    #|module Data.Task.Scheduler
    #|  ( Priority(..)
    #|  , schedule
    #|  ) where
    #|
    #|schedule :: [String] -> [String]
    #|schedule xs = xs
  let names = fnl_declared_names(registry, "haskell", source, "Scheduler.hs")
  assert_true(names.get("Data.Task.Scheduler") == Some("Module"))
  assert_true(names.get("schedule") == Some("Function"))
}

///|
/// A qualified module name is dot-joined with no spaces. The lexer had no
/// token for that shape, so `Data.Map.Strict` split into three idents around
/// two generic `Operator` dots and `import`/`module` captured only the first
/// segment — producing a dependency on "Data" instead of the real module.
test "declares: haskell import keeps the whole dotted module path" {
  let registry = get_fixture_registry()
  let source =
    #|module M where
    #|
    #|import Data.Map.Strict (Map)
    #|import qualified Control.Monad.State as State
  let vias = fnl_depends_via(registry, "haskell", source, "M.hs")
  assert_true(vias.contains("Data.Map.Strict"))
  assert_true(vias.contains("Control.Monad.State"))
  assert_true(!vias.contains("Data"))
  assert_true(!vias.contains("Control"))
}

///|
/// A Haskell function is written as a type signature followed by its defining
/// equations. `FunctionDecl` had one alternative per form, so BOTH matched and
/// the same function got two identical declares edges. The rule now matches
/// the signature plus its equations as a single declaration.
test "declares: haskell signature plus equation is one declaration" {
  let registry = get_fixture_registry()
  let source =
    #|module M where
    #|
    #|-- | Adds two numbers.
    #|add :: Int -> Int -> Int
    #|add a b = a + b
  assert_eq(fnl_count_named(registry, "haskell", source, "M.hs", "add"), 1)
  assert_true(
    fnl_doc_of(registry, "haskell", source, "M.hs", "add").contains(
      "Adds two numbers.",
    ),
  )
}

///|
/// Class methods used to wait on a `current_class` binding that nothing ever
/// produced, so a typeclass contributed no method edges. The bind now happens
/// in a `ClassHeader` sub-rule, which matches BEFORE the body is entered —
/// events fire bottom-up, so a bind on `ClassDecl` itself would run after its
/// own members had already been reduced.
test "declares: haskell class methods attach to their class" {
  let registry = get_fixture_registry()
  let source =
    #|module M where
    #|
    #|-- | A clock.
    #|class Clock c where
    #|  -- | Current time.
    #|  now :: c -> Int
    #|  sleepFor :: c -> Int -> Int
    #|
    #|-- | Top level, not a method.
    #|afterClass :: Int
    #|afterClass = 1
  let names = fnl_declared_names(registry, "haskell", source, "M.hs")
  assert_true(names.get("Clock") == Some("Class"))
  assert_true(names.get("now") == Some("Method"))
  assert_true(names.get("sleepFor") == Some("Method"))
  assert_eq(
    fnl_parent_of(registry, "haskell", source, "M.hs", "now"),
    "M.hs::Clock",
  )
  // The class body is indentation-delimited, which a token grammar cannot
  // see. It is bounded by the first BLANK line, so the declaration that
  // follows must stay a top-level Function rather than becoming a method.
  assert_true(names.get("afterClass") == Some("Function"))
}

///|
/// Record fields used to surface as top-level `Function`s, because `DataCons`
/// had no slot for the record brace — which sits on the line AFTER the
/// constructor name in idiomatic code.
test "declares: haskell record fields attach to their data type" {
  let registry = get_fixture_registry()
  let source =
    #|module M where
    #|
    #|-- | A policy.
    #|data RetryPolicy = RetryPolicy
    #|  { retryLimit   :: Int
    #|  , retryBackoff :: Double
    #|  } deriving (Show, Eq)
  let names = fnl_declared_names(registry, "haskell", source, "M.hs")
  assert_true(names.get("RetryPolicy") == Some("Data"))
  assert_true(names.get("retryLimit") == Some("Field"))
  assert_true(names.get("retryBackoff") == Some("Field"))
}

///|
/// A `where` block binds helpers local to one equation. The rule consumed it
/// with a greedy `( NL / Atom )*`, which swallowed every following
/// declaration to end of file; the helpers themselves also leaked out as
/// top-level functions.
test "declares: haskell where-block does not swallow later declarations" {
  let registry = get_fixture_registry()
  let source =
    #|module M where
    #|
    #|bucketize :: [Int] -> Int
    #|bucketize xs = foldr step 0 xs
    #|  where
    #|    step x acc = x + acc
    #|
    #|-- | Declared after the where block.
    #|afterWhere :: Int
    #|afterWhere = 1
  let names = fnl_declared_names(registry, "haskell", source, "M.hs")
  assert_true(names.get("bucketize") == Some("Function"))
  assert_true(names.get("afterWhere") == Some("Function"))
  // `step` is local to the equation and must not surface at all.
  assert_true(!names.contains("step"))
}

// ─── OCaml ──────────────────────────────────────────────────

///|
/// `exception Overloaded of string` used to stop the parse dead: the payload
/// after `of` was not accepted, the item failed, and with no top-level
/// catch-all everything after it was dropped.
test "declares: ocaml exception with payload does not stop the parse" {
  let registry = get_fixture_registry()
  let source =
    #|(** A type. *)
    #|type slot = Slot of int
    #|
    #|exception Overloaded of string
    #|
    #|(** Declared after the exception. *)
    #|let after_exception x = x
  assert_true(fnl_parses_fully(registry, "ocaml", source))
  let names = fnl_declared_names(registry, "ocaml", source, "m.ml")
  assert_true(names.get("Overloaded") == Some("Exception"))
  assert_true(names.get("after_exception") == Some("Function"))
}

///|
/// Variants and record fields used to wait on a `current_type` binding that
/// nothing produced. A `TypeHeader` sub-rule now publishes the type id before
/// its definition is parsed.
test "declares: ocaml variants and fields attach to their type" {
  let registry = get_fixture_registry()
  let source =
    #|(** Priority. *)
    #|type priority =
    #|  | Low  (** Spare capacity. *)
    #|  | High
    #|
    #|(** Policy. *)
    #|type retry_policy = {
    #|  limit : int;  (** Max attempts. *)
    #|  backoff : float;
    #|  mutable attempts : int;
    #|}
  let names = fnl_declared_names(registry, "ocaml", source, "m.ml")
  assert_true(names.get("priority") == Some("Type"))
  assert_true(names.get("Low") == Some("Variant"))
  assert_true(names.get("High") == Some("Variant"))
  assert_eq(
    fnl_parent_of(registry, "ocaml", source, "m.ml", "Low"),
    "m.ml::priority",
  )
  // A trailing `(** ... *)` sits AFTER the `;`, so the field separator has to
  // absorb it; otherwise the record was truncated after its first field.
  assert_true(names.get("limit") == Some("Field"))
  assert_true(names.get("backoff") == Some("Field"))
  assert_true(names.get("attempts") == Some("Field"))
}

///|
/// An object body used to be consumed by the method's own opaque right-hand
/// side, because `Expr` accepted `KW_end` — the token that CLOSES the object.
/// The class then failed, its header was re-matched as a standalone item
/// (emitting a second, doc-less Class edge), and every method after the first
/// was lost. A `virtual` method, which has a type but no body, was dropped
/// too because the modifier slot matched a bare identifier and took the
/// method name for a flag.
test "declares: ocaml object methods attach once to their class" {
  let registry = get_fixture_registry()
  let source =
    #|(** A clock. *)
    #|class virtual clock = object
    #|  (** Current time. *)
    #|  method virtual now : int
    #|
    #|  (** Sleeps. *)
    #|  method sleep_for ms = ms
    #|end
  let names = fnl_declared_names(registry, "ocaml", source, "m.ml")
  assert_true(names.get("clock") == Some("Class"))
  assert_eq(fnl_count_named(registry, "ocaml", source, "m.ml", "clock"), 1)
  assert_true(names.get("now") == Some("Method"))
  assert_true(names.get("sleep_for") == Some("Method"))
  // `ms` is the PARAMETER of sleep_for, never the method name.
  assert_true(!names.contains("ms"))
  assert_eq(
    fnl_parent_of(registry, "ocaml", source, "m.ml", "now"),
    "m.ml::clock",
  )
}

///|
/// `TypeAtom` had a record-brace alternative that re-parsed the very
/// `RecordField`s `RecordDef` had already matched, so each field was reduced
/// twice and emitted twice.
test "declares: ocaml record field is declared once" {
  let registry = get_fixture_registry()
  let source =
    #|type store = {
    #|  tasks : task list;
    #|  next_id : int;
    #|}
  assert_eq(fnl_count_named(registry, "ocaml", source, "m.ml", "tasks"), 1)
  assert_eq(fnl_count_named(registry, "ocaml", source, "m.ml", "next_id"), 1)
}

// ─── Elixir ─────────────────────────────────────────────────

///|
/// The headline failure of this spec: `Statement` accepted `KW_end`, so a
/// `def` body could eat the `end` that closes it. The body never terminated,
/// `DefDecl` never completed, `ModuleDecl` never completed, and EVERY
/// declaration fell through to the catch-all — the file produced zero edges
/// while still reporting a successful parse.
test "declares: elixir module and functions are not silently dropped" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule TaskApp.TaskServer do
    #|  @moduledoc "Holds tasks in memory."
    #|
    #|  @doc "Starts the server."
    #|  def start_link(opts) do
    #|    GenServer.start_link(__MODULE__, %{}, opts)
    #|  end
    #|
    #|  defp private_helper(x) do
    #|    x
    #|  end
    #|end
  let names = fnl_declared_names(registry, "elixir", source, "server.ex")
  // The module name is a dotted path and must survive whole.
  assert_true(names.get("TaskApp.TaskServer") == Some("Module"))
  assert_true(names.get("start_link") == Some("Function"))
  assert_eq(
    fnl_parent_of(registry, "elixir", source, "server.ex", "start_link"),
    "server.ex::TaskApp.TaskServer",
  )
  // `defp` is private and must not be declared.
  assert_true(!names.contains("private_helper"))
}

///|
/// `@moduledoc` belongs to the module and `@doc` to the NEXT function, but a
/// single `DocAttr` token kind covered both, so a module with no `@moduledoc`
/// stole the first function's `@doc`. The two are separate token kinds now.
/// The single-line form `@doc "..."` also had no lexer rule at all — only the
/// heredoc and `false` forms — so it lexed as two tokens and was never
/// captured.
test "declares: elixir moduledoc and doc attach to the right symbols" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule A do
    #|  @doc "Function doc."
    #|  def f(a), do: a
    #|end
  assert_true(
    fnl_doc_of(registry, "elixir", source, "a.ex", "f").contains(
      "Function doc.",
    ),
  )
  // A has no @moduledoc, so it must NOT inherit f's @doc.
  assert_eq(fnl_doc_of(registry, "elixir", source, "a.ex", "A"), "")
}

///|
/// `quote do: expr` is a keyword-list entry, not a `do ... end` block. The
/// block rule was tried first, so the bare `do:` opened a block that consumed
/// the ENCLOSING `end`; the outer body then failed and the whole module was
/// re-parsed, emitting every declaration twice.
test "declares: elixir inline do: keyword does not open a block" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule M do
    #|  def f(x), do: x
    #|
    #|  defmacro g do
    #|    quote do: unquote(1)
    #|  end
    #|end
  assert_eq(fnl_count_named(registry, "elixir", source, "m.ex", "f"), 1)
  assert_eq(fnl_count_named(registry, "elixir", source, "m.ex", "g"), 1)
  let names = fnl_declared_names(registry, "elixir", source, "m.ex")
  assert_true(names.get("g") == Some("Macro"))
}

///|
/// A guard ends at the `,` that introduces the `do:` body, but the guard
/// expression accepted a top-level COMMA and so consumed the separator and
/// the body with it. The declaration failed, the module body backtracked, and
/// every declaration before it was emitted a second time.
test "declares: elixir guard with inline body does not duplicate earlier defs" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule M do
    #|  def a(x), do: x
    #|  defp normalize(v) when is_binary(v), do: String.downcase(v)
    #|end
  assert_eq(fnl_count_named(registry, "elixir", source, "m.ex", "a"), 1)
}

///|
/// Elixir has four ways to reference another module and each must produce a
/// dependency carrying the whole dotted path.
test "declares: elixir use/import/alias/require record the full module path" {
  let registry = get_fixture_registry()
  let source =
    #|defmodule M do
    #|  use GenServer
    #|  import Enum
    #|  alias TaskApp.TaskServer
    #|  require Logger
    #|end
  let vias = fnl_depends_via(registry, "elixir", source, "m.ex")
  assert_true(vias.contains("GenServer"))
  assert_true(vias.contains("Enum"))
  assert_true(vias.contains("TaskApp.TaskServer"))
  assert_true(vias.contains("Logger"))
}

// ─── Scala ──────────────────────────────────────────────────

///|
/// The deepest bug in this spec: the generic `Operator` token included `:`
/// and was defined BEFORE `COLON`, so the first-match lexer turned every
/// single `:` in the language into an `Operator`. No `param: Type`,
/// `def f: T` or `val x: T` could ever match its COLON slot.
test "declares: scala colon is not shadowed by the operator token" {
  let registry = get_fixture_registry()
  let source =
    #|/** How urgently a task should run. */
    #|enum Priority(val weight: Int) {
    #|  /** Spare capacity. */
    #|  case Low extends Priority(0)
    #|  case High extends Priority(2)
    #|}
  let names = fnl_declared_names(registry, "scala", source, "P.scala")
  assert_true(names.get("Priority") == Some("Enum"))
  assert_true(names.get("Low") == Some("EnumCase"))
  assert_true(names.get("High") == Some("EnumCase"))
  assert_eq(
    fnl_parent_of(registry, "scala", source, "P.scala", "Low"),
    "P.scala::Priority",
  )
  assert_true(
    fnl_doc_of(registry, "scala", source, "P.scala", "Low").contains(
      "Spare capacity.",
    ),
  )
}

///|
/// `case` is not a modifier: `case class` / `case object` have their own
/// explicit slot, and inside an enum body `case` introduces an EnumCase.
/// Listing it in `Modifier` made every rule tried before `EnumCase` swallow
/// the keyword, so no enum case ever matched.
test "declares: scala case class and case object still parse" {
  let registry = get_fixture_registry()
  let source =
    #|/** A task. */
    #|final case class Task(id: Long, title: String)
    #|
    #|/** Declared after the case class. */
    #|case object Sentinel
  let names = fnl_declared_names(registry, "scala", source, "T.scala")
  assert_true(names.get("Task") == Some("Class"))
  assert_true(names.get("Sentinel") == Some("Object"))
}

///|
/// Members used to be emitted from the file rather than from their enclosing
/// type, and a method declared in two different types collided. Each type
/// header now publishes its id for the members that follow it.
test "declares: scala methods attach to their enclosing type" {
  let registry = get_fixture_registry()
  let source =
    #|/** A clock. */
    #|trait Clock {
    #|  /** Current time. */
    #|  def now: Long
    #|}
    #|
    #|/** A scheduler. */
    #|class Scheduler {
    #|  /** Submits a task. */
    #|  def submit(name: String): Unit = {
    #|    println(name)
    #|  }
    #|}
  assert_eq(
    fnl_parent_of(registry, "scala", source, "S.scala", "now"),
    "S.scala::Clock",
  )
  assert_eq(
    fnl_parent_of(registry, "scala", source, "S.scala", "submit"),
    "S.scala::Scheduler",
  )
}

///|
/// The `=== attrs` import action and the `=== semantics` block both emitted a
/// dependency edge, so every import produced two — and the attrs one resolved
/// `path` as a single label, which for a multi-token name is only its LAST
/// segment.
test "declares: scala import records the whole dotted path once" {
  let registry = get_fixture_registry()
  let source =
    #|package com.example.tasks
    #|
    #|import scala.collection.mutable
  let vias = fnl_depends_via(registry, "scala", source, "S.scala")
  assert_eq(vias.length(), 1)
  assert_eq(vias[0], "scala.collection.mutable")
}

// ─── Julia ──────────────────────────────────────────────────

///|
/// Same headline failure as Elixir: the function body could reach `KW_end`
/// through the atom set, so it never terminated, every `function ... end`
/// failed to match, and the whole file fell through to the catch-all with
/// zero edges despite a successful parse.
test "declares: julia functions and structs are not silently dropped" {
  let registry = get_fixture_registry()
  let source =
    #|"""Add a task."""
    #|function add!(col, title)
    #|    push!(col.tasks, title)
    #|    return col
    #|end
    #|
    #|"""A task."""
    #|struct Task
    #|    id::Int
    #|    title::String
    #|end
  let names = fnl_declared_names(registry, "julia", source, "m.jl")
  assert_true(names.get("add!") == Some("Function"))
  assert_true(names.get("Task") == Some("Struct"))
  assert_true(names.get("id") == Some("Field"))
  assert_eq(
    fnl_parent_of(registry, "julia", source, "m.jl", "id"),
    "m.jl::Task",
  )
  // The docstring token must expose its BODY, not the `"""` delimiters.
  assert_true(
    fnl_doc_of(registry, "julia", source, "m.jl", "add!").contains(
      "Add a task.",
    ),
  )
}

///|
/// The generic `Operator` token included `=` and was defined before `EQ`, so
/// every bare `=` lexed as an Operator and the assignment form `f(x) = expr`
/// — the most common way to define a Julia function — could never match.
test "declares: julia short assignment form defines a function" {
  let registry = get_fixture_registry()
  let source =
    #|"""Return the pending tasks."""
    #|pending(col) = filter(t -> !t.done, col.tasks)
  let names = fnl_declared_names(registry, "julia", source, "m.jl")
  assert_true(names.get("pending") == Some("Function"))
}

///|
/// `for` opens a block ONLY at statement level; inside brackets it introduces
/// a comprehension, which has no `end`. Treating it as a block opener there
/// made the bracket group demand a terminator that never came, so any
/// function containing a comprehension failed to match and was dropped.
test "declares: julia comprehension does not break the enclosing function" {
  let registry = get_fixture_registry()
  let source =
    #|function schedule(tasks)
    #|    ordered = sort(tasks)
    #|    return [name for (name, _) in ordered]
    #|end
    #|
    #|"""Declared after the comprehension."""
    #|after_comprehension(x) = x
  assert_true(fnl_parses_fully(registry, "julia", source))
  let names = fnl_declared_names(registry, "julia", source, "m.jl")
  assert_true(names.get("schedule") == Some("Function"))
  assert_true(names.get("after_comprehension") == Some("Function"))
}

///|
/// `weight(::Low) = 0` dispatches on a type with NO parameter name, which is
/// idiomatic Julia multiple dispatch. The parameter rule required a named
/// identifier, so these methods never matched.
test "declares: julia method dispatching on a bare type parses" {
  let registry = get_fixture_registry()
  let source =
    #|"""Numeric weight."""
    #|weight(::Low) = 0
    #|weight(::High) = 2
  let names = fnl_declared_names(registry, "julia", source, "m.jl")
  assert_true(names.get("weight") == Some("Function"))
}

///|
/// `$` is Julia's interpolation operator and had no token at all, so the
/// lexer reported unrecognized input and skipped the character.
test "declares: julia interpolation dollar lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|macro timed(expr)
    #|    return quote
    #|        local result = $(esc(expr))
    #|        result
    #|    end
    #|end
  assert_true(fnl_lexes_cleanly(registry, "julia", source))
  let names = fnl_declared_names(registry, "julia", source, "m.jl")
  assert_true(names.get("timed") == Some("Macro"))
}

// ─── Lua ────────────────────────────────────────────────────

///|
/// Same headline failure again: the statement rule listed `KW_end` among the
/// keywords a body could contain, so every `function ... end` failed and the
/// file produced zero edges despite a successful parse.
test "declares: lua functions are not silently dropped" {
  let registry = get_fixture_registry()
  let source =
    #|--- Creates a manager.
    #|function TaskManager.new()
    #|    local self = setmetatable({}, TaskManager)
    #|    return self
    #|end
    #|
    #|--- Adds a task.
    #|function TaskManager:add(title)
    #|    return title
    #|end
  let names = fnl_declared_names(registry, "lua", source, "m.lua")
  // The qualified name is kept whole so `M.f` and `M:g` stay distinct.
  assert_true(names.get("TaskManager.new") == Some("Function"))
  assert_true(names.get("TaskManager:add") == Some("Function"))
  assert_true(
    fnl_doc_of(registry, "lua", source, "m.lua", "TaskManager.new").contains(
      "Creates a manager.",
    ),
  )
}

///|
/// A `repeat ... until` block is the one Lua block NOT closed by `end`.
/// Treating it like the others left the `until` unconsumed and broke the
/// enclosing function.
test "declares: lua repeat-until block does not break the enclosing function" {
  let registry = get_fixture_registry()
  let source =
    #|--- Retries a function.
    #|local function retry(fn, limit)
    #|    local attempts = 0
    #|    repeat
    #|        attempts = attempts + 1
    #|    until attempts >= limit
    #|    return false
    #|end
    #|
    #|--- Declared after the repeat block.
    #|function after_repeat()
    #|    return 1
    #|end
  assert_true(fnl_parses_fully(registry, "lua", source))
  let names = fnl_declared_names(registry, "lua", source, "m.lua")
  // The global declared after the repeat block must still be reached.
  assert_true(names.get("after_repeat") == Some("Function"))
  // `retry` is `local`, which is Lua's privacy keyword, so it is not
  // published — but it still has to PARSE, which is what this test pins.
  assert_true(!names.contains("retry"))
}

///|
/// `require` is Lua's only import form and the spec had no rule for it, so a
/// Lua file produced no dependency edges at all. Both the call form and the
/// bare string form must be recognised, and the quotes stripped.
test "declares: lua require produces a dependency edge" {
  let registry = get_fixture_registry()
  let source =
    #|local TaskManager = require("task_manager")
    #|local inspect = require "inspect"
  let vias = fnl_depends_via(registry, "lua", source, "m.lua")
  assert_true(vias.contains("task_manager"))
  assert_true(vias.contains("inspect"))
}

// ─── Protobuf ───────────────────────────────────────────────

///|
/// Fields, enum values, oneof alternatives and map fields all had to PARSE,
/// or the container holding them failed and was dropped along with whatever
/// followed it. The published declares surface for protobuf is deliberately
/// containers + rpcs, not individual members (pinned by declares_wbtest.mbt),
/// so this test asserts that the containers survive bodies full of members
/// rather than that each member gets an edge of its own.
test "declares: protobuf containers survive bodies full of members" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto3";
    #|
    #|// Lifecycle state.
    #|enum Status {
    #|  // Queued.
    #|  STATUS_PENDING = 0;
    #|  STATUS_DONE = 2;
    #|}
    #|
    #|// A task.
    #|message Task {
    #|  // Stable identifier.
    #|  int64 id = 1;
    #|  string title = 2;
    #|
    #|  // Payload, inline or by reference.
    #|  oneof payload {
    #|    bytes inline_payload = 6;
    #|    string payload_uri = 7;
    #|  }
    #|
    #|  map<string, string> annotations = 8;
    #|}
    #|
    #|// Declared after all of the above.
    #|message Trailer {
    #|  string note = 1;
    #|}
  assert_true(fnl_parses_fully(registry, "protobuf", source))
  let names = fnl_declared_names(registry, "protobuf", source, "t.proto")
  assert_true(names.get("Status") == Some("Enum"))
  assert_true(names.get("Task") == Some("Message"))
  // The message declared after the oneof and the map field must still be
  // reached: a oneof body that failed to match used to take the rest with it.
  assert_true(names.get("Trailer") == Some("Message"))
  // Members are not part of the published surface.
  assert_true(!names.contains("id"))
  assert_true(!names.contains("inline_payload"))
  assert_true(!names.contains("STATUS_PENDING"))
}

///|
/// An rpc must hang off its service, and its request/response message types
/// are worth recording on the edge. Rpcs used to be emitted from the file, so
/// two services with a same-named method collided.
test "declares: protobuf rpc attaches to its service" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto3";
    #|
    #|// Read and write tasks.
    #|service TaskStore {
    #|  // Fetches one task.
    #|  rpc Get(GetRequest) returns (GetResponse);
    #|
    #|  // Streams every task.
    #|  rpc List(ListRequest) returns (stream Task) {
    #|    option idempotency_level = NO_SIDE_EFFECTS;
    #|  }
    #|}
  let names = fnl_declared_names(registry, "protobuf", source, "t.proto")
  assert_true(names.get("TaskStore") == Some("Service"))
  assert_true(names.get("Get") == Some("Rpc"))
  assert_true(names.get("List") == Some("Rpc"))
  assert_eq(
    fnl_parent_of(registry, "protobuf", source, "t.proto", "Get"),
    "t.proto::TaskStore",
  )
}

///|
/// The `extend` rule had no slot for the newlines inside its block, so it
/// never matched: the block fell through to the catch-all token by token and
/// could carry away the declaration that followed it.
test "declares: protobuf extend block does not break later declarations" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto2";
    #|
    #|message Task {
    #|  required int64 id = 1;
    #|  extensions 100 to 199;
    #|}
    #|
    #|// Extra fields.
    #|extend Task {
    #|  optional int32 priority_weight = 100;
    #|}
    #|
    #|// Declared after the extend block.
    #|message Trailer {
    #|  optional string note = 1;
    #|}
  assert_true(fnl_parses_fully(registry, "protobuf", source))
  let names = fnl_declared_names(registry, "protobuf", source, "t.proto")
  assert_true(names.get("Task") == Some("Message"))
  assert_true(names.get("Trailer") == Some("Message"))
}

///|
/// The `=== attrs` import action and the `=== semantics` block both emitted a
/// dependency edge, so every import produced two; the quotes also had to be
/// stripped before resolving.
test "declares: protobuf import produces one unquoted dependency" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto3";
    #|
    #|import "google/protobuf/timestamp.proto";
  let vias = fnl_depends_via(registry, "protobuf", source, "t.proto")
  assert_eq(vias.length(), 1)
  assert_eq(vias[0], "google/protobuf/timestamp.proto")
}
