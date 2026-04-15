///|
fn registry() -> @kgf_registry.KGFRegistry {
  @kgf_registry.KGFRegistry::load_from_dir("kgfs")
}

///|
fn declaration_names(decls : Array[PubDeclaration]) -> Map[String, Bool] {
  let names : Map[String, Bool] = {}
  for decl in decls {
    names.set(decl.name, true)
  }
  names
}

///|
fn extract_test_declarations(
  path : String,
  source : String,
) -> (Array[PubDeclaration], Map[String, Bool]) {
  let (decls, _) = extract_pub_declarations_and_doc_map(
    source,
    path,
    Some(registry()),
  )
  let names = declaration_names(decls)
  (decls, names)
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
test "declarations: coverage includes every programming kgf" {
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

///|
test "declarations: RFC 3492 fixture extracts KGF top-level declarations" {
  let path = "fixtures/project/spec-align-rfc3492/typescript/src/punycode.ts"
  let source = @fs.read_file_to_string(path)
  let (decls, _) = extract_pub_declarations_and_doc_map(
    source,
    path,
    Some(registry()),
  )
  let names = declaration_names(decls)
  assert_true(decls.length() >= 10)
  assert_true(names.contains("bootstringParameters"))
}

///|
test "declarations: RFC 2795 fixture extracts KGF top-level declarations" {
  let path = "fixtures/project/spec-align-rfc2795/typescript/src/keeper.ts"
  let source = @fs.read_file_to_string(path)
  let (decls, _) = extract_pub_declarations_and_doc_map(
    source,
    path,
    Some(registry()),
  )
  let names = declaration_names(decls)
  assert_true(decls.length() >= 18)
  assert_false(names.contains("keeperExchangeExample"))
  assert_false(names.contains("chimpSessionExample"))
  assert_false(names.contains("iambPentSessionExample"))
  assert_false(names.contains("panSessionExample"))
  assert_false(names.contains("ChimpCommand"))
  assert_false(names.contains("PanCommand"))
}

///|
test "declarations: moonbit extracts public top-level declarations" {
  let source =
    #|pub fn visible() -> Int { 1 }
    #|fn hidden() -> Int { 0 }
    #|pub struct Box { value : Int }
    #|pub let answer : Int = 42
  let (decls, names) = extract_test_declarations("memory/sample.mbt", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("visible"))
  assert_true(names.contains("Box"))
  assert_true(names.contains("answer"))
  assert_false(names.contains("hidden"))
}

///|
test "declarations: python extracts top-level function and class" {
  let source =
    #|class User:
    #|    name: str
    #|
    #|class Box:
    #|    id: str
    #|
    #|def visible():
    #|    return None
  let (decls, names) = extract_test_declarations("memory/sample.py", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("visible"))
  assert_true(names.contains("User"))
  assert_true(names.contains("Box"))
}

///|
test "declarations: rust extracts pub declarations" {
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
  let (decls, names) = extract_test_declarations("memory/config.rs", source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("Config"))
  assert_true(names.contains("load"))
  assert_true(!names.contains("private_fn"))
}

///|
test "declarations: go extracts exported declarations" {
  let source =
    #|package sample
    #|
    #|func Visible() {}
    #|func hidden() {}
    #|type VisibleType struct {}
    #|var VisibleVar = 1
    #|const VisibleConst = 2
  let (decls, names) = extract_test_declarations("memory/sample.go", source)
  assert_true(decls.length() >= 4)
  assert_true(names.contains("Visible"))
  assert_true(names.contains("VisibleType"))
  assert_true(names.contains("VisibleVar"))
  assert_true(names.contains("VisibleConst"))
  assert_false(names.contains("hidden"))
}

///|
test "declarations: javascript extracts top-level function and class" {
  let source =
    #|function visible(name) {
    #|  return "Hello";
    #|}
    #|
    #|function helper() {
    #|  return 42;
    #|}
  let (decls, names) = extract_test_declarations("memory/sample.js", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("visible"))
  assert_true(names.contains("helper"))
}

///|
test "declarations: javascript-jsx extracts function component and class" {
  let source =
    #|function App() {
    #|  return <Box />;
    #|}
    #|
    #|class LocalBox {}
  let (decls, names) = extract_test_declarations("memory/sample.jsx", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("App"))
  assert_true(names.contains("LocalBox"))
}

///|
test "declarations: typescript extracts exported function and interface" {
  let source =
    #|export function formatClassName(base: string, variant: string): string {
    #|  return `${base}-${variant}`;
    #|}
    #|
    #|export interface Config {
    #|  host: string
    #|  port: number
    #|}
  let (decls, names) = extract_test_declarations("memory/sample.ts", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("formatClassName"))
  assert_true(names.contains("Config"))
}

///|
test "declarations: typescript-jsx extracts jsx component and interface" {
  let source =
    #|export interface Props {
    #|  title: string
    #|}
    #|
    #|export function App(props: Props) {
    #|  return <Main title={props.title} />;
    #|}
  let (decls, names) = extract_test_declarations("memory/sample.tsx", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("Props"))
  assert_true(names.contains("App"))
}

///|
test "declarations: clojure extracts def defn defmacro" {
  let source =
    #|(def visible-value 1)
    #|(defn visible-fn [name]
    #|  name)
    #|(defmacro visible-macro [x] x)
  let (decls, names) = extract_test_declarations("memory/sample.clj", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("visible-value"))
  assert_true(names.contains("visible-fn"))
  assert_true(names.contains("visible-macro"))
}

///|
test "declarations: clojure extracts protocol record type multimethod method" {
  let source =
    #|(defprotocol VisibleProtocol)
    #|(defrecord VisibleRecord)
    #|(deftype VisibleType)
    #|(defmulti visible-dispatch)
    #|(defmethod visible-method)
  let (decls, names) = extract_test_declarations("memory/extended.clj", source)
  assert_true(decls.length() >= 5)
  assert_true(names.contains("VisibleProtocol"))
  assert_true(names.contains("VisibleRecord"))
  assert_true(names.contains("VisibleType"))
  assert_true(names.contains("visible-dispatch"))
  assert_true(names.contains("visible-method"))
}

///|
test "declarations: c extracts top-level declarations" {
  let source =
    #|struct Box { int value; };
    #|typedef int count_t;
    #|int visible(void) { return 0; }
    #|int data;
  let (decls, names) = extract_test_declarations("memory/sample.c", source)
  assert_true(decls.length() >= 4)
  assert_true(names.contains("Box"))
  assert_true(names.contains("count_t"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("data"))
}

///|
test "declarations: cpp extracts top-level declarations" {
  let source =
    #|class Box {};
    #|void visible() {}
    #|int data;
  let (decls, names) = extract_test_declarations("memory/sample.cpp", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("data"))
}

///|
test "declarations: csharp extracts public declarations" {
  let source =
    #|public class Box {}
    #|class Hidden {}
    #|public interface Visible {}
  let (decls, names) = extract_test_declarations("memory/sample.cs", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("Box"))
  assert_true(names.contains("Visible"))
  assert_false(names.contains("Hidden"))
}

///|
test "declarations: java extracts public declarations" {
  let source =
    #|public class Box {}
    #|class Hidden {}
    #|public interface Visible {}
  let (decls, names) = extract_test_declarations("memory/sample.java", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("Box"))
  assert_true(names.contains("Visible"))
  assert_false(names.contains("Hidden"))
}

///|
test "declarations: php extracts top-level class and function" {
  let source =
    #|<?php
    #|class Box {}
    #|function visible() {}
  let (decls, names) = extract_test_declarations("memory/sample.php", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
}

///|
test "declarations: kotlin extracts top-level declarations" {
  let source =
    #|class Box
    #|fun visible() = 1
    #|val visibleValue = 1
  let (decls, names) = extract_test_declarations("memory/sample.kt", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("visibleValue"))
}

///|
test "declarations: swift extracts public declarations" {
  let source =
    #|public class Box {}
    #|class Hidden {}
    #|public func visible() {}
    #|public typealias Answer = Int
  let (decls, names) = extract_test_declarations("memory/sample.swift", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("Answer"))
  assert_false(names.contains("Hidden"))
}

///|
test "declarations: scala extracts top-level declarations" {
  let source =
    #|class Box
    #|def visible = 1
    #|object Tools
  let (decls, names) = extract_test_declarations("memory/sample.scala", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("Tools"))
}

///|
test "declarations: ruby extracts public class module method" {
  let source =
    #|class Box
    #|end
    #|
    #|module Tools
    #|end
    #|
    #|def visible
    #|  1
    #|end
  let (decls, names) = extract_test_declarations("memory/sample.rb", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("Tools"))
  assert_true(names.contains("visible"))
}

///|
test "declarations: zig extracts pub declarations" {
  let source =
    #|pub fn visible() void {
    #|    return;
    #|}
    #|
    #|fn hidden() void {}
  let (decls, names) = extract_test_declarations("memory/sample.zig", source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("visible"))
  assert_false(names.contains("hidden"))
}

///|
test "declarations: ocaml extracts top-level declarations" {
  let source =
    #|type status = Pending | Done
  let (decls, names) = extract_test_declarations("memory/sample.ml", source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("status"))
}

///|
test "declarations: haskell extracts top-level declarations" {
  let source =
    #|data Box = Red | Green | Blue
    #|
    #|visible :: Box -> String
    #|visible Red = "red"
  let (decls, names) = extract_test_declarations("memory/sample.hs", source)
  assert_true(decls.length() >= 2)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
}

///|
test "declarations: elixir extracts public module and defs" {
  let source =
    #|defmodule Box do
    #|  def visible(), do: 1
    #|  defp hidden(), do: 0
    #|end
    #|
    #|defguard is_box(value) when value > 0
  let (decls, names) = extract_test_declarations("memory/sample.ex", source)
  assert_true(decls.length() >= 3)
  assert_true(names.contains("Box"))
  assert_true(names.contains("visible"))
  assert_true(names.contains("is_box"))
  assert_false(names.contains("hidden"))
}

///|
test "declarations: dart extracts public declarations" {
  let path = "fixtures/programming/dart/task.dart"
  let source = @fs.read_file_to_string(path)
  let (decls, names) = extract_test_declarations(path, source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("Task"))
}

///|
test "declarations: lua extracts global declarations" {
  let source =
    #|function visible()
    #|  return 1
    #|end
    #|
    #|local function hidden()
    #|  return 0
    #|end
  let (decls, names) = extract_test_declarations("memory/sample.lua", source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("visible"))
  assert_false(names.contains("hidden"))
}

///|
test "declarations: julia extracts top-level declarations" {
  let source =
    #|struct Task
    #|    id::Int
    #|end
  let (decls, names) = extract_test_declarations("memory/sample.jl", source)
  assert_true(decls.length() >= 1)
  assert_true(names.contains("Task"))
}
