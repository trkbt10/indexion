// Full integration tests for KGF: spec -> lexer -> peg -> semantics -> graph
// Tests the complete pipeline from KGF specification to generated CodeGraph.

///|
/// Helper function to run the full KGF pipeline and return the generated graph.
fn run_full_pipeline(
  spec_text : String,
  source_code : String,
  file_path : String,
) -> @graph.CodeGraph {
  // Parse spec
  let spec = @parser.parse_kgf(spec_text).unwrap()
  // Create lexer and tokenize
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source_code)
  // Build PEG and parse
  let peg = build_peg(spec) catch { _ => return @graph.CodeGraph::new() }
  let start_rule = spec.get_start_rule()
  let parse_result = run_parse(peg, spec, start_rule, tokens)
  // Create graph
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(file_path, file=Some(file_path))
  // Evaluate semantics
  match parse_result {
    Some(eval_result) => {
      let ctx = @semantics.SemEvalCtx::new(
        spec,
        graph,
        file_path,
        "",
        spec.get_language(),
        fn(_path) { false },
      )
      for event in eval_result.get_events() {
        let rule_name = event.0
        let labels = event.1
        @semantics.eval_rule_semantics(rule_name, labels, ctx)
      }
    }
    None => ()
  }
  graph
}

///|
/// TypeScript spec embedded for testing.
fn typescript_spec() -> String {
  let text =
    #|kgf 0.5
    #|language: typescript
    #|
    #|=== lex
    #|SKIP /(\s+|\/\/[^\n]*|\/\*([^*]|\*[^\/])*\*\/)+/
    #|TOKEN KW_import /import/
    #|TOKEN KW_from /from/
    #|TOKEN KW_export /export/
    #|TOKEN KW_type /type/
    #|TOKEN KW_function /function/
    #|TOKEN KW_const /const/
    #|TOKEN KW_let /let/
    #|TOKEN KW_var /var/
    #|TOKEN KW_as /as/
    #|TOKEN KW_return /return/
    #|TOKEN KW_new /new/
    #|TOKEN STAR /\*/
    #|TOKEN Ident /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    #|TOKEN NumberLit /(?:0|[1-9][0-9]*)(?:\.[0-9]+)?/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN SEMI /;/
    #|TOKEN COMMA /,/
    #|TOKEN COLON /:/
    #|TOKEN DOT /\./
    #|TOKEN LT /</
    #|TOKEN GT />/
    #|TOKEN EQ /=/
    #|
    #|=== grammar
    #|Module -> ( ImportDecl | ExportFrom | TypeAlias | FnDecl | VarDecl | ExprStmt )*
    #|ImportDecl -> KW_import ( SideEffect | ImportNS | ImportNamedDefault | ImportNamed | ImportDefault ) SEMI?
    #|SideEffect -> path:StringLit
    #|ImportNS -> STAR KW_as ns:Ident KW_from from:StringLit
    #|ImportNamedDefault -> defId:Ident COMMA LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ImportNamed -> LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ImportDefault -> defId:Ident KW_from from:StringLit
    #|ImportSpecList -> ImportSpec ( COMMA ImportSpec )*
    #|ImportSpec -> origin:Ident ( KW_as local:Ident )?
    #|ExportFrom -> KW_export ( STAR KW_from from:StringLit | LBRACE ExportSpecList RBRACE KW_from from:StringLit ) SEMI?
    #|ExportSpecList -> ExportSpec ( COMMA ExportSpec )*
    #|ExportSpec -> origin:Ident ( KW_as local:Ident )?
    #|TypeAlias -> KW_type id:Ident EQ Type SEMI
    #|VarDecl -> (KW_const | KW_let | KW_var) VarList SEMI?
    #|VarList -> VarItem ( COMMA VarItem )*
    #|VarItem -> id:Ident [ COLON Type ] [ EQ Expr ]
    #|FnDecl -> KW_function id:Ident LPAREN ParamList? RPAREN Block
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> id:Ident [ COLON Type ]
    #|Block -> LBRACE BlockItem* RBRACE
    #|BlockItem -> VarDecl | ReturnStmt | ExprStmt
    #|ReturnStmt -> KW_return [ Expr ] SEMI?
    #|ExprStmt -> Expr SEMI?
    #|Expr -> CallExpr | Primary ( DOT Ident )*
    #|CallExpr -> callee:Primary LPAREN (Arg ( COMMA Arg )*)? RPAREN
    #|Arg -> Expr
    #|Primary -> PrimaryName | LPAREN Expr RPAREN | NumberLit | StringLit | NewExpr
    #|PrimaryName -> name:Ident
    #|NewExpr -> KW_new Ident LPAREN (Arg ( COMMA Arg )*)? RPAREN
    #|Type -> TypeCore [ GenericArgs ] | ObjectType
    #|TypeCore -> TypeRef
    #|GenericArgs -> LT ( Type ( COMMA Type )* ) GT
    #|TypeRef -> tname:QN
    #|ObjectType -> LBRACE (Ident|NumberLit|StringLit|LBRACE|RBRACE|LPAREN|RPAREN|COMMA|COLON|SEMI|DOT|LT|GT|EQ)* RBRACE
    #|QN -> Ident ( DOT Ident )*
    #|
    #|=== attrs
    #|on VarItem: def id kind=Variable ns=value
    #|on TypeAlias: def id kind=TypeAlias ns=type
    #|on FnDecl: def id kind=Function ns=value
    #|on Param: def id kind=Param ns=value
    #|on PrimaryName: ref name ns=value
    #|on TypeRef: ref tname ns=type
    #|on CallExpr: call callee=callee
    #|on SideEffect: import module=path
    #|on ImportNS: import module=from
    #|on ImportNamedDefault: import module=from
    #|on ImportNamed: import module=from
    #|on ImportDefault: import module=from
    #|on ExportFrom: reexport module=from
    #|
  text
}

