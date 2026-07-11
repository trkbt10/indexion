///|
/// Tests for KGF semantics `declares` edge extraction across all supported languages.
/// Validates that `extract_pub_declarations_and_doc_map` produces correct
/// function and type counts for realistic fixture code.

///|
/// Helper: run the full KGF pipeline on inline source and count declares edges.
/// Returns (fn_count, type_count, names_set).
fn count_declares(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> (Int, Int, Map[String, String]) {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  let peg = @peg.build_peg(spec) catch { _ => return (0, 0, {}) }
  let start_rule = spec.get_start_rule()
  let parse_result = match @peg.run_parse(peg, spec, start_rule, tokens) {
    Some(r) => r
    None => return (0, 0, {})
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @semantics.SemEvalCtx::new(spec, graph, path, "", lang, fn(_) {
    false
  })
  for event in parse_result.get_events() {
    @semantics.eval_rule_semantics(event.0, event.1, ctx)
  }
  let function_kinds : Array[String] = match
    spec.get_feature("function_kinds") {
    Some(kinds) => kinds
    None => []
  }
  let mut fn_count = 0
  let mut type_count = 0
  let names : Map[String, String] = {}
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    let name = edge.attrs.get("name").unwrap_or("")
    let kind = edge.attrs.get("kind").unwrap_or("")
    if function_kinds.iter().any(fn(k) { k == kind }) {
      fn_count += 1
    } else {
      type_count += 1
    }
    names.set(name, @features.to_lower_str(kind))
  }
  (fn_count, type_count, names)
}

///|
fn programming_langs_from_kgfs() -> Map[String, Bool] {
  let langs : Map[String, Bool] = {}
  let entries = @fs.read_dir("kgfs/programming") catch { _ => [] }
  for entry in entries {
    if !entry.has_suffix(".kgf") {
      continue
    }
    let lang = entry[0:entry.length() - 4].to_owned()
    langs.set(lang, true)
  }
  langs
}

///|
test "declares: semantics coverage includes every programming kgf" {
  let covered = [
    "c", "clojure", "cpp", "csharp", "dart", "elixir", "go", "haskell", "java", "javascript",
    "javascript-jsx", "julia", "kotlin", "lua", "moonbit", "ocaml", "php", "protobuf",
    "python", "ruby", "rust", "scala", "swift", "typescript", "typescript-jsx", "zig",
  ]
  let langs = programming_langs_from_kgfs()
  assert_eq(langs.length(), covered.length())
  for lang in covered {
    assert_true(langs.contains(lang))
  }
}

// ─── MoonBit ────────────────────────────────────────────────

///|
test "declares: moonbit pub fn and pub struct" {
  let registry = get_fixture_registry()
  let source =
    #|pub struct ParsedValue {
    #|  value : Int
    #|  source : String
    #|}
    #|
    #|pub fn parse(input : String) -> Result[Int, String] {
    #|  Ok(42)
    #|}
    #|
    #|pub fn format(n : Int) -> String {
    #|  n.to_string()
    #|}
    #|
    #|fn private_helper() -> Unit { () }
  let (fn_count, type_count, names) = count_declares(
    registry, "moonbit", source, "lib.mbt",
  )
  assert_eq(fn_count, 2)
  assert_eq(type_count, 1)
  assert_true(names.get("parse") == Some("function"))
  assert_true(names.get("format") == Some("function"))
  assert_true(names.get("ParsedValue") == Some("struct"))
  // private_helper should NOT be in declares edges
  assert_true(!names.contains("private_helper"))
}

// ─── Rust ───────────────────────────────────────────────────

///|
test "declares: rust pub fn and pub struct" {
  let registry = get_fixture_registry()
  let source =
    #|/// Application configuration.
    #|pub struct Config {
    #|    pub name: String,
    #|}
    #|
    #|impl Config {
    #|    pub fn load() -> Self {
    #|        Config { name: "default".to_string() }
    #|    }
    #|}
    #|
    #|fn private_fn() {}
  let (fn_count, type_count, names) = count_declares(
    registry, "rust", source, "config.rs",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 1)
  assert_true(names.get("load") == Some("function"))
  assert_true(names.get("Config") == Some("struct"))
  assert_true(!names.contains("private_fn"))
}

///|
/// Regression test for real-world Rust that exercises the constructs the
/// lexer/grammar previously mishandled: an outer `#[derive(...)]` attribute
/// (which used to abort the whole parse), `&self` receivers, reference
/// parameters/returns (`&str`, `&[u8]`), a raw-pointer parameter (`*const`),
/// and `pub const` / `pub type` declarations whose `=` was shadowed by the
/// generic `Operator` token. Before the fix, most of these items were
/// silently dropped from the graph.
test "declares: rust attributes, references, const and type alias" {
  let registry = get_fixture_registry()
  let source =
    #|//! Module documentation.
    #|use std::fmt;
    #|
    #|/// An absolute path, stored as raw bytes.
    #|#[derive(Clone, PartialEq, Eq, Hash)]
    #|pub struct RemotePath(Vec<u8>);
    #|
    #|pub const MAX_LEN: usize = 4096;
    #|
    #|pub type Bytes = Vec<u8>;
    #|
    #|impl RemotePath {
    #|    pub fn root() -> Self {
    #|        RemotePath(Vec::new())
    #|    }
    #|
    #|    pub fn as_bytes(&self) -> &[u8] {
    #|        &self.0
    #|    }
    #|
    #|    pub fn from_str(s: &str) -> Self {
    #|        RemotePath(s.as_bytes().to_vec())
    #|    }
    #|
    #|    pub unsafe fn from_raw(p: *const u8) -> Self {
    #|        RemotePath(Vec::new())
    #|    }
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "rust", source, "path.rs",
  )
  // Four methods survive the whole impl body now that references parse.
  assert_eq(fn_count, 4)
  // Struct + const + type alias.
  assert_eq(type_count, 3)
  assert_true(names.get("RemotePath") == Some("struct"))
  assert_true(names.get("MAX_LEN") == Some("const"))
  assert_true(names.get("Bytes") == Some("type"))
  assert_true(names.get("root") == Some("function"))
  assert_true(names.get("as_bytes") == Some("function"))
  assert_true(names.get("from_str") == Some("function"))
  assert_true(names.get("from_raw") == Some("function"))
}

