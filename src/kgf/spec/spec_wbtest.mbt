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

// =============================================================================
// Reference Spec File Compatibility Tests
// =============================================================================

///|
test "parse_kgf handles kgf version header" {
  // Reference spec files start with "kgf 0.5" header
  let text =
    #|kgf 0.5
    #|language: typescript
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN IDENT /[a-z]+/
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "typescript")
  assert_eq(s.tokens.length(), 2)
}

///|
test "parse_lex typescript style" {
  let text =
    #|SKIP        /(\s+|\/\/[^\n]*|\/\*[\s\S]*?\*\/)+/
    #|TOKEN KW_import     /import\b/
    #|TOKEN KW_from       /from\b/
    #|TOKEN STAR          /\*/
    #|TOKEN Ident         /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit     /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    #|TOKEN LBRACE        /\{/
    #|TOKEN RBRACE        /\}/
  let tokens = parse_lex(text)
  assert_eq(tokens.length(), 8)
  assert_eq(tokens[0].get_name(), "SKIP")
  assert_true(tokens[0].is_skip())
  assert_eq(tokens[1].get_name(), "KW_import")
  assert_eq(tokens[1].get_pattern(), "import\\b")
  assert_eq(tokens[4].get_name(), "Ident")
}

///|
test "parse_lex japanese law style" {
  let text =
    #|SKIP /[ \t　]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LawHeader /((?:令和|平成|昭和|大正|明治)[一二三四五六七八九十百千〇零]+年(?:法律|政令|省令|勅令)第[一二三四五六七八九十百千〇零]+号)/
    #|TOKEN ChapterLine /((?:第[一二三四五六七八九十百千〇零]+章))[^\r\n]*/
    #|TOKEN Kanji    /[一-龯々〆ヵヶ]+/
    #|TOKEN Hiragana /[ぁ-ゖー]+/
  let tokens = parse_lex(text)
  assert_eq(tokens.length(), 6)
  assert_eq(tokens[0].get_name(), "SKIP")
  assert_eq(tokens[2].get_name(), "LawHeader")
  assert_eq(tokens[4].get_name(), "Kanji")
}

///|
test "parse_rules with labeled captures" {
  let text =
    #|ImportDecl      -> KW_import ( SideEffect | ImportNS | ImportNamed ) SEMI?
    #|SideEffect      -> path:StringLit
    #|ImportNS        -> STAR KW_as ns:Ident KW_from from:StringLit
    #|ImportSpec      -> origin:Ident ( KW_as local:Ident )?
  let rules = parse_rules(text)
  assert_eq(rules.size(), 4)
  assert_true(rules.contains("ImportDecl"))
  assert_true(rules.contains("SideEffect"))
  assert_true(rules.contains("ImportNS"))
  assert_true(rules.contains("ImportSpec"))
  let side_effect = rules.get("SideEffect").unwrap()
  assert_eq(side_effect.get_expr(), "path:StringLit")
}

///|
test "parse_rules with alternatives" {
  let text =
    #|Token -> LineComment | BlockComment
    #|      | RawString | String | Char | Number
    #|      | KeywordDecl | KeywordControl
  let rules = parse_rules(text)
  assert_eq(rules.size(), 1)
  assert_true(rules.contains("Token"))
  let token_expr = rules.get("Token").unwrap().get_expr()
  assert_true(find_substring(token_expr, "LineComment | BlockComment") >= 0)
}

///|
test "parse_attrs typescript style" {
  let text =
    #|on VarItem:    def id kind=Variable ns=value
    #|on TypeAlias:  def id kind=TypeAlias ns=type
    #|on FnDecl:     def id kind=Function ns=value ; scope push=function
    #|on PrimaryName: ref name ns=value
    #|on CallExpr:   call callee=callee
    #|on SideEffect: import module=path
  let attrs = parse_attrs(text)
  assert_eq(attrs.size(), 6)
  // VarItem
  let var_actions = attrs.get("VarItem").unwrap()
  assert_eq(var_actions.length(), 1)
  assert_eq(var_actions[0].get_kind(), "def")
  assert_eq(var_actions[0].get_param("kind"), Some("Variable"))
  assert_eq(var_actions[0].get_param("ns"), Some("value"))
  // FnDecl has multiple actions separated by semicolon
  let fn_actions = attrs.get("FnDecl").unwrap()
  assert_eq(fn_actions.length(), 2)
  assert_eq(fn_actions[0].get_kind(), "def")
  assert_eq(fn_actions[1].get_kind(), "scope")
  assert_eq(fn_actions[1].get_param("push"), Some("function"))
  // CallExpr
  let call_actions = attrs.get("CallExpr").unwrap()
  assert_eq(call_actions[0].get_kind(), "call")
  assert_eq(call_actions[0].get_param("callee"), Some("callee"))
}

