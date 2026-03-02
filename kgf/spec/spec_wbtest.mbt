///|
test "split_lines basic" {
  let lines = split_lines("a\nb\nc")
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
  assert_eq(lines[2], "c")
}

///|
test "split_lines with CRLF" {
  let lines = split_lines("a\r\nb\r\nc")
  assert_eq(lines.length(), 3)
  assert_eq(lines[0], "a")
  assert_eq(lines[1], "b")
  assert_eq(lines[2], "c")
}

///|
test "trim_str" {
  assert_eq(trim_str("  hello  "), "hello")
  assert_eq(trim_str("\t\nworld\t\n"), "world")
  assert_eq(trim_str("no_trim"), "no_trim")
  assert_eq(trim_str(""), "")
}

///|
test "find_substring" {
  assert_eq(find_substring("hello world", "world"), 6)
  assert_eq(find_substring("hello", "x"), -1)
  assert_eq(find_substring("abcabc", "bc"), 1)
}

///|
test "starts_with" {
  assert_true(starts_with("hello", "hel"))
  assert_true(starts_with("hello", "hello"))
  assert_false(starts_with("hello", "world"))
  assert_false(starts_with("hi", "hello"))
}

///|
test "parse_list" {
  let result = parse_list("a, b, c")
  assert_eq(result.length(), 3)
  assert_eq(result[0], "a")
  assert_eq(result[1], "b")
  assert_eq(result[2], "c")
}

///|
test "parse_lex basic" {
  let text =
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-z]+/
    #|TOKEN NUMBER /[0-9]+/i
    #|
  let tokens = parse_lex(text)
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0].get_name(), "SKIP")
  assert_eq(tokens[0].get_pattern(), "\\s+")
  assert_true(tokens[0].is_skip())
  assert_eq(tokens[1].get_name(), "IDENT")
  assert_eq(tokens[1].get_pattern(), "[a-z]+")
  assert_false(tokens[1].is_skip())
  assert_eq(tokens[2].get_name(), "NUMBER")
  assert_eq(tokens[2].get_pattern(), "[0-9]+")
  assert_eq(tokens[2].get_flags(), Some("i"))
}

///|
test "parse_lex with comments" {
  let text =
    #|# This is a comment
    #|TOKEN WORD /\w+/
    #|
  let tokens = parse_lex(text)
  assert_eq(tokens.length(), 1)
  assert_eq(tokens[0].get_name(), "WORD")
}

///|
test "parse_rules basic" {
  let text =
    #|Expr -> Term ((PLUS | MINUS) Term)*
    #|Term -> Factor ((STAR | SLASH) Factor)*
    #|
  let rules = parse_rules(text)
  assert_eq(rules.size(), 2)
  assert_eq(
    rules.get("Expr").unwrap().get_expr(),
    "Term ((PLUS | MINUS) Term)*",
  )
  assert_eq(
    rules.get("Term").unwrap().get_expr(),
    "Factor ((STAR | SLASH) Factor)*",
  )
}

///|
test "parse_rules multiline" {
  let text =
    #|Stmt -> IF LPAREN Expr RPAREN
    #|        Block
    #|        (ELSE Block)?
    #|Other -> Simple
    #|
  let rules = parse_rules(text)
  assert_eq(rules.size(), 2)
  let stmt_expr = rules.get("Stmt").unwrap().get_expr()
  assert_true(find_substring(stmt_expr, "IF LPAREN") >= 0)
  assert_true(find_substring(stmt_expr, "Block") >= 0)
  assert_true(find_substring(stmt_expr, "ELSE") >= 0)
}

///|
test "parse_attrs basic" {
  let text =
    #|on FuncDecl: def name=id
    #|on VarRef: ref
    #|
  let attrs = parse_attrs(text)
  assert_eq(attrs.size(), 2)
  let func_actions = attrs.get("FuncDecl").unwrap()
  assert_eq(func_actions.length(), 1)
  assert_eq(func_actions[0].get_kind(), "def")
  assert_eq(func_actions[0].get_param("name"), Some("id"))
  let var_actions = attrs.get("VarRef").unwrap()
  assert_eq(var_actions.length(), 1)
  assert_eq(var_actions[0].get_kind(), "ref")
}