///|
/// JavaScript spec embedded for testing.
fn javascript_spec() -> String {
  let text =
    #|kgf 0.5
    #|language: javascript
    #|
    #|=== lex
    #|SKIP /(\s+|\/\/[^\n]*|\/\*([^*]|\*[^\/])*\*\/)+/
    #|TOKEN KW_import /import/
    #|TOKEN KW_from /from/
    #|TOKEN KW_export /export/
    #|TOKEN KW_function /function/
    #|TOKEN KW_const /const/
    #|TOKEN KW_let /let/
    #|TOKEN KW_var /var/
    #|TOKEN KW_return /return/
    #|TOKEN Ident /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit /'([^'\\]|\\.)*'/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN SEMI /;/
    #|TOKEN COMMA /,/
    #|TOKEN EQ /=/
    #|
    #|=== grammar
    #|Module -> ( ImportDecl | VarDecl | FnDecl | ExprStmt )*
    #|ImportDecl -> KW_import LBRACE ImportSpecList RBRACE KW_from from:StringLit SEMI?
    #|ImportSpecList -> Ident ( COMMA Ident )*
    #|VarDecl -> KW_const id:Ident EQ Expr SEMI?
    #|FnDecl -> KW_function id:Ident LPAREN ParamList? RPAREN Block
    #|ParamList -> Ident ( COMMA Ident )*
    #|Block -> LBRACE BlockItem* RBRACE
    #|BlockItem -> VarDecl | ReturnStmt
    #|ReturnStmt -> KW_return Expr SEMI?
    #|ExprStmt -> Expr SEMI?
    #|Expr -> CallExpr | Primary
    #|CallExpr -> callee:Ident LPAREN Expr? RPAREN
    #|Primary -> Ident
    #|
    #|=== attrs
    #|on ImportDecl: import module=from
    #|on VarDecl: def id kind=Variable
    #|on FnDecl: def id kind=Function
    #|on CallExpr: call callee=callee
    #|
  text
}

///|
/// Python spec embedded for testing.
fn python_spec() -> String {
  let text =
    #|kgf 0.5
    #|language: python
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n/
    #|TOKEN KW_import /import/
    #|TOKEN KW_from /from/
    #|TOKEN KW_def /def/
    #|TOKEN KW_return /return/
    #|TOKEN Ident /[A-Za-z_][A-Za-z0-9_]*/
    #|TOKEN COLON /:/
    #|TOKEN COMMA /,/
    #|TOKEN DOT /\./
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN INDENT /    /
    #|
    #|=== grammar
    #|Module -> ( ImportStmt | FromImport | FnDef | Line )*
    #|ImportStmt -> KW_import ModuleList NL
    #|ModuleList -> QN ( COMMA QN )*
    #|FromImport -> KW_from mod:QN KW_import Names NL
    #|Names -> Ident ( COMMA Ident )*
    #|QN -> Ident ( DOT Ident )*
    #|FnDef -> KW_def id:Ident LPAREN ParamList? RPAREN COLON NL Suite
    #|ParamList -> Ident ( COMMA Ident )*
    #|Suite -> ( INDENT Line )*
    #|Line -> ( ReturnStmt | ExprStmt ) NL?
    #|ReturnStmt -> KW_return Expr
    #|ExprStmt -> Expr
    #|Expr -> CallExpr | Primary
    #|CallExpr -> callee:Ident LPAREN Expr? RPAREN
    #|Primary -> Ident
    #|
    #|=== attrs
    #|on ImportStmt: import
    #|on FromImport: import module=mod
    #|on FnDef: def id kind=Function
    #|on CallExpr: call callee=callee
    #|
  text
}