///|
test "parse_attrs japanese law style" {
  let text =
    #|on LawHeaderEntry: def id=lh kind=LawHeader
    #|on Chapter:      def id=ch kind=Chapter
    #|on Section:      def id=sec kind=Section
    #|on Article:      def id=art kind=Article
  let attrs = parse_attrs(text)
  assert_eq(attrs.size(), 4)
  let chapter = attrs.get("Chapter").unwrap()
  assert_eq(chapter[0].get_param("id"), Some("ch"))
  assert_eq(chapter[0].get_param("kind"), Some("Chapter"))
}

///|
test "parse_resolver typescript style with aliases" {
  let text =
    #|sources: .ts, .tsx, .d.ts
    #|relative_prefixes: ./, ../, /
    #|exts: .ts, .tsx, .d.ts
    #|indexes: /index.ts, /index.tsx, /index.d.ts
    #|bare_prefix: npm:
    #|module_path_style: slash
    #|aliases:
    #|  -
    #|    pattern: ^@/(.*)$
    #|    replace: src/\1
  let resolver = parse_resolver(text)
  assert_eq(resolver.get_sources().length(), 3)
  assert_eq(resolver.get_sources()[0], ".ts")
  assert_eq(resolver.get_sources()[1], ".tsx")
  assert_eq(resolver.get_relative_prefixes().length(), 3)
  assert_eq(resolver.get_exts().length(), 3)
  assert_eq(resolver.get_indexes().length(), 3)
  assert_eq(resolver.get_bare_prefix(), "npm:")
  assert_eq(resolver.get_module_path_style().as_string(), "slash")
  let aliases = resolver.get_aliases()
  assert_eq(aliases.length(), 1)
  assert_eq(aliases[0].get_pattern(), "^@/(.*)$")
  assert_eq(aliases[0].get_replace(), "src/\\1")
}

///|
test "parse_resolver japanese law style with empty fields" {
  let text =
    #|sources: .txt
    #|relative_prefixes:
    #|exts: .txt
    #|indexes:
    #|bare_prefix:
    #|module_path_style: slash
  let resolver = parse_resolver(text)
  assert_eq(resolver.get_sources().length(), 1)
  assert_eq(resolver.get_sources()[0], ".txt")
  assert_eq(resolver.get_relative_prefixes().length(), 0)
  assert_eq(resolver.get_exts().length(), 1)
  assert_eq(resolver.get_indexes().length(), 0)
  assert_eq(resolver.get_bare_prefix(), "")
}

///|
test "parse_semantics typescript edge statements" {
  let text =
    #|on SideEffect {
    #|  edge moduleDependsOn from $file to $resolve($path) attrs obj("via", $path, "dep_kind", "value")
    #|}
    #|on ImportNS {
    #|  edge moduleDependsOn from $file to $resolve($from) attrs obj("via", $from, "dep_kind", "value")
    #|}
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let map = sem.unwrap()
  assert_eq(map.size(), 2)
  assert_true(map.contains("SideEffect"))
  assert_true(map.contains("ImportNS"))
  let side_effect_blocks = map.get("SideEffect").unwrap()
  assert_eq(side_effect_blocks.length(), 1)
  let stmts = side_effect_blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 1)
}

///|
test "parse_semantics japanese law with when conditions" {
  let text =
    #|on Chapter when $scope("value", "last_chapter") {
    #|  let cur = $scope("value", $ch)
    #|  edge next from $scope("value", "last_chapter") to cur attrs obj("rel", "chapter->chapter")
    #|}
    #|on Chapter {
    #|  let cur = $scope("value", $ch)
    #|  edge contains from $file to cur attrs obj("rel", "root->chapter")
    #|  bind ns "value" name "last_chapter" to cur
    #|  bind ns "value" name "current_chapter" to cur
    #|}
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let map = sem.unwrap()
  // Both blocks are for "Chapter" rule
  let chapter_blocks = map.get("Chapter").unwrap()
  assert_eq(chapter_blocks.length(), 2)
  // First block has when condition
  assert_true(chapter_blocks[0].get_when_cond() is Some(_))
  let stmts1 = chapter_blocks[0].get_then_stmts()
  assert_eq(stmts1.length(), 2) // let + edge
  // Second block has no when condition
  assert_true(chapter_blocks[1].get_when_cond() is None)
  let stmts2 = chapter_blocks[1].get_then_stmts()
  assert_eq(stmts2.length(), 4) // let + edge + 2 binds
}

