///|
/// Regression tests for the systems and scripting KGF specs (c, cpp, zig, php,
/// typescript, typescript-jsx, javascript, javascript-jsx, clojure, ruby).
///
/// Each test pins one root cause that used to stop a spec's parse partway
/// through a file, or drop characters in the lexer. A partial parse is the
/// dangerous failure mode: the start rule still matches a prefix, so the file
/// looks analysed while every declaration after the stopping point is silently
/// missing. The tests therefore assert on the declarations that follow the
/// construct that used to break, not only on the construct itself.
///
/// Helpers carry a `sys_` prefix so they cannot clash with the ones in
/// declares_wbtest.mbt, which shares this package.

///|
/// Run the full KGF pipeline (lex, parse, semantics) on inline source and
/// return the resulting graph, or None when the parse fails outright.
fn sys_eval_source_graph(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> @graph.CodeGraph? {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
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
fn sys_declared_names(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Map[String, String] {
  let names : Map[String, String] = Map([])
  let graph = match sys_eval_source_graph(registry, lang, source, path) {
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
/// The `doc` attribute recorded for one declared name, or "" when the name has
/// no declares edge or carries no doc.
fn sys_doc_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  let graph = match sys_eval_source_graph(registry, lang, source, path) {
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
/// True when every character of the source matched some token rule. A character
/// that matches nothing is skipped silently, so the grammar sees a token stream
/// that no longer says what the author wrote.
fn sys_lexes_cleanly(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
) -> Bool {
  let spec = registry.get_spec(lang).unwrap()
  let lexer = @lexer.Lexer::new(spec.get_tokens())
  let (_, diagnostics) = lexer.tokenize_with_diagnostics(source)
  diagnostics.length() == 0
}

// ─── TypeScript / JavaScript ────────────────────────────────

///|
/// A top-level statement that is not a declaration — here a call whose argument
/// is an object literal — used to stop the module parse at its `{`, because the
/// module-level fallback accepted only non-bracket tokens. Everything declared
/// after such a statement was dropped.
test "declares: typescript top-level call with object literal argument" {
  let registry = get_fixture_registry()
  let source =
    #|const PORT = 8000;
    #|
    #|serve(router, { port: PORT });
    #|
    #|export function afterCall(): void {}
  let names = sys_declared_names(registry, "typescript", source, "main.ts")
  assert_true(names.get("PORT") == Some("Variable"))
  assert_true(names.get("afterCall") == Some("Function"))
}

///|
/// A call taking an arrow function with a block body has the same shape: the
/// `{` of the callback used to stop the parse.
test "declares: typescript top-level call with arrow function body" {
  let registry = get_fixture_registry()
  let source =
    #|test("round trips", () => {
    #|  assert(true);
    #|});
    #|
    #|export function afterTest(): void {}
  let names = sys_declared_names(registry, "typescript", source, "spec.ts")
  assert_true(names.get("afterTest") == Some("Function"))
}

///|
/// A regex literal is one token. Without a regex rule the body was shredded
/// into punctuation and its `^`, `@` and `\` characters were dropped by the
/// lexer entirely, so the surrounding file no longer matched what was written.
test "declares: typescript regex literal lexes as one token" {
  let registry = get_fixture_registry()
  let source =
    #|const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    #|
    #|export function validate(v: string): boolean {
    #|  return re.test(v);
    #|}
  assert_true(sys_lexes_cleanly(registry, "typescript", source))
  let names = sys_declared_names(registry, "typescript", source, "auth.ts")
  assert_true(names.get("re") == Some("Variable"))
  assert_true(names.get("validate") == Some("Function"))
}

///|
/// `%` had no token at all, so it was dropped silently and an expression using
/// it parsed as something the author did not write.
test "declares: typescript modulo operator lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|export function wrap(a: number, b: number): number {
    #|  return a % b;
    #|}
  assert_true(sys_lexes_cleanly(registry, "typescript", source))
  let names = sys_declared_names(registry, "typescript", source, "math.ts")
  assert_true(names.get("wrap") == Some("Function"))
}

///|
/// A class member's doc used to be captured on the wrapping ClassMember rule,
/// which left the member's own `$doc` unbound, so every method was reported
/// undocumented no matter what JSDoc preceded it.
test "declares: typescript method keeps its own doc comment" {
  let registry = get_fixture_registry()
  let source =
    #|export class Service {
    #|  /** Retrieves a user by ID. */
    #|  getUser(id: string): string {
    #|    return id;
    #|  }
    #|}
  let doc = sys_doc_of(registry, "typescript", source, "service.ts", "getUser")
  assert_true(doc.contains("Retrieves a user by ID"))
}

///|
/// An interface member signature carries its own doc label too. The spec emits
/// no declares edge for interface members, so this pins the parse instead: a
/// documented member must not stop the interface body, and the interface and
/// the declaration after it must both still be found.
test "declares: typescript documented interface member does not stop the body" {
  let registry = get_fixture_registry()
  let source =
    #|export interface Store {
    #|  /** Total number of records. */
    #|  size: number;
    #|  /** Look up one record. */
    #|  get(id: string): string;
    #|}
    #|
    #|export function afterInterface(): void {}
  let names = sys_declared_names(registry, "typescript", source, "store.ts")
  assert_true(names.get("Store") == Some("Interface"))
  assert_true(names.get("afterInterface") == Some("Function"))
}

///|
/// JSX text is prose and may hold any non-markup character. A symbol such as
/// `×` had no token, so the lexer dropped it and the element around it stopped
/// matching.
test "declares: typescript-jsx element text may hold symbols" {
  let registry = get_fixture_registry()
  let source =
    #|export function Modal({ onClose }: Props) {
    #|  return (
    #|    <header>
    #|      <h2>{title}</h2>
    #|      <Button onClick={onClose}>×</Button>
    #|    </header>
    #|  );
    #|}
  assert_true(sys_lexes_cleanly(registry, "typescript-jsx", source))
  let names = sys_declared_names(
    registry, "typescript-jsx", source, "Modal.tsx",
  )
  assert_true(names.get("Modal") == Some("Function"))
}

///|
/// The javascript spec carries the same fallback and regex rules as typescript.
test "declares: javascript top-level call with object literal argument" {
  let registry = get_fixture_registry()
  let source =
    #|configure({ retries: 3 });
    #|
    #|export function afterConfigure() {}
  let names = sys_declared_names(registry, "javascript", source, "main.js")
  assert_true(names.get("afterConfigure") == Some("Function"))
}

///|
test "declares: javascript method keeps its own doc comment" {
  let registry = get_fixture_registry()
  let source =
    #|export class Emitter {
    #|  /** Emits all queued events. */
    #|  flush() {}
    #|}
  let doc = sys_doc_of(registry, "javascript", source, "events.js", "flush")
  assert_true(doc.contains("Emits all queued events"))
}

// ─── C++ ────────────────────────────────────────────────────

///|
/// A namespace body accepted only a fixed list of members, with no fallback.
/// Any construct outside that list stopped the parse at the namespace's `{`,
/// so a file's entire contents were dropped.
test "declares: cpp namespace body keeps declaring after an unmodelled member" {
  let registry = get_fixture_registry()
  let source =
    #|namespace app {
    #|
    #|using Alias = int;
    #|
    #|struct Config {
    #|  bool debug;
    #|};
    #|
    #|}
  let names = sys_declared_names(registry, "cpp", source, "config.hpp")
  assert_true(names.get("app") == Some("Namespace"))
  assert_true(names.get("Config") == Some("Struct"))
}

///|
/// A declaration specifier is a sequence of built-in type words. `TypeAtom`
/// accepted only one, so `unsigned short` failed and took the whole enclosing
/// struct — and the namespace around it — down with it.
test "declares: cpp multi-word builtin type in a field" {
  let registry = get_fixture_registry()
  let source =
    #|struct Config {
    #|  unsigned short port;
    #|  bool debug;
    #|};
  let names = sys_declared_names(registry, "cpp", source, "config.hpp")
  assert_true(names.get("Config") == Some("Struct"))
}

///|
/// An out-of-line member definition names its owner (`Config::load`). The name
/// position accepted a bare identifier only, so these definitions never matched
/// and the file stopped at the enclosing namespace's brace.
test "declares: cpp out-of-line member definition" {
  let registry = get_fixture_registry()
  let source =
    #|namespace app {
    #|
    #|Config Config::load() {
    #|  return Config{};
    #|}
    #|
    #|void Server::run() {
    #|  io_.run();
    #|}
    #|
    #|}
  let names = sys_declared_names(registry, "cpp", source, "config.cpp")
  assert_true(names.get("load") == Some("Function"))
  assert_true(names.get("run") == Some("Function"))
}

///|
/// An out-of-line constructor has no return type, so it could not match the
/// function rule at all.
test "declares: cpp out-of-line constructor with initializer list" {
  let registry = get_fixture_registry()
  let source =
    #|namespace app {
    #|
    #|Server::Server(const Config& config) : config_(config) {}
    #|
    #|void Server::run() {}
    #|
    #|}
  let names = sys_declared_names(registry, "cpp", source, "server.cpp")
  assert_true(names.get("run") == Some("Function"))
}

///|
/// A C-style typedef'd tag may be anonymous, with the name after the body.
/// The `.h` extension is claimed by both the c and cpp specs and cpp wins, so
/// this C idiom has to parse under cpp.
test "declares: cpp anonymous typedef struct and enum" {
  let registry = get_fixture_registry()
  let source =
    #|typedef enum { OPEN, DONE } TodoStatus;
    #|typedef struct { double id; char * title; } Todo;
  let names = sys_declared_names(registry, "cpp", source, "all.h")
  assert_true(names.get("TodoStatus") == Some("Enum"))
  assert_true(names.get("Todo") == Some("Struct"))
}

///|
/// A preprocessor directive is one *logical* line: a backslash immediately
/// before the newline continues it onto the next physical line, which is how
/// any non-trivial macro is written. The token matched only the first physical
/// line, so the continuation lines were lexed as ordinary code and every
/// trailing backslash matched nothing at all — 232 dropped characters in a
/// single real-world header.
///
/// The character classes also have to stay unambiguous. A branch that lets a
/// backslash match two different ways makes this engine explore the
/// alternatives exponentially: one 915-line header went from 0.3s to 28s.
test "declares: cpp multi-line macro continuation lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|#define DEFINE_NAMED_STACK_OF(name, type)                    \
    #|  BORINGSSL_DEFINE_STACK_OF_IMPL(name, type *, const type *) \
    #|  BORINGSSL_DEFINE_STACK_TRAITS(name, type, false)
    #|
    #|struct Config {
    #|  bool debug;
    #|};
  assert_true(sys_lexes_cleanly(registry, "cpp", source))
  let names = sys_declared_names(registry, "cpp", source, "stack.h")
  assert_true(names.get("Config") == Some("Struct"))
}

///|
/// `#import` is a real directive (Objective-C, and Clang accepts it in C++).
/// It was missing from the directive list, so the `#` matched no token at all
/// and each import line produced a lexer error.
test "declares: cpp import directive lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|#import "Hashing.h"
    #|#import "Utils.h"
    #|
    #|struct Config {
    #|  bool debug;
    #|};
  assert_true(sys_lexes_cleanly(registry, "cpp", source))
  let names = sys_declared_names(registry, "cpp", source, "Hashing.cpp")
  assert_true(names.get("Config") == Some("Struct"))
}

// ─── C ──────────────────────────────────────────────────────

///|
/// `##` is the preprocessor token-paste operator. A macro body that uses
/// `/* */` comments as its line continuations ends the directive token early,
/// so the body is lexed as ordinary code — where `##` needs to be a token.
test "declares: c token paste operator lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|#define MAKE(type) /*
    #|*/ struct catmc_atomic_##type { /*
    #|*/     _Atomic type value; /*
    #|*/ };
    #|
    #|int area(int w, int h) {
    #|  return w * h;
    #|}
  assert_true(sys_lexes_cleanly(registry, "c", source))
  let names = sys_declared_names(registry, "c", source, "atomics.c")
  assert_true(names.get("area") == Some("Function"))
}

///|
/// The c spec shares the same preprocessor token.
test "declares: c multi-line macro continuation lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|#define SWAP(a, b) \
    #|  do { int t = (a); (a) = (b); (b) = t; } while (0)
    #|
    #|int area(int w, int h) {
    #|  return w * h;
    #|}
  assert_true(sys_lexes_cleanly(registry, "c", source))
  let names = sys_declared_names(registry, "c", source, "util.c")
  assert_true(names.get("area") == Some("Function"))
}

///|
test "declares: c multi-word builtin type in a field" {
  let registry = get_fixture_registry()
  let source =
    #|struct Config {
    #|  unsigned short port;
    #|};
  let names = sys_declared_names(registry, "c", source, "config.h")
  assert_true(names.get("Config") == Some("Struct"))
}

///|
/// A brace initializer is a balanced group. Without a rule for it the `{` of a
/// designated initializer stopped the module parse.
test "declares: c brace initializer does not stop the parse" {
  let registry = get_fixture_registry()
  let source =
    #|struct Point origin = { .x = 0, .y = 0 };
    #|
    #|int area(int w, int h) {
    #|  return w * h;
    #|}
  let names = sys_declared_names(registry, "c", source, "geom.c")
  assert_true(names.get("area") == Some("Function"))
}

// ─── Zig ────────────────────────────────────────────────────

///|
/// A Zig container is bound with `const`, so the container rules and the plain
/// const rule share a prefix. PEG is first-match, so the general const rule ran
/// first, matched the head, then failed on `struct {` and stopped the module.
test "declares: zig struct declaration followed by a pub fn" {
  let registry = get_fixture_registry()
  let source =
    #|/// A task.
    #|const Task = struct {
    #|    completed: bool,
    #|};
    #|
    #|/// Count the completed tasks.
    #|pub fn countCompleted(tasks: []const Task) usize {
    #|    return 0;
    #|}
  let names = sys_declared_names(registry, "zig", source, "main.zig")
  assert_true(names.get("countCompleted") == Some("Function"))
}

///|
/// A slice type carries a qualifier keyword (`[]const u8`). The type rule
/// allowed only an expression inside the brackets, so any function taking a
/// slice failed to match and was dropped.
test "declares: zig slice parameter type with const qualifier" {
  let registry = get_fixture_registry()
  let source =
    #|pub fn join(parts: []const u8) void {}
  let names = sys_declared_names(registry, "zig", source, "join.zig")
  assert_true(names.get("join") == Some("Function"))
}

///|
/// `=` was lexed as the general Operator token, which is defined first and wins
/// on a first-match lexer, so no declaration rule could ever see an `=`. A
/// container name is also conventionally PascalCase, which lexes as TypeIdent
/// rather than Ident.
test "declares: zig pub container declaration with PascalCase name" {
  let registry = get_fixture_registry()
  let source =
    #|/// A status.
    #|pub const Status = enum {
    #|    open,
    #|    done,
    #|};
  let names = sys_declared_names(registry, "zig", source, "status.zig")
  assert_true(names.get("Status") == Some("Enum"))
}

///|
/// A `pub fn` inside a container is part of that container's public surface.
test "declares: zig pub fn inside a struct body" {
  let registry = get_fixture_registry()
  let source =
    #|const Task = struct {
    #|    completed: bool,
    #|
    #|    /// Mark the task as completed.
    #|    pub fn complete(self: *Task) void {}
    #|};
  let doc = sys_doc_of(registry, "zig", source, "main.zig", "complete")
  assert_true(doc.contains("Mark the task as completed"))
}

// ─── PHP ────────────────────────────────────────────────────

///|
/// A parameter default made the parameter list fail, because the default
/// expression's atom set included the delimiters of the list itself and so ate
/// the closing paren. Every method with a defaulted parameter was lost.
test "declares: php parameter default does not swallow the parameter list" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|class A {
    #|  public function find(string $id, int $limit = 10) {}
    #|}
  let names = sys_declared_names(registry, "php", source, "A.php")
  assert_true(names.get("A") == Some("Class"))
  assert_true(names.get("find") == Some("Method"))
}

///|
/// Constructor property promotion is written across lines and ends with a
/// trailing comma. The parameter list allowed neither.
test "declares: php constructor property promotion with trailing comma" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|
    #|class UserDto
    #|{
    #|    public function __construct(
    #|        public readonly string $name,
    #|        public readonly ?string $email = null,
    #|    ) {
    #|    }
    #|}
  let names = sys_declared_names(registry, "php", source, "UserDto.php")
  assert_true(names.get("UserDto") == Some("Class"))
  assert_true(names.get("__construct") == Some("Method"))
}

