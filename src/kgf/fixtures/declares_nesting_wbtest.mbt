///|
/// Regression tests for lexical scoping (`scope push` / `scope pop`) in the
/// programming KGF specs.
///
/// Every spec that attaches a member to a parent through `bind` / `$scope`
/// now brackets that parent's body in a scope frame: the declaration HEADER
/// pushes the frame and binds the parent, the members read it, and the
/// enclosing declaration rule — which fires last, events being bottom-up —
/// pops it again.
///
/// The three things that frame buys, and that every test below pins, are:
///
///   1. a nested type is declared UNDER its parent (`Outer.Inner`), not as a
///      second file-level declaration,
///   2. a member of a nested type belongs to the NESTED type, and
///   3. a member written AFTER a nested type belongs to the OUTER type again,
///      and a declaration written after the whole type belongs to the file.
///
/// Point 3 is what a single flat scope map could not express at all: before
/// the frames, the last `bind` won for the rest of the file.
///
/// The helpers mirror the ones in `declares_wbtest.mbt` and carry a `nest_`
/// prefix so the files can coexist in this package.

///|
/// Helper: run the full KGF pipeline (lex, parse, semantics) on inline source
/// and return the resulting graph, or None when parsing fails outright.
fn nest_graph(
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
/// Helper: the declares edges of inline source as (from, to, name) triples,
/// in emission order.
fn nest_declares(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
) -> Array[(String, String, String)] {
  let result : Array[(String, String, String)] = []
  let graph = match nest_graph(registry, lang, source, path) {
    Some(g) => g
    None => return result
  }
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    result.push((edge.from, edge.to, edge.attrs.get("name").unwrap_or("")))
  }
  result
}

///|
/// Helper: the `from` endpoint — the PARENT — of the declares edge for `name`,
/// or "" when nothing declares it. This is the assertion the whole file is
/// about: which declaration a member hangs off.
fn nest_parent_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in nest_declares(registry, lang, source, path) {
    if row.2 == name {
      return row.0
    }
  }
  ""
}

///|
/// Helper: the `to` endpoint — the SYMBOL ID — of the declares edge for
/// `name`, or "" when nothing declares it. A nested type's symbol id is what
/// shows it was qualified under its parent rather than re-rooted at the file.
fn nest_symbol_of(
  registry : @registry.KGFRegistry,
  lang : String,
  source : String,
  path : String,
  name : String,
) -> String {
  for row in nest_declares(registry, lang, source, path) {
    if row.2 == name {
      return row.1
    }
  }
  ""
}

// ─── Java ───────────────────────────────────────────────────

///|
test "nesting: java nested class owns its own method, outer method returns to outer" {
  let registry = get_fixture_registry()
  let path = "Nest.java"
  let source =
    #|public class Outer {
    #|    public static class Inner {
    #|        public void innerMethod() {}
    #|    }
    #|    public void outerMethod() {}
    #|}
  // Inner is declared under Outer, qualified as Outer.Inner.
  assert_eq(
    nest_parent_of(registry, "java", source, path, "Inner"),
    "Nest.java::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "java", source, path, "Inner"),
    "Nest.java::Outer.Inner",
  )
  // innerMethod sits inside Inner's frame.
  assert_eq(
    nest_parent_of(registry, "java", source, path, "innerMethod"),
    "Nest.java::Outer.Inner",
  )
  // outerMethod follows Inner's ClassDecl, whose `scope pop` restored Outer.
  assert_eq(
    nest_parent_of(registry, "java", source, path, "outerMethod"),
    "Nest.java::Outer",
  )
  assert_eq(nest_declares(registry, "java", source, path).length(), 4)
}

// ─── Kotlin ─────────────────────────────────────────────────

