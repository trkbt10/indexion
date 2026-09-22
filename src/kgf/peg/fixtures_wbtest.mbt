// Integration tests using fixtures from reference implementation.
// These test cases verify parsing and tokenization of real-world code examples.

///|
/// TypeScript import example from reference fixtures.
fn typescript_import_example() -> String {
  let text =
    #|import { foo as f } from './utils';
    #|import React from 'react';
    #|type U = T;
    #|const a: T = f(b)
    #|function g(x: T) { return f(x) }
  text
}

///|
/// TypeScript spec (simplified for testing).
fn typescript_spec_for_fixtures() -> String {
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
    #|TOKEN KW_as /as/
    #|TOKEN KW_return /return/
    #|TOKEN Ident /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN SEMI /;/
    #|TOKEN COMMA /,/
    #|TOKEN COLON /:/
    #|TOKEN EQ /=/
    #|
    #|=== grammar
    #|Module -> ( ImportDecl | TypeAlias | FnDecl | VarDecl )*
    #|ImportDecl -> KW_import ( ImportNamed | ImportDefault ) SEMI?
    #|ImportNamed -> LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ImportDefault -> defId:Ident KW_from from:StringLit
    #|ImportSpecList -> ImportSpec ( COMMA ImportSpec )*
    #|ImportSpec -> origin:Ident ( KW_as local:Ident )?
    #|TypeAlias -> KW_type id:Ident EQ Type SEMI?
    #|VarDecl -> KW_const id:Ident COLON? Type? EQ Expr
    #|FnDecl -> KW_function id:Ident LPAREN ParamList? RPAREN Block
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> id:Ident COLON? Type?
    #|Block -> LBRACE BlockItem* RBRACE
    #|BlockItem -> VarDecl | ReturnStmt
    #|ReturnStmt -> KW_return Expr
    #|Expr -> CallExpr | Primary
    #|CallExpr -> callee:Ident LPAREN Expr? RPAREN
    #|Primary -> Ident
    #|Type -> Ident
    #|
    #|=== attrs
    #|on ImportNamed: import module=from
    #|on ImportDefault: import module=from
    #|on TypeAlias: def id kind=TypeAlias
    #|on VarDecl: def id kind=Variable
    #|on FnDecl: def id kind=Function
    #|
  text
}