///|
/// Method edges were gated on a `current_class` binding that nothing ever set,
/// and events fire bottom-up, so the owner has to be bound by a header rule
/// that runs before its members.
test "declares: php method is attached to its class with its doc" {
  let registry = get_fixture_registry()
  let source =
    #|<?php
    #|class Repo {
    #|  /** Returns all stored users. */
    #|  public function findAll(): array { return []; }
    #|}
  let doc = sys_doc_of(registry, "php", source, "Repo.php", "findAll")
  assert_true(doc.contains("Returns all stored users"))
}

// ─── Clojure ────────────────────────────────────────────────

///|
/// A symbol may be built entirely from operator characters, and `&` is itself
/// the rest-argument symbol. The old character classes covered only
/// alphanumeric-ish names, so these were dropped by the lexer.
test "declares: clojure operator symbols lex cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|(defn filter-by-status
    #|  "Filter tasks by their status keyword."
    #|  [tasks status]
    #|  (filter #(= (:status %) status) tasks))
  assert_true(sys_lexes_cleanly(registry, "clojure", source))
  let names = sys_declared_names(registry, "clojure", source, "core.clj")
  assert_true(names.get("filter-by-status") == Some("Function"))
}

///|
/// A namespace form spans lines and carries a docstring. Without newline
/// handling the very first form of the file failed, and with it everything
/// after it.
test "declares: clojure ns form with docstring and require" {
  let registry = get_fixture_registry()
  let source =
    #|(ns task-manager.core
    #|  "Task management system."
    #|  (:require [clojure.string :as str]))
    #|
    #|(defn complete-task
    #|  "Mark a task as completed."
    #|  [task]
    #|  (assoc task :status :completed))
  let names = sys_declared_names(registry, "clojure", source, "core.clj")
  assert_true(names.get("task-manager.core") == Some("Namespace"))
  assert_true(names.get("complete-task") == Some("Function"))
  let doc = sys_doc_of(registry, "clojure", source, "core.clj", "complete-task")
  assert_true(doc.contains("Mark a task as completed"))
}