///|
test "nesting: kotlin nested class, and a top-level fun below it returns to file" {
  let registry = get_fixture_registry()
  let path = "Nest.kt"
  let source =
    #|class Outer {
    #|    class Inner {
    #|        fun innerFun() {}
    #|    }
    #|    fun outerFun() {}
    #|}
    #|fun topLevel() {}
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "Inner"),
    "Nest.kt::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "kotlin", source, path, "Inner"),
    "Nest.kt::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "innerFun"),
    "Nest.kt::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "outerFun"),
    "Nest.kt::Outer",
  )
  // Outer's own ClassDecl popped back to the root frame, so topLevel is the
  // file's, not Outer's. The old `|`-joined type stack this replaced needed
  // explicit string surgery to get this right.
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "topLevel"),
    "Nest.kt",
  )
  assert_eq(nest_declares(registry, "kotlin", source, path).length(), 5)
}

///|
test "nesting: kotlin companion object members belong to the enclosing class" {
  let registry = get_fixture_registry()
  let path = "Companion.kt"
  let source =
    #|class Outer {
    #|    companion object {
    #|        fun create(): Outer = Outer()
    #|    }
    #|    fun member() {}
    #|}
  // An unnamed object opens a TRANSPARENT frame: it binds nothing, so `$scope`
  // falls through to Outer, and the pushes and pops still balance.
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "create"),
    "Companion.kt::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "kotlin", source, path, "member"),
    "Companion.kt::Outer",
  )
}

// ─── C# ─────────────────────────────────────────────────────

///|
test "nesting: csharp nested class owns its own method" {
  let registry = get_fixture_registry()
  let path = "Nest.cs"
  let source =
    #|public class Outer
    #|{
    #|    public class Inner
    #|    {
    #|        public void InnerMethod() {}
    #|    }
    #|    public void OuterMethod() {}
    #|}
  assert_eq(
    nest_parent_of(registry, "csharp", source, path, "Inner"),
    "Nest.cs::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "csharp", source, path, "Inner"),
    "Nest.cs::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "csharp", source, path, "InnerMethod"),
    "Nest.cs::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "csharp", source, path, "OuterMethod"),
    "Nest.cs::Outer",
  )
  assert_eq(nest_declares(registry, "csharp", source, path).length(), 4)
}

// ─── Swift ──────────────────────────────────────────────────

///|
test "nesting: swift nested struct, and a top-level func below it returns to file" {
  let registry = get_fixture_registry()
  let path = "Nest.swift"
  let source =
    #|public struct Outer {
    #|    public struct Inner {
    #|        public func innerFunc() {}
    #|    }
    #|    public func outerFunc() {}
    #|}
    #|public func topLevel() {}
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "Inner"),
    "Nest.swift::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "swift", source, path, "Inner"),
    "Nest.swift::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "innerFunc"),
    "Nest.swift::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "outerFunc"),
    "Nest.swift::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "topLevel"),
    "Nest.swift",
  )
  assert_eq(nest_declares(registry, "swift", source, path).length(), 5)
}

///|
test "nesting: swift extension visibility does not leak past the extension" {
  let registry = get_fixture_registry()
  let path = "Ext.swift"
  let source =
    #|public struct Thing {}
    #|public extension Thing {
    #|    func inExtension() {}
    #|}
    #|func afterExtension() {}
  // `public extension` publishes its members without repeating the modifier,
  // and `inherited_vis` carrying that lives in the extension's OWN frame —
  // popped by ExtensionDecl, so `afterExtension`, which is internal, is not
  // published at all.
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "inExtension"),
    "Ext.swift::Thing",
  )
  assert_eq(
    nest_parent_of(registry, "swift", source, path, "afterExtension"),
    "",
  )
}

// ─── Scala ──────────────────────────────────────────────────

///|
test "nesting: scala nested class owns its own def, outer def returns to outer" {
  let registry = get_fixture_registry()
  let path = "Nest.scala"
  let source =
    #|class Outer {
    #|  class Inner {
    #|    def innerDef(): Unit = {}
    #|  }
    #|  def outerDef(): Unit = {}
    #|}
  // Before the frames, Inner was declared at FILE level and both defs were
  // attributed to Inner, because the flat `current_owner` never unwound.
  assert_eq(
    nest_parent_of(registry, "scala", source, path, "Inner"),
    "Nest.scala::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "scala", source, path, "Inner"),
    "Nest.scala::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "scala", source, path, "innerDef"),
    "Nest.scala::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "scala", source, path, "outerDef"),
    "Nest.scala::Outer",
  )
  assert_eq(nest_declares(registry, "scala", source, path).length(), 4)
}