///|
test "parse_semantics bind with null" {
  let text =
    #|on Chapter {
    #|  bind ns "value" name "last_section" to null
    #|  bind ns "value" name "last_subsection" to null
    #|  bind ns "value" name "current_chapter" to cur
    #|}
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let blocks = sem.unwrap().get("Chapter").unwrap()
  let stmts = blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 3)
}

///|
test "parse_semantics complex scope expressions" {
  let text =
    #|on Article when $scope("value", "current_subsection") {
    #|  let cur = $scope("value", $art)
    #|  edge contains from $scope("value", "current_subsection") to cur attrs obj("rel", "subsection->article")
    #|  bind ns "value" name "last_article" to cur
    #|}
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let blocks = sem.unwrap().get("Article").unwrap()
  assert_eq(blocks.length(), 1)
  // Check when condition is parsed
  assert_true(blocks[0].get_when_cond() is Some(_))
  let stmts = blocks[0].get_then_stmts()
  assert_eq(stmts.length(), 3) // let + edge + bind
}

///|
test "parse_kgf go spec style no attrs no semantics" {
  let text =
    #|kgf 0.5
    #|language: go
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> ( Token )* ( NL )?
    #|Token -> LineComment | Ident
    #|
    #|=== resolver
    #|sources: .go
    #|relative_prefixes: ./
    #|exts: .go
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "go")
  assert_eq(s.tokens.length(), 4)
  assert_eq(s.rules.size(), 3)
  // attrs and semantics should be empty/None
  assert_eq(s.attrs.size(), 0)
  assert_true(s.semantics is None)
}

///|
test "parse_kgf base64 minimal spec" {
  let text =
    #|kgf 0.5
    #|language: base64
    #|
    #|=== lex
    #|SKIP /\s+/
    #|TOKEN B64_CHAR /[A-Za-z0-9_\/]/
    #|TOKEN PAD /=/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> Quad | Tail | Other
    #|Quad -> B64_CHAR B64_CHAR B64_CHAR B64_CHAR
    #|
    #|=== attrs
    #|# none
    #|
    #|=== resolver
    #|sources: .b64, .base64, .txt
    #|exts: .b64, .base64, .txt
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "base64")
  assert_eq(s.tokens.length(), 3)
  assert_eq(s.rules.size(), 3)
  // attrs section has only comment, should be empty
  assert_eq(s.attrs.size(), 0)
  let resolver = s.resolver
  assert_eq(resolver.get_sources().length(), 3)
}

///|
test "parse_rules multiline with continuation and labeled captures" {
  // From typescript.kgf
  let text =
    #|ImportDecl      -> KW_import ( SideEffect | ImportNS | ImportNamedDefault | ImportNamed | ImportDefault ) SEMI?
    #|SideEffect      -> path:StringLit
    #|ImportNS        -> STAR KW_as ns:Ident KW_from from:StringLit
    #|ImportNamedDefault -> defId:Ident COMMA LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ImportNamed     -> LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ExportFrom      -> KW_export ( STAR KW_from from:StringLit
    #|                             | LBRACE ExportSpecList RBRACE KW_from from:StringLit ) SEMI?
  let rules = parse_rules(text)
  assert_eq(rules.size(), 6)
  // Check multiline rule is combined
  let export_from = rules.get("ExportFrom").unwrap().get_expr()
  assert_true(find_substring(export_from, "STAR KW_from") >= 0)
  assert_true(find_substring(export_from, "ExportSpecList") >= 0)
}

///|
test "parse_expr $scope call" {
  let result = parse_expr("$scope(\"value\", $ch)")
  // Should parse as a call expression
  match result {
    @types.SemExpr::Call(name, args) => {
      assert_eq(name, "scope")
      assert_eq(args.length(), 2)
    }
    _ => fail("Expected Call expression")
  }
}

///|
test "parse_expr obj function" {
  let result = parse_expr("obj(\"via\", $path, \"dep_kind\", \"value\")")
  // Should parse as a func expression
  match result {
    @types.SemExpr::Func(name, args) => {
      assert_eq(name, "obj")
      assert_eq(args.length(), 4)
    }
    _ => fail("Expected Func expression")
  }
}