///|
/// Regression test for Rust generic/lexer corner cases: nested generics that
/// close with adjacent `>` (`Vec<Option<f32>>`), a lifetime used as a generic
/// argument (`Ctx<'a>`), doc comments and `#[attr]`s on struct fields in
/// either order, and an enum whose variant is literally named `None` (a
/// prelude value constructor, not a type). Each of these used to abort the
/// parse and drop the enclosing item.
test "declares: rust nested generics, lifetimes, doc-fields, None variant" {
  let registry = get_fixture_registry()
  let source =
    #|use std::collections::{
    #|    HashMap,
    #|    BTreeMap,
    #|};
    #|
    #|/// Aggregated per-core stats.
    #|#[derive(Debug, Clone, Default)]
    #|pub struct Stats {
    #|    /// Busy percentage per core.
    #|    pub per_core: Vec<Option<f32>>,
    #|    #[serde(default)]
    #|    /// Attribute precedes the doc here.
    #|    pub table: HashMap<String, Vec<u32>>,
    #|}
    #|
    #|impl Stats {
    #|    pub fn view<'a>(&'a self, ctx: &Ctx<'a>) -> &'a [u8] {
    #|        &self.raw
    #|    }
    #|}
    #|
    #|/// Which splits are allowed.
    #|#[derive(Copy, Clone)]
    #|pub enum Allowed {
    #|    #[default]
    #|    /// No restriction.
    #|    All = 0b11,
    #|    /// Nothing is allowed.
    #|    None = 0b00,
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "rust", source, "stats.rs",
  )
  assert_eq(fn_count, 1) // view
  assert_eq(type_count, 2) // Stats + Allowed
  assert_true(names.get("Stats") == Some("struct"))
  assert_true(names.get("view") == Some("function"))
  assert_true(names.get("Allowed") == Some("enum"))
}