///|
test "parse_attrs multiple actions" {
  let text =
    #|on CallExpr: call; arg_begin; scope open=new
    #|
  let attrs = parse_attrs(text)
  let actions = attrs.get("CallExpr").unwrap()
  assert_eq(actions.length(), 3)
  assert_eq(actions[0].get_kind(), "call")
  assert_eq(actions[1].get_kind(), "arg_begin")
  assert_eq(actions[2].get_kind(), "scope")
  assert_eq(actions[2].get_param("open"), Some("new"))
}

///|
test "parse_resolver basic" {
  let text =
    #|sources: src, lib
    #|exts: .ts, .js
    #|module_path_style: slash
    #|bare_prefix: @
    #|
  let resolver = parse_resolver(text)
  assert_eq(resolver.get_sources().length(), 2)
  assert_eq(resolver.get_sources()[0], "src")
  assert_eq(resolver.get_sources()[1], "lib")
  assert_eq(resolver.get_exts().length(), 2)
  assert_eq(resolver.get_module_path_style().as_string(), "slash")
  assert_eq(resolver.get_bare_prefix(), "@")
}

///|
test "parse_resolver with aliases" {
  let text =
    #|sources: src
    #|aliases:
    #|  -
    #|    pattern: ^@/
    #|    replace: src/
    #|  -
    #|    pattern: ^~/
    #|    replace: home/
    #|
  let resolver = parse_resolver(text)
  let aliases = resolver.get_aliases()
  assert_eq(aliases.length(), 2)
  assert_eq(aliases[0].get_pattern(), "^@/")
  assert_eq(aliases[0].get_replace(), "src/")
  assert_eq(aliases[1].get_pattern(), "^~/")
  assert_eq(aliases[1].get_replace(), "home/")
}

///|
test "parse_semantics basic" {
  let text =
    #|on FuncDecl {
    #|  let x = $node
    #|  note definition
    #|}
    #|
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let map = sem.unwrap()
  assert_true(map.contains("FuncDecl"))
  let blocks = map.get("FuncDecl").unwrap()
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].get_rule(), "FuncDecl")
  assert_true(blocks[0].get_when_cond() is None)
  assert_eq(blocks[0].get_then_stmts().length(), 2)
}

///|
test "parse_semantics with when condition" {
  let text =
    #|on VarDecl when $isExported {
    #|  note export
    #|} else {
    #|  note local
    #|}
    #|
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let map = sem.unwrap()
  let blocks = map.get("VarDecl").unwrap()
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0].get_when_cond() is Some(_))
  assert_eq(blocks[0].get_then_stmts().length(), 1)
  assert_true(blocks[0].get_else_stmts() is Some(_))
  assert_eq(blocks[0].get_else_stmts().unwrap().length(), 1)
}

///|
test "parse_kgf full" {
  let text =
    #|language: typescript
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Program -> Statement*
    #|Statement -> IDENT
    #|
    #|=== attrs
    #|on Statement: ref
    #|
    #|=== resolver
    #|sources: src
    #|exts: .ts
    #|
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.get_language(), "typescript")
  assert_eq(s.get_tokens().length(), 2)
  assert_eq(s.get_rules().size(), 2)
  assert_eq(s.get_attrs().size(), 1)
  assert_eq(s.get_resolver().get_sources().length(), 1)
}

///|
test "parse_semantics edge statement" {
  let text =
    #|on Import {
    #|  edge import from $source to $target attrs $metadata
    #|}
    #|
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let blocks = sem.unwrap().get("Import").unwrap()
  let stmts = blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 1)
}

///|
test "parse_semantics bind statement" {
  let text =
    #|on FuncDecl {
    #|  bind ns $scope name $funcName to $node
    #|}
    #|
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let blocks = sem.unwrap().get("FuncDecl").unwrap()
  let stmts = blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 1)
}