///|
test "nesting: scala multi-parameter case class keeps its members" {
  let registry = get_fixture_registry()
  let path = "Params.scala"
  let source =
    #|case class Task(id: Long, title: String) {
    #|  def summary: String = title
    #|}
  // A `,` is not a type operator: while `Type` accepted one it swallowed the
  // comma between two PARAMETERS, so the parameter list never reached its
  // closing paren, the class header ended at its name, and the body was
  // re-parsed at top level.
  assert_eq(
    nest_parent_of(registry, "scala", source, path, "Task"),
    "Params.scala",
  )
  assert_eq(
    nest_parent_of(registry, "scala", source, path, "summary"),
    "Params.scala::Task",
  )
}

// ─── Ruby ───────────────────────────────────────────────────

///|
test "nesting: ruby methods belong to their class, nested class under its parent" {
  let registry = get_fixture_registry()
  let path = "nest.rb"
  let source =
    #|class Outer
    #|  class Inner
    #|    def inner_method
    #|    end
    #|  end
    #|  def outer_method
    #|  end
    #|end
  // Before the header/body split every method hung off the FILE: nothing
  // bound a namespace at all.
  assert_eq(
    nest_parent_of(registry, "ruby", source, path, "Inner"),
    "nest.rb::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "ruby", source, path, "Inner"),
    "nest.rb::Outer::Inner",
  )
  assert_eq(
    nest_parent_of(registry, "ruby", source, path, "inner_method"),
    "nest.rb::Outer::Inner",
  )
  assert_eq(
    nest_parent_of(registry, "ruby", source, path, "outer_method"),
    "nest.rb::Outer",
  )
  assert_eq(nest_declares(registry, "ruby", source, path).length(), 4)
}

///|
test "nesting: ruby private does not escape the class it was written in" {
  let registry = get_fixture_registry()
  let path = "vis.rb"
  let source =
    #|class Guarded
    #|  private
    #|  def secret
    #|  end
    #|end
    #|def top_level
    #|end
  // `private` binds into the class's own frame, so it stops at the matching
  // `end`. Without the frame it hid every later declaration in the file.
  assert_eq(nest_parent_of(registry, "ruby", source, path, "secret"), "")
  assert_eq(
    nest_parent_of(registry, "ruby", source, path, "top_level"),
    "vis.rb",
  )
}

// ─── C++ ────────────────────────────────────────────────────

///|
test "nesting: cpp nested class owns its own method" {
  let registry = get_fixture_registry()
  let path = "nest.cpp"
  let source =
    #|class Outer {
    #|public:
    #|    class Inner {
    #|    public:
    #|        void inner_method();
    #|    };
    #|    void outer_method();
    #|};
  // Before the header/body split nothing ever bound `current_class`, so no
  // method or field of any class was declared at all.
  assert_eq(
    nest_parent_of(registry, "cpp", source, path, "Inner"),
    "nest.cpp::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "cpp", source, path, "Inner"),
    "nest.cpp::Outer::Inner",
  )
  assert_eq(
    nest_parent_of(registry, "cpp", source, path, "inner_method"),
    "nest.cpp::Outer::Inner",
  )
  assert_eq(
    nest_parent_of(registry, "cpp", source, path, "outer_method"),
    "nest.cpp::Outer",
  )
  assert_eq(nest_declares(registry, "cpp", source, path).length(), 4)
}

///|
test "nesting: cpp namespace qualifies the types declared in it" {
  let registry = get_fixture_registry()
  let path = "ns.cpp"
  let source =
    #|namespace app {
    #|class Thing {
    #|public:
    #|    void go();
    #|};
    #|}
  assert_eq(
    nest_parent_of(registry, "cpp", source, path, "Thing"),
    "ns.cpp::app",
  )
  assert_eq(
    nest_symbol_of(registry, "cpp", source, path, "Thing"),
    "ns.cpp::app::Thing",
  )
  assert_eq(
    nest_parent_of(registry, "cpp", source, path, "go"),
    "ns.cpp::app::Thing",
  )
}