///|
test "fixtures: typescript import tokenization" {
  let spec = @parser.parse_kgf(typescript_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = typescript_import_example()
  let tokens = lexer.tokenize(code)
  // Verify first line tokens: import { foo as f } from './utils';
  assert_eq(tokens[0].kind, "KW_import")
  assert_eq(tokens[1].kind, "LBRACE")
  assert_eq(tokens[2].kind, "Ident")
  assert_eq(tokens[2].text, "foo")
  assert_eq(tokens[3].kind, "KW_as")
  assert_eq(tokens[4].kind, "Ident")
  assert_eq(tokens[4].text, "f")
  assert_eq(tokens[5].kind, "RBRACE")
  assert_eq(tokens[6].kind, "KW_from")
  assert_eq(tokens[7].kind, "StringLit")
  assert_eq(tokens[7].text, "'./utils'")
  assert_eq(tokens[8].kind, "SEMI")
  // Verify second line tokens: import React from 'react';
  assert_eq(tokens[9].kind, "KW_import")
  assert_eq(tokens[10].kind, "Ident")
  assert_eq(tokens[10].text, "React")
  assert_eq(tokens[11].kind, "KW_from")
  assert_eq(tokens[12].kind, "StringLit")
  assert_eq(tokens[12].text, "'react'")
}

///|
test "fixtures: typescript import parsing" {
  let spec = @parser.parse_kgf(typescript_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = typescript_import_example()
  let tokens = lexer.tokenize(code)
  let peg = build_peg(spec)
  let result = run_parse(peg, spec, "Module", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// JavaScript import example from reference fixtures.
fn javascript_import_example() -> String {
  let text =
    #|import { double } from './util.js';
    #|const val = double(n);
    #|function run(n){ return double(n) }
  text
}

///|
/// JavaScript spec (simplified for testing).
fn javascript_spec_for_fixtures() -> String {
  let text =
    #|kgf 0.5
    #|language: javascript
    #|
    #|=== lex
    #|SKIP /(\s+|\/\/[^\n]*|\/\*([^*]|\*[^\/])*\*\/)+/
    #|TOKEN KW_import /import/
    #|TOKEN KW_from /from/
    #|TOKEN KW_export /export/
    #|TOKEN KW_const /const/
    #|TOKEN KW_function /function/
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
    #|Module -> ( ImportDecl | VarDecl | FnDecl )*
    #|ImportDecl -> KW_import LBRACE ImportSpecList RBRACE KW_from from:StringLit SEMI?
    #|ImportSpecList -> Ident ( COMMA Ident )*
    #|VarDecl -> KW_const id:Ident EQ Expr SEMI?
    #|FnDecl -> KW_function id:Ident LPAREN ParamList? RPAREN Block
    #|ParamList -> Ident ( COMMA Ident )*
    #|Block -> LBRACE BlockItem* RBRACE
    #|BlockItem -> VarDecl | ReturnStmt
    #|ReturnStmt -> KW_return Expr
    #|Expr -> CallExpr | Primary
    #|CallExpr -> callee:Ident LPAREN Expr? RPAREN
    #|Primary -> Ident
    #|
    #|=== attrs
    #|on ImportDecl: import module=from
    #|on VarDecl: def id kind=Variable
    #|on FnDecl: def id kind=Function
    #|
  text
}

///|
test "fixtures: javascript import tokenization" {
  let spec = @parser.parse_kgf(javascript_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = javascript_import_example()
  let tokens = lexer.tokenize(code)
  // Verify first line tokens: import { double } from './util.js';
  assert_eq(tokens[0].kind, "KW_import")
  assert_eq(tokens[1].kind, "LBRACE")
  assert_eq(tokens[2].kind, "Ident")
  assert_eq(tokens[2].text, "double")
  assert_eq(tokens[3].kind, "RBRACE")
  assert_eq(tokens[4].kind, "KW_from")
  assert_eq(tokens[5].kind, "StringLit")
  assert_eq(tokens[5].text, "'./util.js'")
}

///|
test "fixtures: javascript import parsing" {
  let spec = @parser.parse_kgf(javascript_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = javascript_import_example()
  let tokens = lexer.tokenize(code)
  let peg = build_peg(spec)
  let result = run_parse(peg, spec, "Module", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Python import example from reference fixtures.
fn python_import_example() -> String {
  let text =
    #|import pkg.util, os
    #|from pkg import util
    #|def run(n):
    #|    return inc(n)
  text
}

///|
/// Python spec (simplified for testing).
fn python_spec_for_fixtures() -> String {
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
    #|
  text
}

///|
test "fixtures: python import tokenization" {
  let spec = @parser.parse_kgf(python_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = python_import_example()
  let tokens = lexer.tokenize(code)
  // Verify first line tokens: import pkg.util, os
  assert_eq(tokens[0].kind, "KW_import")
  assert_eq(tokens[1].kind, "Ident")
  assert_eq(tokens[1].text, "pkg")
  assert_eq(tokens[2].kind, "DOT")
  assert_eq(tokens[3].kind, "Ident")
  assert_eq(tokens[3].text, "util")
  assert_eq(tokens[4].kind, "COMMA")
  assert_eq(tokens[5].kind, "Ident")
  assert_eq(tokens[5].text, "os")
  assert_eq(tokens[6].kind, "NL")
  // Verify second line: from pkg import util
  assert_eq(tokens[7].kind, "KW_from")
  assert_eq(tokens[8].kind, "Ident")
  assert_eq(tokens[8].text, "pkg")
  assert_eq(tokens[9].kind, "KW_import")
  assert_eq(tokens[10].kind, "Ident")
  assert_eq(tokens[10].text, "util")
}

///|
test "fixtures: python import parsing" {
  let spec = @parser.parse_kgf(python_spec_for_fixtures()).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = python_import_example()
  let tokens = lexer.tokenize(code)
  let peg = build_peg(spec)
  let result = run_parse(peg, spec, "Module", tokens)
  assert_true(result is Some(_))
  assert_true(result.unwrap().ok)
}

///|
/// Markdown example from reference fixtures.
fn markdown_example() -> String {
  let text =
    #|# Hello World
    #|
    #|This is **bold** and *italic*.
    #|
    #|```js
    #|const x = 1;
    #|```
  text
}

///|
test "fixtures: markdown tokenization" {
  // Simplified markdown spec (pattern matcher doesn't support ^ anchor or {1,6})
  let spec_text =
    #|kgf 0.5
    #|language: markdown
    #|
    #|=== lex
    #|TOKEN Heading /#+ [^\n]*/
    #|TOKEN Bold /\*\*[^*]+\*\*/
    #|TOKEN Italic /\*[^*]+\*/
    #|TOKEN Text /[^\n#`*]+/
    #|TOKEN NL /\n+/
    #|
    #|=== grammar
    #|Doc -> Element*
    #|Element -> Heading | Bold | Italic | Text | NL
    #|
  let spec = @parser.parse_kgf(spec_text).unwrap()
  let lexer = @lexer.Lexer::for_spec(spec)
  let code = markdown_example()
  let tokens = lexer.tokenize(code)
  // Verify heading
  assert_eq(tokens[0].kind, "Heading")
  assert_true(tokens[0].text.contains("Hello World"))
  // Find bold token
  let bold_token = tokens.iter().find_first(fn(t) { t.kind == "Bold" })
  assert_true(bold_token is Some(_))
  assert_eq(bold_token.unwrap().text, "**bold**")
}