///|
/// Regression test for two real-world idioms that used to silently drop the
/// enclosing declaration: (1) the conventional member ordering where a `///`
/// doc comment PRECEDES an `#[attr]` on its own line, and (2) declarations
/// named after prelude type words — the near-universal `pub type Result<T>`
/// alias and an enum whose variant/field is named `String`. The whole
/// struct/enum/alias was lost before, so this asserts they all appear.
test "declares: rust doc-before-attr member and type-word identifiers" {
  let registry = get_fixture_registry()
  let source =
    #|pub type Result<T> = std::result::Result<T, Error>;
    #|
    #|/// Configuration.
    #|pub struct Config {
    #|    /// The name.
    #|    #[serde(default)]
    #|    pub name: String,
    #|}
    #|
    #|/// A JSON value.
    #|pub enum Value {
    #|    /// A string payload.
    #|    #[serde(rename = "str")]
    #|    String(String),
    #|    Number(f64),
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "rust", source, "json.rs",
  )
  ignore(fn_count)
  assert_eq(type_count, 3) // Result alias + Config struct + Value enum
  assert_true(names.get("Result") == Some("type"))
  assert_true(names.get("Config") == Some("struct"))
  assert_true(names.get("Value") == Some("enum"))
}

// ─── Go ─────────────────────────────────────────────────────

///|
test "declares: go exported func and type" {
  let registry = get_fixture_registry()
  let source =
    #|package server
    #|
    #|type Server struct {
    #|	router string
    #|}
    #|
    #|func New() *Server {
    #|	return &Server{}
    #|}
    #|
    #|func (s *Server) Run(addr string) error {
    #|	return nil
    #|}
    #|
    #|func helper() {}
  let (fn_count, type_count, names) = count_declares(
    registry, "go", source, "server.go",
  )
  assert_eq(fn_count, 2)
  assert_eq(type_count, 1)
  assert_true(names.get("New") == Some("function"))
  assert_true(names.get("Run") == Some("function"))
  assert_true(names.get("Server") == Some("type"))
  // lowercase helper should NOT be exported
  assert_true(!names.contains("helper"))
}

// ─── TypeScript ─────────────────────────────────────────────

///|
test "declares: typescript function and interface" {
  let registry = get_fixture_registry()
  let source =
    #|export function formatClassName(base: string, variant: string): string {
    #|  return `${base}-${variant}`;
    #|}
    #|
    #|export interface Config {
    #|  host: string;
    #|  port: number;
    #|}
    #|
    #|function privateHelper() {}
  let (fn_count, type_count, names) = count_declares(
    registry, "typescript", source, "utils.ts",
  )
  // TS semantics emits declares for all top-level declarations (no vis filter)
  assert_eq(fn_count, 2)
  assert_eq(type_count, 1)
  assert_true(names.get("formatClassName") == Some("function"))
  assert_true(names.get("Config") == Some("interface"))
  assert_true(names.get("privateHelper") == Some("function"))
}

// ─── TSX / JSX / Clojure ───────────────────────────────────

///|
test "declares: typescript-jsx jsx component and interface" {
  let registry = get_fixture_registry()
  let source =
    #|export interface Props {
    #|  title: string;
    #|}
    #|
    #|export function App(props: Props) {
    #|  return <Main title={props.title} />;
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "typescript-jsx", source, "app.tsx",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 1)
  assert_true(names.get("App") == Some("function"))
  assert_true(names.get("Props") == Some("interface"))
}

///|
test "declares: javascript-jsx function component and class" {
  let registry = get_fixture_registry()
  let source =
    #|function App() {
    #|  return <Box />;
    #|}
    #|
    #|class LocalBox {}
  let (fn_count, type_count, names) = count_declares(
    registry, "javascript-jsx", source, "app.jsx",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 1)
  assert_true(names.get("App") == Some("function"))
  assert_true(names.get("LocalBox") == Some("class"))
}

///|
test "declares: clojure def defn defmacro" {
  let registry = get_fixture_registry()
  let source =
    #|(def visible-value 1)
    #|(defn visible-fn [name]
    #|  name)
    #|(defmacro visible-macro [x] x)
  let (fn_count, type_count, names) = count_declares(
    registry, "clojure", source, "sample.clj",
  )
  assert_eq(fn_count, 2)
  assert_eq(type_count, 1)
  assert_true(names.get("visible-value") == Some("var"))
  assert_true(names.get("visible-fn") == Some("function"))
  assert_true(names.get("visible-macro") == Some("macro"))
}

///|
test "declares: clojure protocol record type multimethod method" {
  let registry = get_fixture_registry()
  let source =
    #|(defprotocol VisibleProtocol)
    #|(defrecord VisibleRecord)
    #|(deftype VisibleType)
    #|(defmulti visible-dispatch)
    #|(defmethod visible-method)
  let (fn_count, type_count, names) = count_declares(
    registry, "clojure", source, "extended.clj",
  )
  assert_eq(fn_count, 2)
  assert_eq(type_count, 3)
  assert_true(names.get("VisibleProtocol") == Some("protocol"))
  assert_true(names.get("VisibleRecord") == Some("record"))
  assert_true(names.get("VisibleType") == Some("type"))
  assert_true(names.get("visible-dispatch") == Some("multimethod"))
  assert_true(names.get("visible-method") == Some("method"))
}