// ─── C ──────────────────────────────────────────────────────

///|
test "nesting: c struct fields and enum values belong to their type" {
  let registry = get_fixture_registry()
  let path = "nest.c"
  let source =
    #|struct Outer {
    #|    int a;
    #|};
    #|enum Color { RED, GREEN };
  // Before the header/body split nothing bound `current_struct` or
  // `current_enum`, so no field or enum value was declared at all.
  assert_eq(nest_parent_of(registry, "c", source, path, "a"), "nest.c::Outer")
  assert_eq(nest_parent_of(registry, "c", source, path, "RED"), "nest.c::Color")
  assert_eq(
    nest_parent_of(registry, "c", source, path, "GREEN"),
    "nest.c::Color",
  )
  // The enum's values are not claimed by the struct that precedes it: the
  // struct's frame was popped at its own StructDecl.
  assert_eq(nest_declares(registry, "c", source, path).length(), 5)
}

///|
test "nesting: c typedef struct is named by its trailing name, with its doc" {
  let registry = get_fixture_registry()
  let path = "td.c"
  let source =
    #|/** A typedef'd struct. */
    #|typedef struct {
    #|    int b;
    #|} Alias;
  // An anonymous header cannot publish a name, so the declaration rule does —
  // reading the doc back out of the frame the header opened for it.
  assert_eq(nest_parent_of(registry, "c", source, path, "Alias"), "td.c")
  assert_eq(nest_symbol_of(registry, "c", source, path, "Alias"), "td.c::Alias")
}

// ─── Zig ────────────────────────────────────────────────────

///|
test "nesting: zig nested struct owns its own field, later field returns to outer" {
  let registry = get_fixture_registry()
  let path = "nest.zig"
  let source =
    #|pub const Outer = struct {
    #|    pub const Inner = struct {
    #|        deep: i32,
    #|    };
    #|    after: i32,
    #|};
  assert_eq(
    nest_parent_of(registry, "zig", source, path, "Inner"),
    "nest.zig::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "zig", source, path, "Inner"),
    "nest.zig::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "zig", source, path, "deep"),
    "nest.zig::Outer.Inner",
  )
  // `after` is written after Inner's body, so Inner's frame is already popped.
  assert_eq(
    nest_parent_of(registry, "zig", source, path, "after"),
    "nest.zig::Outer",
  )
  assert_eq(nest_declares(registry, "zig", source, path).length(), 4)
}

// ─── Protobuf ───────────────────────────────────────────────

///|
test "nesting: protobuf nested message is declared under its parent message" {
  let registry = get_fixture_registry()
  let path = "nest.proto"
  let source =
    #|syntax = "proto3";
    #|message Outer {
    #|  message Inner {
    #|    string deep = 1;
    #|  }
    #|  Inner inner = 1;
    #|}
  assert_eq(
    nest_parent_of(registry, "protobuf", source, path, "Inner"),
    "nest.proto::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "protobuf", source, path, "Inner"),
    "nest.proto::Outer.Inner",
  )
}

///|
test "nesting: protobuf rpc belongs to its service" {
  let registry = get_fixture_registry()
  let path = "svc.proto"
  let source =
    #|syntax = "proto3";
    #|service Svc {
    #|  rpc Go(Req) returns (Res);
    #|}
  assert_eq(
    nest_parent_of(registry, "protobuf", source, path, "Svc"),
    "svc.proto",
  )
  assert_eq(
    nest_parent_of(registry, "protobuf", source, path, "Go"),
    "svc.proto::Svc",
  )
}

// ─── Elixir ─────────────────────────────────────────────────

///|
test "nesting: elixir nested defmodule owns its own def" {
  let registry = get_fixture_registry()
  let path = "nest.ex"
  let source =
    #|defmodule Outer do
    #|  defmodule Inner do
    #|    def inner_fun, do: 1
    #|  end
    #|  def outer_fun, do: 2
    #|end
  assert_eq(
    nest_parent_of(registry, "elixir", source, path, "Inner"),
    "nest.ex::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "elixir", source, path, "Inner"),
    "nest.ex::Outer.Inner",
  )
  assert_eq(
    nest_parent_of(registry, "elixir", source, path, "inner_fun"),
    "nest.ex::Outer.Inner",
  )
  // `outer_fun` follows Inner's body, whose `scope pop` restored Outer.
  assert_eq(
    nest_parent_of(registry, "elixir", source, path, "outer_fun"),
    "nest.ex::Outer",
  )
  assert_eq(nest_declares(registry, "elixir", source, path).length(), 4)
}