///|
test "graph integration: typescript import parses successfully" {
  let source =
    #|import { foo as f } from './utils';
    #|import React from 'react';
  let graph = run_full_pipeline(typescript_spec(), source, "src/main.ts")
  // Should have module node
  let modules = graph.get_modules()
  assert_true(modules.contains("src/main.ts"))
}

///|
test "graph integration: typescript variable declaration creates symbols" {
  let source =
    #|const x = 1;
    #|let y: number = 2;
  let graph = run_full_pipeline(typescript_spec(), source, "src/vars.ts")
  // Should have module node
  assert_true(graph.get_modules().contains("src/vars.ts"))
  // Should have symbols for x and y
  let symbols = graph.get_symbols()
  let has_x = symbols.iter().any(fn(entry) { entry.1.name == "x" })
  let has_y = symbols.iter().any(fn(entry) { entry.1.name == "y" })
  assert_true(has_x)
  assert_true(has_y)
}

///|
test "graph integration: typescript function declaration creates symbols" {
  let source =
    #|function greet(name: string) {
    #|  return name;
    #|}
  let graph = run_full_pipeline(typescript_spec(), source, "src/fn.ts")
  // Should have module node
  assert_true(graph.get_modules().contains("src/fn.ts"))
  // Check all symbols for debugging
  let symbols = graph.get_symbols()
  // Should have function symbol
  let has_greet = symbols
    .iter()
    .any(fn(entry) { entry.1.name == "greet" && entry.1.kind == "Function" })
  assert_true(has_greet)
}

///|
test "graph integration: typescript type alias creates symbol" {
  let source =
    #|type MyType = string;
  let graph = run_full_pipeline(typescript_spec(), source, "src/types.ts")
  assert_true(graph.get_modules().contains("src/types.ts"))
  // Should have type alias symbol
  let symbols = graph.get_symbols()
  let has_mytype = symbols
    .iter()
    .any(fn(entry) { entry.1.name == "MyType" && entry.1.kind == "TypeAlias" })
  assert_true(has_mytype)
}

///|
test "graph integration: javascript variable creates symbol" {
  let source =
    #|import { double } from './util.js';
    #|const val = double(n);
  let graph = run_full_pipeline(javascript_spec(), source, "src/app.js")
  assert_true(graph.get_modules().contains("src/app.js"))
  // Should have variable symbol
  let symbols = graph.get_symbols()
  let has_val = symbols
    .iter()
    .any(fn(entry) { entry.1.name == "val" && entry.1.kind == "Variable" })
  assert_true(has_val)
}

///|
test "graph integration: javascript FnDecl labels" {
  // Test that JavaScript FnDecl captures the function name correctly
  let events = run_parse_with_events(
    javascript_spec(),
    "function run(n) { return double(n); }",
  )
  let fn_decl = events.iter().find_first(fn(e) { e.0 == "FnDecl" })
  assert_true(fn_decl is Some(_))
  let labels = fn_decl.unwrap().1
  // Check the function name is captured
  match labels.get("id") {
    Some(String(name)) => assert_eq(name, "run")
    _ => fail("Expected id label to be 'run'")
  }
}

///|
test "graph integration: javascript function creates symbol" {
  let source =
    #|function run(n) {
    #|  return double(n);
    #|}
  let graph = run_full_pipeline(javascript_spec(), source, "src/run.js")
  assert_true(graph.get_modules().contains("src/run.js"))
  // Should have function symbol
  let symbols = graph.get_symbols()
  let has_run = symbols
    .iter()
    .any(fn(entry) { entry.1.name == "run" && entry.1.kind == "Function" })
  assert_true(has_run)
}