// ─── Python ─────────────────────────────────────────────────

///|
test "declares: python def and class" {
  let registry = get_fixture_registry()
  let source =
    #|class User:
    #|    name: str
    #|    email: str
    #|
    #|class Project:
    #|    id: str
    #|
    #|def create_client(api_key: str):
    #|    return None
  let (fn_count, type_count, names) = count_declares(
    registry, "python", source, "app.py",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 2)
  assert_true(names.get("create_client") == Some("function"))
  assert_true(names.get("User") == Some("class"))
  assert_true(names.get("Project") == Some("class"))
}

// ─── Java ───────────────────────────────────────────────────

///|
test "declares: java public class and method" {
  let registry = get_fixture_registry()
  let source =
    #|public class Service {
    #|    public String process(String input) {
    #|        return input.trim();
    #|    }
    #|    private void validate(String input) {}
    #|}
    #|
    #|public record UserRecord(String name, int age) {}
  let (fn_count, type_count, names) = count_declares(
    registry, "java", source, "Service.java",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 2)
  assert_true(names.get("process") == Some("method"))
  assert_true(names.get("Service") == Some("class"))
  assert_true(names.get("UserRecord") == Some("record"))
  assert_true(!names.contains("validate"))
}

// ─── C# ─────────────────────────────────────────────────────

///|
test "declares: csharp public class, interface, method" {
  let registry = get_fixture_registry()
  let source =
    #|public class User
    #|{
    #|    public string GetDisplayName() { return ""; }
    #|}
    #|
    #|public interface IValidator
    #|{
    #|    bool Validate(string input);
    #|}
    #|
    #|internal class InternalHelper
    #|{
    #|    private void DoSomething() { }
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "csharp", source, "Models.cs",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 2)
  assert_true(names.get("GetDisplayName") == Some("method"))
  assert_true(names.get("User") == Some("class"))
  assert_true(names.get("IValidator") == Some("interface"))
  assert_true(!names.contains("InternalHelper"))
  assert_true(!names.contains("DoSomething"))
}

// ─── Swift ──────────────────────────────────────────────────

///|
test "declares: swift public struct, protocol, func" {
  let registry = get_fixture_registry()
  let source =
    #|public struct User {
    #|    public let name: String
    #|    public func displayName() -> String { return name }
    #|}
    #|
    #|public protocol Validator {
    #|    func validate(_ input: Any) -> Bool
    #|}
    #|
    #|internal class InternalHelper {}
  let (fn_count, type_count, names) = count_declares(
    registry, "swift", source, "Models.swift",
  )
  assert_eq(fn_count, 1)
  assert_eq(type_count, 2)
  assert_true(names.get("displayName") == Some("function"))
  assert_true(names.get("User") == Some("struct"))
  assert_true(names.get("Validator") == Some("protocol"))
  assert_true(!names.contains("InternalHelper"))
}

// ─── Ruby ───────────────────────────────────────────────────

///|
test "declares: ruby class, module, public methods" {
  let registry = get_fixture_registry()
  let source =
    #|module Calculator
    #|  class Basic
    #|    def add(a, b)
    #|      a + b
    #|    end
    #|
    #|    private
    #|
    #|    def validate_input(value)
    #|      value
    #|    end
    #|  end
    #|end
  let (_, _, names) = count_declares(registry, "ruby", source, "calculator.rb")
  assert_true(names.get("Calculator") == Some("module"))
  assert_true(names.get("Basic") == Some("class"))
  assert_true(names.get("add") == Some("method"))
  // validate_input is private — should NOT be in declares edges
  assert_true(!names.contains("validate_input"))
}

// ─── PHP ────────────────────────────────────────────────────

///|
test "declares: php class and function" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|class UserService
    #|{
    #|    public function findById(int $id) { return null; }
    #|}
    #|
    #|function createUserService(string $host) { return new UserService(); }
  let (fn_count, type_count, names) = count_declares(
    registry, "php", source, "helpers.php",
  )
  assert_true(names.get("UserService") == Some("class"))
  assert_true(names.get("createUserService") == Some("function"))
  assert_true(type_count >= 1)
  assert_true(fn_count >= 1)
}