///|
test "parse_expr $resolve nested call" {
  let result = parse_expr("$resolve($path)")
  match result {
    @types.SemExpr::Call(name, args) => {
      assert_eq(name, "resolve")
      assert_eq(args.length(), 1)
    }
    _ => fail("Expected Call expression")
  }
}

///|
test "parse_expr null literal" {
  let result = parse_expr("null")
  match result {
    @types.SemExpr::Null => ()
    _ => fail("Expected Null expression")
  }
}

///|
test "parse_lex with comments in reference style" {
  let text =
    #|# Comments
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|
    #|# String literals
    #|TOKEN RawString /`[^`]*`/
    #|TOKEN String /"(?:[^"\\]|\\.)*"/
  let tokens = parse_lex(text)
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0].get_name(), "LineComment")
  assert_eq(tokens[1].get_name(), "BlockComment")
  assert_eq(tokens[2].get_name(), "RawString")
  assert_eq(tokens[3].get_name(), "String")
}

///|
test "parse_resolver python style with dot module path" {
  let text =
    #|sources: .py
    #|relative_prefixes: ./, ../, /
    #|exts: .py
    #|indexes: /__init__.py
    #|bare_prefix: pip:
    #|module_path_style: dot
  let resolver = parse_resolver(text)
  assert_eq(resolver.get_sources().length(), 1)
  assert_eq(resolver.get_sources()[0], ".py")
  assert_eq(resolver.get_indexes().length(), 1)
  assert_eq(resolver.get_indexes()[0], "/__init__.py")
  assert_eq(resolver.get_bare_prefix(), "pip:")
  assert_eq(resolver.get_module_path_style().as_string(), "dot")
}

///|
test "parse_expr concat function" {
  let result = parse_expr("concat($file, \"::b64png:sig@\", $sig_pos)")
  match result {
    @types.SemExpr::Func(name, args) => {
      assert_eq(name, "concat")
      assert_eq(args.length(), 3)
    }
    _ => fail("Expected Func expression")
  }
}

///|
test "parse_semantics with concat and multiple module calls" {
  let text =
    #|on PngSig {
    #|  module $file file $file
    #|}
    #|on PngSig when $scope("value", "__b64png_prev") {
    #|  edge next from $scope("value", "__b64png_prev") to concat($file, "::sig@", $pos) attrs obj("pos", $pos)
    #|}
    #|on PngSig {
    #|  module concat($file, "::sig@", $pos) file null
    #|  edge maybeType from concat($file, "::sig@", $pos) to "png" attrs obj("confidence", 0.9)
    #|  bind ns "value" name "__prev" to concat($file, "::sig@", $pos)
    #|}
  let sem = parse_semantics(text)
  assert_true(sem is Some(_))
  let map = sem.unwrap()
  // Three blocks for PngSig
  let blocks = map.get("PngSig").unwrap()
  assert_eq(blocks.length(), 3)
  // First block: simple module
  assert_true(blocks[0].get_when_cond() is None)
  assert_eq(blocks[0].get_then_stmts().length(), 1)
  // Second block: with when condition
  assert_true(blocks[1].get_when_cond() is Some(_))
  assert_eq(blocks[1].get_then_stmts().length(), 1)
  // Third block: multiple statements
  assert_true(blocks[2].get_when_cond() is None)
  assert_eq(blocks[2].get_then_stmts().length(), 3)
}

///|
test "parse_attrs with comment line" {
  let text =
    #|on FnDef:       def id kind=Function ns=value ; scope push=function
    #|on Params:      def id kind=Param ns=value
    #|on SimpleStmt:  # no-op just to keep node
    #|on Primary:     ref name ns=value
  let attrs = parse_attrs(text)
  assert_eq(attrs.size(), 4)
  // SimpleStmt has no actions (comment only)
  let simple = attrs.get("SimpleStmt").unwrap()
  assert_eq(simple.length(), 0)
}

///|
test "parse_kgf rust spec style" {
  let text =
    #|kgf 0.5
    #|language: rust
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN Macro /[a-zA-Z_][a-zA-Z0-9_]*!/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> ( Token )* ( NL )?
    #|Token -> LineComment | Macro | Ident
    #|
    #|=== resolver
    #|sources: .rs
    #|relative_prefixes: ./
    #|exts: .rs
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "rust")
  assert_eq(s.tokens.length(), 5)
  assert_eq(s.rules.size(), 3)
  assert_eq(s.attrs.size(), 0)
  assert_true(s.semantics is None)
}