///|
test "graph integration: python function creates symbol" {
  let source =
    #|def run(n):
    #|    return inc(n)
  let graph = run_full_pipeline(python_spec(), source, "main.py")
  assert_true(graph.get_modules().contains("main.py"))
  // Should have function symbol
  let symbols = graph.get_symbols()
  let has_run = symbols
    .iter()
    .any(fn(entry) { entry.1.name == "run" && entry.1.kind == "Function" })
  assert_true(has_run)
}

///|
test "graph integration: multiple files simulation" {
  // Simulate processing multiple files and merging graphs
  let graph1 = run_full_pipeline(typescript_spec(), "const a = 1;", "src/a.ts")
  let graph2 = run_full_pipeline(typescript_spec(), "const b = 2;", "src/b.ts")
  // Merge graphs manually
  let merged = @graph.CodeGraph::new()
  for entry in graph1.get_modules() {
    let m = entry.1
    let _ = merged.get_or_add_module(m.id, file=m.file)
  }
  for entry in graph2.get_modules() {
    let m = entry.1
    let _ = merged.get_or_add_module(m.id, file=m.file)
  }
  // Verify merged graph has both modules
  assert_true(merged.get_modules().contains("src/a.ts"))
  assert_true(merged.get_modules().contains("src/b.ts"))
}

///|
test "graph integration: json serialization" {
  let source = "const x = 1;"
  let graph = run_full_pipeline(typescript_spec(), source, "test.ts")
  // Serialize to JSON
  let json_str = graph.to_json_string()
  // Should contain expected keys
  assert_true(json_str.contains("\"modules\""))
  assert_true(json_str.contains("\"symbols\""))
  assert_true(json_str.contains("\"edges\""))
  assert_true(json_str.contains("test.ts"))
}

///|
test "graph integration: complex typescript example parses" {
  let source =
    #|import { foo as f } from './utils';
    #|import React from 'react';
    #|type U = T;
    #|const a: T = f(b)
    #|function g(x: T) { return f(x) }
  let graph = run_full_pipeline(typescript_spec(), source, "src/main.ts")
  // Should have module
  assert_true(graph.get_modules().contains("src/main.ts"))
}

///|
test "graph integration: attrs parsing debug" {
  // Test that attrs are being parsed correctly
  let spec = @parser.parse_kgf(typescript_spec()).unwrap()
  let attrs = spec.get_attrs()
  // Should have attrs for FnDecl
  let fn_attrs = attrs.get("FnDecl")
  assert_true(fn_attrs is Some(_))
  let fn_actions = fn_attrs.unwrap()
  assert_true(fn_actions.length() > 0)
  // Check the first action is "def"
  assert_eq(fn_actions[0].get_kind(), "def")
  // Check the "id" param is present
  let params = fn_actions[0].get_params()
  assert_true(params.contains("id"))
  assert_eq(params.get("id").unwrap(), "id")
  assert_eq(params.get("kind").unwrap(), "Function")
}

///|
test "graph integration: typescript FnDecl labels" {
  // Test that nested rules don't pollute parent labels
  let events = run_parse_with_events(
    typescript_spec(),
    "function greet(name: string) { return name; }",
  )
  let fn_decl = events.iter().find_first(fn(e) { e.0 == "FnDecl" })
  assert_true(fn_decl is Some(_))
  let labels = fn_decl.unwrap().1
  // Verify function name is "greet", not "name" (the parameter)
  match labels.get("id") {
    Some(String(name)) => assert_eq(name, "greet")
    _ => fail("Expected id label to be 'greet'")
  }
}

///|
test "graph integration: empty file" {
  let source = ""
  let graph = run_full_pipeline(typescript_spec(), source, "empty.ts")
  // Should still have module node
  assert_true(graph.get_modules().contains("empty.ts"))
  // But no symbols
  assert_eq(graph.get_symbols().length(), 0)
}

///|
test "graph integration: comments only file" {
  let source =
    #|// This is a comment
    #|/* Block comment */
  let graph = run_full_pipeline(typescript_spec(), source, "comments.ts")
  // Should have module node
  assert_true(graph.get_modules().contains("comments.ts"))
  // No symbols (comments are skipped)
  assert_eq(graph.get_symbols().length(), 0)
}