///|
test "parse_semantics module statement" {
  let text =
    #|on ModuleDecl {
    #|  module $modulePath file $filePath
    #|}
    #|
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let blocks = sem.unwrap().get("ModuleDecl").unwrap()
  let stmts = blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 1)
}

///|
test "parse_preprocess_fst empty" {
  let result = parse_preprocess_fst("")
  assert_true(result is None)
}

///|
test "parse_preprocess_fst single object" {
  let json_text =
    #|{
    #|  "name": "test_fst",
    #|  "initial": "start",
    #|  "classes": { "alpha": "[A-Za-z]" },
    #|  "states": {
    #|    "start": [
    #|      { "on": "alpha", "to": "start", "actions": [{ "type": "emitInput" }] }
    #|    ]
    #|  }
    #|}
  let result = parse_preprocess_fst(json_text)
  assert_true(result is Some(_))
  let specs = result.unwrap()
  assert_eq(specs.length(), 1)
  assert_eq(specs[0].name, "test_fst")
  assert_eq(specs[0].initial, "start")
}

///|
test "parse_preprocess_fst array" {
  let json_text =
    #|[
    #|  {
    #|    "name": "fst1",
    #|    "initial": "s0",
    #|    "classes": { "a": "[a]" },
    #|    "states": { "s0": [] }
    #|  },
    #|  {
    #|    "name": "fst2",
    #|    "initial": "s1",
    #|    "classes": { "b": "[b]" },
    #|    "states": { "s1": [] }
    #|  }
    #|]
  let result = parse_preprocess_fst(json_text)
  assert_true(result is Some(_))
  let specs = result.unwrap()
  assert_eq(specs.length(), 2)
  assert_eq(specs[0].name, "fst1")
  assert_eq(specs[1].name, "fst2")
}

///|
test "parse_preprocess_fst with all action types" {
  let json_text =
    #|{
    #|  "name": "test",
    #|  "initial": "start",
    #|  "classes": { "alpha": "[A-Z]", "digit": "[0-9]" },
    #|  "states": {
    #|    "start": [
    #|      { "on": "alpha", "to": "start", "actions": [{ "type": "emitInput" }] },
    #|      { "on": "digit", "to": "buf", "actions": [{ "type": "buf" }] }
    #|    ],
    #|    "buf": [
    #|      { "on": "alpha", "to": "start", "actions": [{ "type": "flush", "pad": 0 }, { "type": "emit", "value": "X" }] }
    #|    ]
    #|  }
    #|}
  let result = parse_preprocess_fst(json_text)
  assert_true(result is Some(_))
  let spec = result.unwrap()[0]
  let start_transitions = spec.states.get("start").unwrap()
  assert_eq(start_transitions.length(), 2)
  assert_eq(start_transitions[0].on, "alpha")
  assert_eq(start_transitions[0].to, "start")
  assert_eq(start_transitions[1].on, "digit")
  assert_eq(start_transitions[1].to, "buf")
}

///|
test "parse_kgf with preprocess_fst" {
  let text =
    #|language: test
    #|
    #|=== preprocess
    #|fst:base64_classify
    #|
    #|=== preprocess_fst
    #|{
    #|  "name": "base64_classify",
    #|  "initial": "start",
    #|  "classes": { "b64": "[A-Za-z0-9+/=]" },
    #|  "states": {
    #|    "start": [
    #|      { "on": "b64", "to": "start", "actions": [{ "type": "emitInput" }] }
    #|    ]
    #|  }
    #|}
    #|
    #|=== lex
    #|TOKEN ID /[a-z]+/
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "test")
  // Check preprocess
  assert_true(s.preprocess is Some(_))
  let preprocess = s.preprocess.unwrap()
  assert_eq(preprocess.length(), 1)
  assert_eq(preprocess[0], "fst:base64_classify")
  // Check preprocess_fst
  assert_true(s.preprocess_fst is Some(_))
  let fst_specs = s.preprocess_fst.unwrap()
  assert_eq(fst_specs.length(), 1)
  assert_eq(fst_specs[0].name, "base64_classify")
}
