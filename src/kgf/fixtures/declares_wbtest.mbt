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
    let lang = entry[0:entry.length() - 4].to_string()
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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

// ─── Go ─────────────────────────────────────────────────────

///|
test "declares: go exported func and type" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let path = "fixtures/programming/dart/task.dart"
  let source = @fs.read_file_to_string(path)
  let (_, _, names) = count_declares(registry, "dart", source, path)
  assert_true(names.get("Task") == Some("class"))
}

// ─── OCaml ──────────────────────────────────────────────────

///|
test "declares: ocaml task store fixture values and types" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
  let source =
    #|type status = Pending | Done
  let (_, _, names) = count_declares(registry, "ocaml", source, "task_store.ml")
  assert_true(names.get("status") == Some("type"))
}

// ─── Protobuf ──────────────────────────────────────────────

///|
test "declares: protobuf message, enum, service, rpc" {
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
  let registry = @registry.KGFRegistry::load_from_dir(get_kgfs_dir())
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