///|
/// Inside `(ns ...)` the reference clauses are keywords (`:require`), not the
/// bare symbols the `require` function uses, so the dependency edge was lost.
test "declares: clojure ns require emits a dependency edge" {
  let registry = get_fixture_registry()
  let source =
    #|(ns app.core
    #|  (:require [clojure.string :as str]))
  let graph = sys_eval_source_graph(registry, "clojure", source, "core.clj")
  let mut found = false
  match graph {
    Some(g) =>
      for edge in g.get_edges() {
        if edge.kind is @graph.ModuleDependsOn &&
          edge.attrs.get("via").unwrap_or("") == "clojure.string" {
          found = true
        }
      }
    None => ()
  }
  assert_true(found)
}

///|
/// A rest argument and a destructuring map in the parameter vector.
test "declares: clojure destructuring parameter vector" {
  let registry = get_fixture_registry()
  let source =
    #|(defn create-task
    #|  "Create a new task."
    #|  [title & {:keys [description priority]}]
    #|  {:title title})
  let names = sys_declared_names(registry, "clojure", source, "core.clj")
  assert_true(names.get("create-task") == Some("Function"))
}

// ─── Ruby ───────────────────────────────────────────────────

///|
/// A Ruby method name may end in `?`, `!` or `=`, and those names are legal in
/// a symbol too. The symbol token stopped before the suffix, leaving the `?` as
/// a character the lexer could not place.
test "declares: ruby symbol with a trailing question mark lexes cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|class TaskService
    #|  # Returns all pending tasks.
    #|  def pending
    #|    @tasks.values.reject(&:done?)
    #|  end
    #|end
  assert_true(sys_lexes_cleanly(registry, "ruby", source))
  let names = sys_declared_names(registry, "ruby", source, "task_service.rb")
  assert_true(names.get("TaskService") == Some("Class"))
}

///|
/// The same suffix rule covers `!` and `=` symbol names.
test "declares: ruby symbols with bang and setter suffixes lex cleanly" {
  let registry = get_fixture_registry()
  let source =
    #|class Store
    #|  def apply
    #|    items.each(&:save!)
    #|  end
    #|end
  assert_true(sys_lexes_cleanly(registry, "ruby", source))
}