// ─── Kotlin ─────────────────────────────────────────────────

///|
test "declares: kotlin class and fun" {
  let registry = get_fixture_registry()
  let source =
    #|class UserService {
    #|    fun findById(id: Int): String? = null
    #|}
    #|
    #|interface Repository {
    #|    fun getAll(): List<String>
    #|}
    #|
    #|fun createService(): UserService = UserService()
  let (_, _, names) = count_declares(registry, "kotlin", source, "Service.kt")
  assert_true(names.get("UserService") == Some("class"))
  assert_true(names.get("Repository") == Some("interface"))
  assert_true(names.get("createService") == Some("function"))
}

// ─── Scala ──────────────────────────────────────────────────

///|
test "declares: scala class, trait, def" {
  let registry = get_fixture_registry()
  let source =
    #|class UserService {
    #|  def findById(id: Int): Option[String] = None
    #|}
    #|
    #|trait Repository {
    #|  def getAll(): List[String]
    #|}
  let (_, _, names) = count_declares(registry, "scala", source, "Service.scala")
  assert_true(names.get("UserService") == Some("class"))
  assert_true(names.get("Repository") == Some("trait"))
  assert_true(names.get("findById") == Some("def"))
}

// ─── Zig ────────────────────────────────────────────────────

///|
test "declares: zig pub fn" {
  let registry = get_fixture_registry()
  let source =
    #|pub fn load() void {
    #|    return;
    #|}
    #|
    #|fn private_fn() void {}
  let (fn_count, type_count, names) = count_declares(
    registry, "zig", source, "config.zig",
  )
  assert_true(names.get("load") == Some("function"))
  assert_true(!names.contains("private_fn"))
  assert_true(fn_count >= 1)
  ignore(type_count)
}

// ─── JavaScript ─────────────────────────────────────────────

///|
test "declares: javascript function" {
  let registry = get_fixture_registry()
  let source =
    #|function greet(name) {
    #|  return "Hello";
    #|}
    #|
    #|function helper() {
    #|  return 42;
    #|}
  let (_fn_count, _type_count, names) = count_declares(
    registry, "javascript", source, "app.js",
  )
  assert_true(names.get("greet") == Some("function"))
  assert_true(names.get("helper") == Some("function"))
}

// ─── C ──────────────────────────────────────────────────────

///|
test "declares: c struct and function" {
  let registry = get_fixture_registry()
  let source =
    #|struct Point {
    #|    int x;
    #|    int y;
    #|};
    #|
    #|int add(int a, int b) {
    #|    return a + b;
    #|}
  let (_, _, names) = count_declares(registry, "c", source, "math.c")
  assert_true(names.get("Point") == Some("struct"))
  assert_true(names.get("add") == Some("function"))
}

// ─── C++ ────────────────────────────────────────────────────

///|
test "declares: cpp class, namespace, function" {
  let registry = get_fixture_registry()
  let source =
    #|namespace app {
    #|
    #|class Server {
    #|public:
    #|    void run();
    #|};
    #|
    #|}
  let (_, _, names) = count_declares(registry, "cpp", source, "server.cpp")
  assert_true(names.get("app") == Some("namespace"))
  assert_true(names.get("Server") == Some("class"))
}

// ─── Haskell ────────────────────────────────────────────────

///|
test "declares: haskell data and function" {
  let registry = get_fixture_registry()
  let source =
    #|data Color = Red | Green | Blue
    #|
    #|show_color :: Color -> String
    #|show_color Red = "red"
  let (_, _, names) = count_declares(registry, "haskell", source, "Color.hs")
  assert_true(names.get("Color") == Some("data"))
  assert_true(names.get("show_color") == Some("function"))
}

// ─── Elixir ─────────────────────────────────────────────────

///|
test "declares: elixir tokenize and parse" {
  let registry = get_fixture_registry()
  // Basic parsing test — Elixir's def/defp visibility filtering
  // uses vis:( KW_def / KW_defp ) label with eq($vis, "def") condition
  let spec = registry.get_spec("elixir").unwrap()
  let source = "def add(a, b) do\n  a + b\nend\n"
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let tokens = lexer.tokenize(source)
  assert_true(tokens.length() > 0)
  assert_true(tokens.iter().any(fn(t) { t.kind == "KW_def" }))
  assert_true(tokens.iter().any(fn(t) { t.kind == "Ident" && t.text == "add" }))
}