///|
/// Helper to run parse and get events
fn run_parse_with_events(
  spec_text : String,
  source_code : String,
) -> Array[(String, Map[String, Json])] {
  let spec = @parser.parse_kgf(spec_text).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let tokens = lexer.tokenize(source_code)
  let peg = build_peg(spec) catch { _ => return [] }
  let start_rule = spec.get_start_rule()
  match run_parse(peg, spec, start_rule, tokens) {
    Some(result) => result.get_events()
    None => []
  }
}

///|
test "graph integration: parse events for variable declaration" {
  let events = run_parse_with_events(typescript_spec(), "const x = 1;")
  // Should have events for VarItem rule
  let has_var_item = events.iter().any(fn(e) { e.0 == "VarItem" })
  assert_true(has_var_item)
  // Check the labels contain expected values
  let var_item_event = events.iter().find_first(fn(e) { e.0 == "VarItem" })
  match var_item_event {
    Some(event) =>
      match event.1.get("id") {
        Some(String(id)) => assert_eq(id, "x")
        _ => fail("Expected id label")
      }
    None => fail("Expected VarItem event")
  }
}

///|
test "graph integration: parse events for function declaration" {
  let events = run_parse_with_events(
    typescript_spec(),
    "function greet(name: string) { return name; }",
  )
  // Should have events for FnDecl rule
  let has_fn_decl = events.iter().any(fn(e) { e.0 == "FnDecl" })
  assert_true(has_fn_decl)
  // Should have events for Param rule
  let has_param = events.iter().any(fn(e) { e.0 == "Param" })
  assert_true(has_param)
}

///|
test "graph integration: parse events for import statement" {
  let events = run_parse_with_events(
    typescript_spec(),
    "import { foo } from './utils';",
  )
  // Should have events for ImportNamed rule
  let has_import = events.iter().any(fn(e) { e.0 == "ImportNamed" })
  assert_true(has_import)
  // Check the from label (value is stripped of quotes by get_value)
  let import_event = events.iter().find_first(fn(e) { e.0 == "ImportNamed" })
  match import_event {
    Some(event) =>
      match event.1.get("from") {
        Some(String(from)) => assert_eq(from, "./utils")
        _ => fail("Expected from label")
      }
    None => fail("Expected ImportNamed event")
  }
}

///|
test "graph integration: parse events for type alias" {
  let events = run_parse_with_events(typescript_spec(), "type T = string;")
  // Should have events for TypeAlias rule
  let has_type_alias = events.iter().any(fn(e) { e.0 == "TypeAlias" })
  assert_true(has_type_alias)
  // Check the id label
  let type_event = events.iter().find_first(fn(e) { e.0 == "TypeAlias" })
  match type_event {
    Some(event) =>
      match event.1.get("id") {
        Some(String(id)) => assert_eq(id, "T")
        _ => fail("Expected id label")
      }
    None => fail("Expected TypeAlias event")
  }
}

///|
test "graph integration: parse events for call expression" {
  let events = run_parse_with_events(typescript_spec(), "const x = foo(1);")
  // Should have events for CallExpr rule
  let has_call = events.iter().any(fn(e) { e.0 == "CallExpr" })
  assert_true(has_call)
}

///|
test "graph integration: parse events for reference" {
  let events = run_parse_with_events(typescript_spec(), "const x = a;")
  // Should have events for PrimaryName rule (identifier reference)
  let has_primary = events.iter().any(fn(e) { e.0 == "PrimaryName" })
  assert_true(has_primary)
}

///|
test "graph integration: parse events for type reference" {
  let events = run_parse_with_events(typescript_spec(), "const x: T = 1;")
  // Should have events for TypeRef rule
  let has_type_ref = events.iter().any(fn(e) { e.0 == "TypeRef" })
  assert_true(has_type_ref)
}

///|
test "graph integration: javascript function parses" {
  // JavaScript function without semicolon inside
  let events = run_parse_with_events(
    javascript_spec(),
    "function run(n) { return double(n) }",
  )
  // Should have events for FnDecl rule
  let has_fn_decl = events.iter().any(fn(e) { e.0 == "FnDecl" })
  assert_true(has_fn_decl)
}

///|
test "graph integration: python parse events" {
  let events = run_parse_with_events(
    python_spec(),
    "def run(n):\n    return inc(n)\n",
  )
  // Should have events for FnDef rule
  let has_fn_def = events.iter().any(fn(e) { e.0 == "FnDef" })
  assert_true(has_fn_def)
  // Should have events for CallExpr rule
  let has_call = events.iter().any(fn(e) { e.0 == "CallExpr" })
  assert_true(has_call)
}