// ─── OCaml ──────────────────────────────────────────────────

///|
test "nesting: ocaml nested module is declared under its parent module" {
  let registry = get_fixture_registry()
  let path = "nest.ml"
  let source =
    #|module Outer = struct
    #|  module Inner = struct
    #|    let inner_fn x = x
    #|  end
    #|end
  assert_eq(
    nest_parent_of(registry, "ocaml", source, path, "Inner"),
    "nest.ml::Outer",
  )
  assert_eq(
    nest_symbol_of(registry, "ocaml", source, path, "Inner"),
    "nest.ml::Outer.Inner",
  )
}

// ─── TypeScript / JavaScript ────────────────────────────────

///|
test "nesting: typescript members stay on their own type and export chain survives" {
  let registry = get_fixture_registry()
  let path = "nest.ts"
  let source =
    #|export class Outer {
    #|  method(): void {}
    #|}
    #|export interface Shape {
    #|  area(): number;
    #|}
    #|export function after(): void {}
  assert_eq(
    nest_parent_of(registry, "typescript", source, path, "method"),
    "nest.ts::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "typescript", source, path, "area"),
    "nest.ts::Shape",
  )
  // `after` is a top-level function: Outer's and Shape's frames were both
  // popped by their own declaration rules.
  assert_eq(
    nest_parent_of(registry, "typescript", source, path, "after"),
    "nest.ts",
  )
  assert_eq(nest_declares(registry, "typescript", source, path).length(), 5)
}

///|
test "nesting: javascript class members stay on the class, function after it on the file" {
  let registry = get_fixture_registry()
  let path = "nest.js"
  let source =
    #|class Outer {
    #|  method() {}
    #|}
    #|function after() {}
  assert_eq(
    nest_parent_of(registry, "javascript", source, path, "method"),
    "nest.js::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "javascript", source, path, "after"),
    "nest.js",
  )
}

// ─── PHP / Dart / Go ────────────────────────────────────────

///|
test "nesting: php top-level function after a class is not attributed to it" {
  let registry = get_fixture_registry()
  let path = "nest.php"
  let source =
    #|<?php
    #|class Outer {
    #|    public function outerMethod() {}
    #|}
    #|function topLevel() {}
  assert_eq(
    nest_parent_of(registry, "php", source, path, "outerMethod"),
    "nest.php::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "php", source, path, "topLevel"),
    "nest.php",
  )
}

///|
test "nesting: dart top-level function after a class is not attributed to it" {
  let registry = get_fixture_registry()
  let path = "nest.dart"
  let source =
    #|class Outer {
    #|  void outerMethod() {}
    #|}
    #|void topLevel() {}
  assert_eq(
    nest_parent_of(registry, "dart", source, path, "outerMethod"),
    "nest.dart::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "dart", source, path, "topLevel"),
    "nest.dart",
  )
}

///|
test "nesting: go anonymous inner struct does not steal the fields after it" {
  let registry = get_fixture_registry()
  let path = "nest.go"
  let source =
    #|package main
    #|
    #|type Outer struct {
    #|	Inner struct {
    #|		Deep string
    #|	}
    #|	After int
    #|}
  // Go's anonymous inner struct has no name of its own, so all three fields
  // belong to Outer — and `After`, written after the inner body, proves the
  // binding did not outlive it.
  assert_eq(
    nest_parent_of(registry, "go", source, path, "Deep"),
    "nest.go::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "go", source, path, "Inner"),
    "nest.go::Outer",
  )
  assert_eq(
    nest_parent_of(registry, "go", source, path, "After"),
    "nest.go::Outer",
  )
  assert_eq(nest_declares(registry, "go", source, path).length(), 4)
}