// ─── Lua ────────────────────────────────────────────────────

///|
test "declares: lua global function" {
  let registry = get_fixture_registry()
  let source =
    #|function greet(name)
    #|  return "Hello, " .. name
    #|end
    #|
    #|local function helper()
    #|  return 42
    #|end
  let (_, _, names) = count_declares(registry, "lua", source, "greet.lua")
  assert_true(names.get("greet") == Some("function"))
  // local functions are private — should NOT be in declares
  assert_true(!names.contains("helper"))
}

// ─── Dart ───────────────────────────────────────────────────

///|
test "declares: dart task fixture class" {
  let registry = get_fixture_registry()
  let path = "fixtures/programming/dart/task.dart"
  let source = @fs.read_file_to_string(path)
  let (_, _, names) = count_declares(registry, "dart", source, path)
  assert_true(names.get("Task") == Some("class"))
}

// ─── OCaml ──────────────────────────────────────────────────

///|
test "declares: ocaml task store fixture values and types" {
  let registry = get_fixture_registry()
  let source =
    #|type status = Pending | Done
  let (_, _, names) = count_declares(registry, "ocaml", source, "task_store.ml")
  assert_true(names.get("status") == Some("type"))
}

// ─── Protobuf ──────────────────────────────────────────────

///|
test "declares: protobuf message, enum, service, rpc" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto3";
    #|
    #|package example.api;
    #|
    #|import "google/protobuf/timestamp.proto";
    #|
    #|// User account service.
    #|service UserService {
    #|  // Create a new user.
    #|  rpc CreateUser (CreateUserRequest) returns (UserResponse);
    #|
    #|  // Get user by ID.
    #|  rpc GetUser (GetUserRequest) returns (UserResponse);
    #|}
    #|
    #|// Request to create a user.
    #|message CreateUserRequest {
    #|  string name = 1;
    #|  string email = 2;
    #|  Role role = 3;
    #|}
    #|
    #|message GetUserRequest {
    #|  string user_id = 1;
    #|}
    #|
    #|// User information.
    #|message UserResponse {
    #|  string id = 1;
    #|  string name = 2;
    #|  string email = 3;
    #|  Role role = 4;
    #|  google.protobuf.Timestamp created_at = 5;
    #|}
    #|
    #|// User role.
    #|enum Role {
    #|  ROLE_UNSPECIFIED = 0;
    #|  ROLE_ADMIN = 1;
    #|  ROLE_USER = 2;
    #|}
  let (fn_count, type_count, names) = count_declares(
    registry, "protobuf", source, "user.proto",
  )
  // rpc edges have kind="Rpc", function_kinds=["Method"] so they count as types here
  assert_eq(fn_count, 0)
  // messages (3) + enum (1) + service (1) + rpc (2) = 7
  assert_eq(type_count, 7)
  assert_true(names.get("UserService") == Some("service"))
  assert_true(names.get("CreateUser") == Some("rpc"))
  assert_true(names.get("GetUser") == Some("rpc"))
  assert_true(names.get("CreateUserRequest") == Some("message"))
  assert_true(names.get("GetUserRequest") == Some("message"))
  assert_true(names.get("UserResponse") == Some("message"))
  assert_true(names.get("Role") == Some("enum"))
}

///|
test "declares: protobuf keyword as field name" {
  let registry = get_fixture_registry()
  let source =
    #|syntax = "proto3";
    #|
    #|// Event with keyword field names.
    #|message Event {
    #|  string message = 1;
    #|  string service = 2;
    #|  int32 enum = 3;
    #|  bool optional = 4;
    #|}
  let (_fn_count, type_count, names) = count_declares(
    registry, "protobuf", source, "event.proto",
  )
  assert_eq(type_count, 1)
  assert_true(names.get("Event") == Some("message"))
}

// ─── Julia ──────────────────────────────────────────────────

///|
test "declares: julia task store fixture module and function" {
  let registry = get_fixture_registry()
  let source =
    #|struct Task
    #|    id::Int
    #|end
    #|
    #|function add!(x)
    #|    x
    #|end
  let (_, _, names) = count_declares(registry, "julia", source, "task_store.jl")
  assert_true(names.get("Task") == Some("struct"))
  assert_true(names.get("add!") == Some("function"))
}
