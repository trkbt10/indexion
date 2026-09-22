///|
/// Regression tests for constructs that made a whole declaration — and, with
/// it, everything the declaration enclosed — disappear from the graph.
///
/// Every defect pinned here failed the same silent way: the construct was
/// unmatchable by the rule that should have accepted it, so the enclosing
/// declaration failed, the module-level catch-all re-parsed the region one
/// token at a time, and the parse still reported success. Nothing was
/// reported; the symbols were simply not there. That is why each test asserts
/// on the DECLARED NAMES rather than on a parse status.
///
/// The helpers carry a `kwb_` prefix so this file can coexist with the other
/// fixture test files in this package.

///|
/// Run the full KGF pipeline on inline source and return the resulting graph,
/// or None when parsing fails outright.
fn kwb_graph(
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
/// The declared names of inline source, mapped to their `kind`.
fn kwb_names(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  let graph = match kwb_graph(registry, lang, source, path) {
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
/// The `from` endpoint — the OWNER — of the declares edge for `name`, or ""
/// when nothing declares it.
fn kwb_owner_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  let graph = match kwb_graph(registry, lang, source, path) {
    Some(g) => g
    None => return ""
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("name").unwrap_or("") == name {
      return edge.from
    }
  }
  ""
}

///|
/// The `doc` recorded for one declared name, or "" when it has none.
fn kwb_doc_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  let graph = match kwb_graph(registry, lang, source, path) {
    Some(g) => g
    None => return ""
  }
  for edge in graph.get_edges() {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("name").unwrap_or("") == name {
      let doc = edge.attrs.get("doc").unwrap_or("")
      if doc != "" {
        return doc
      }
    }
  }
  ""
}

///|
/// True when every character of the source matched some token rule. A
/// character matching nothing is skipped silently, so the grammar sees a token
/// stream that no longer says what the author wrote.
fn kwb_lexes_cleanly(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
) -> Bool {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let (_, diagnostics) = lexer.tokenize_with_diagnostics(source)
  diagnostics.length() == 0
}

// ─── Ruby: keywords inside a method body ────────────────────

///|
/// `super`, `self` and `alias` were each missing from the rule listing what a
/// method body may contain, so a body using one made `MethodDecl` unmatchable.
/// The class was then re-parsed by the file-level catch-all: the class and its
/// methods vanished, and a method written after the offending one re-attached
/// to the FILE. The parse reported success throughout.
test "keyword bodies: ruby super/self/alias keep the class and its methods" {
  let registry = get_fixture_registry()
  let path = "top.rb"
  let source =
    #|# Doc for Top.
    #|class Top
    #|  def initialize(x)
    #|    super()
    #|    @x = x
    #|  end
    #|
    #|  def label
    #|    self.class.name
    #|  end
    #|
    #|  alias name label
    #|
    #|  def after
    #|    1
    #|  end
    #|end
  let names = kwb_names(registry, "ruby", source, path)
  assert_eq(names.get("Top"), Some("Class"))
  assert_eq(names.get("initialize"), Some("Method"))
  assert_eq(names.get("label"), Some("Method"))
  // `after` is written after the `alias`; it must still belong to the class.
  assert_eq(names.get("after"), Some("Method"))
  assert_eq(
    kwb_owner_of(registry, "ruby", source, path, "after"),
    "top.rb::Top",
  )
}

///|
/// A top-level class carried no doc, while a nested one did: the file-level
/// item rule listed a bare comment alternative BEFORE the declarations, and
/// PEG ordered choice takes the first match, so the doc block was consumed as
/// a standalone item before the class could capture it.
test "keyword bodies: ruby top-level class captures its doc comment" {
  let registry = get_fixture_registry()
  let path = "doc.rb"
  let source =
    #|# A documented top-level class.
    #|class Documented
    #|  # A documented method.
    #|  def run
    #|    1
    #|  end
    #|end
  assert_eq(
    kwb_doc_of(registry, "ruby", source, path, "Documented"),
    "# A documented top-level class.",
  )
}

///|
/// Every other keyword a body may contain, in one method each, plus the
/// literal and operator forms that the lexer previously could not place.
/// `Tail` at the end is the witness: if any construct above truncated the
/// parse, the trailing class would be gone.
test "keyword bodies: ruby absorbs every body keyword and literal form" {
  let registry = get_fixture_registry()
  let path = "hard.rb"
  let source =
    #|class Report
    #|  TAGS = %w[alpha beta].freeze
    #|  KEYS = %i[id name]
    #|
    #|  def render(title)
    #|    header = <<~EOS
    #|      == #{title} ==
    #|      end of header
    #|    EOS
    #|    begin
    #|      rows.each do |line|
    #|        next if line.empty?
    #|        header << line
    #|      end
    #|    rescue StandardError => e
    #|      retry if e.message == "again"
    #|      raise
    #|    ensure
    #|      @done = true
    #|    end
    #|    header
    #|  end
    #|
    #|  def kind(row)
    #|    case row[:type]
    #|    when :a then "A"
    #|    else "other"
    #|    end
    #|  end
    #|
    #|  def summary
    #|    return "none" unless @rows.any?
    #|    @rows&.first&.fetch(:name)
    #|  end
    #|
    #|  def each_row
    #|    return to_enum(:each_row) unless block_given?
    #|    @rows.each { |r| yield r }
    #|  end
    #|
    #|  LOADER = -> (x) { x.to_s }
    #|
    #|  def self.build(rows)
    #|    new(rows)
    #|  end
    #|end
    #|
    #|class Tail
    #|  def ping
    #|    :pong
    #|  end
    #|end
  assert_true(kwb_lexes_cleanly(registry, "ruby", source))
  let names = kwb_names(registry, "ruby", source, path)
  for m in ["render", "kind", "summary", "each_row", "build"] {
    assert_eq(names.get(m), Some("Method"))
    assert_eq(
      kwb_owner_of(registry, "ruby", source, path, m),
      "hard.rb::Report",
    )
  }
  // The trailing class proves nothing above swallowed the rest of the file.
  assert_eq(names.get("Tail"), Some("Class"))
  assert_eq(names.get("ping"), Some("Method"))
}

// ─── C#: interpolated and raw string literals ───────────────

///|
/// The `$` of the interpolated-string alternative was unescaped, so the regexp
/// engine read it as the end-of-input anchor and the alternative could never
/// match: every `$"…"` in a file was left as unrecognised input.
test "keyword bodies: csharp interpolated and raw strings lex cleanly" {
  let registry = get_fixture_registry()
  let path = "S.cs"
  let source =
    #|public class S {
    #|  public string A(int id) { return $"user {id} ok"; }
    #|  public string B() { return @"c:\tmp\x"; }
    #|  public string C(int n) { return $@"path\{n}\end"; }
    #|  public string D(int n) { return @$"alt\{n}\end"; }
    #|  public string E() { return """raw "quoted" text"""; }
    #|  public string F() { return @"he said ""hi"" loudly"; }
    #|}
  assert_true(kwb_lexes_cleanly(registry, "csharp", source))
  let names = kwb_names(registry, "csharp", source, path)
  for m in ["A", "B", "C", "D", "E", "F"] {
    assert_eq(names.get(m), Some("Method"))
  }
}

///|
/// A quote inside an interpolation hole must not end the string.
test "keyword bodies: csharp interpolation may contain a quoted expression" {
  let registry = get_fixture_registry()
  let path = "Q.cs"
  let source =
    #|public class Q {
    #|  public string Go(System.Collections.Generic.Dictionary<string,string> m) {
    #|    return $"v={m["key"]}";
    #|  }
    #|  public int After() { return 1; }
    #|}
  assert_true(kwb_lexes_cleanly(registry, "csharp", source))
  let names = kwb_names(registry, "csharp", source, path)
  assert_eq(names.get("Go"), Some("Method"))
  // `After` is the witness that the string ended where it should have.
  assert_eq(names.get("After"), Some("Method"))
}

// ─── Kotlin: string templates ───────────────────────────────

///|
/// The string token admitted `$ident` but explicitly EXCLUDED `${`, so a
/// braced template ended the string early: the rest of the line lexed as code,
/// the quote that really closed it opened a new string running to the next
/// quote lines below, and every declaration in between disappeared.
test "keyword bodies: kotlin string templates keep later declarations" {
  let registry = get_fixture_registry()
  let path = "G.kt"
  let source =
    #|class Greeter(val name: String) {
    #|    fun simple(): String = "hello $name"
    #|    fun braced(n: Int): String = "count ${n + 1}"
    #|    fun nested(m: Map<String, String>): String = "v=${m["key"]}"
    #|    fun raw(): String = """
    #|        name: $name
    #|        size: ${name.length}
    #|    """
    #|    fun after(): String = "x"
    #|}
  assert_true(kwb_lexes_cleanly(registry, "kotlin", source))
  let names = kwb_names(registry, "kotlin", source, path)
  for m in ["simple", "braced", "nested", "raw", "after"] {
    assert_eq(names.get(m), Some("Method"))
  }
}

// ─── C / C++: extern "C", qualifiers, typedef tags ──────────

///|
/// An `extern "C" { … }` block had no rule of its own, so it fell to the
/// module-level fallback, which takes a balanced brace group as ONE opaque
/// unit. Every declaration between the braces was dropped — and that block is
/// the entire body of a C-compatible header.
test "keyword bodies: cpp extern C block declares its contents" {
  let registry = get_fixture_registry()
  let path = "api.h"
  let source =
    #|extern "C" {
    #|
    #|/** Creates a thing. */
    #|int thing_create(int capacity);
    #|
    #|/** Destroys a thing. */
    #|void thing_destroy(int handle);
    #|
    #|}
  let names = kwb_names(registry, "cpp", source, path)
  assert_eq(names.get("thing_create"), Some("Function"))
  assert_eq(names.get("thing_destroy"), Some("Function"))
  assert_eq(
    kwb_doc_of(registry, "cpp", source, path, "thing_create"),
    " Creates a thing. ",
  )
}

///|
/// The same block written the way a real header guards it, with the braces
/// split across `#ifdef __cplusplus` directives.
test "keyword bodies: c header guarded extern C declares its contents" {
  let registry = get_fixture_registry()
  let path = "buf.h"
  let source =
    #|#ifndef BUF_H
    #|#define BUF_H
    #|
    #|#ifdef __cplusplus
    #|extern "C" {
    #|#endif
    #|
    #|int buf_create(int capacity);
    #|void buf_destroy(int handle);
    #|
    #|#ifdef __cplusplus
    #|}
    #|#endif
    #|
    #|#endif
  let names = kwb_names(registry, "c", source, path)
  assert_eq(names.get("buf_create"), Some("Function"))
  assert_eq(names.get("buf_destroy"), Some("Function"))
}

///|
/// An out-of-line member definition names its owner in the qualifier. The
/// handler ignored both the qualifier and the enclosing namespace, so every
/// such definition was published as a fresh FILE-LEVEL function and the type
/// it belongs to was lost.
test "keyword bodies: cpp out-of-line definitions attach to their owner" {
  let registry = get_fixture_registry()
  let path = "c.cpp"
  let source =
    #|namespace app {
    #|
    #|Config Config::load() {
    #|    return Config{};
    #|}
    #|
    #|int Config::port() const {
    #|    return 8080;
    #|}
    #|
    #|Config::Config() {}
    #|
    #|}
  assert_eq(
    kwb_owner_of(registry, "cpp", source, path, "load"),
    "c.cpp::app::Config",
  )
  assert_eq(
    kwb_owner_of(registry, "cpp", source, path, "port"),
    "c.cpp::app::Config",
  )
  // The out-of-line constructor has no return type, so it cannot match the
  // function rule at all; with no handler of its own it produced no edge.
  assert_eq(
    kwb_owner_of(registry, "cpp", source, path, "Config"),
    "c.cpp::app::Config",
  )
}

///|
/// A typedef'd tag inside a namespace was published at FILE level while a
/// tagged declaration beside it nested correctly — the same header produced
/// two different id shapes depending only on which spelling was used.
test "keyword bodies: cpp typedef tag nests under its namespace" {
  let registry = get_fixture_registry()
  let path = "t.cpp"
  let source =
    #|namespace app {
    #|typedef struct PointTag { int x; } Point;
    #|struct Plain { int y; };
    #|typedef enum ColorTag { RED } Color;
    #|}
  assert_eq(kwb_owner_of(registry, "cpp", source, path, "Point"), "t.cpp::app")
  assert_eq(kwb_owner_of(registry, "cpp", source, path, "Plain"), "t.cpp::app")
  assert_eq(kwb_owner_of(registry, "cpp", source, path, "Color"), "t.cpp::app")
}
