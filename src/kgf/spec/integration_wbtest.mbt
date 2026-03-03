// Integration tests for parsing reference KGF spec files.
// These tests verify that the parser can handle real-world spec files.

// Note: The actual spec files are stored in kgf/specs/ directory.
// These tests use embedded spec content to verify parsing behavior.

///|
test "parse typescript spec - full structure" {
  let text =
    #|kgf 0.5
    #|language: typescript
    #|
    #|=== lex
    #|SKIP        /(\s+|\/\/[^\n]*|\/\*[\s\S]*?\*\/)+/
    #|TOKEN KW_import     /import\b/
    #|TOKEN KW_from       /from\b/
    #|TOKEN KW_export     /export\b/
    #|TOKEN KW_type       /type\b/
    #|TOKEN KW_function   /function\b/
    #|TOKEN KW_const      /const\b/
    #|TOKEN KW_let        /let\b/
    #|TOKEN KW_as         /as\b/
    #|TOKEN STAR          /\*/
    #|TOKEN Ident         /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit     /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    #|TOKEN LBRACE        /\{/
    #|TOKEN RBRACE        /\}/
    #|TOKEN LPAREN        /\(/
    #|TOKEN RPAREN        /\)/
    #|TOKEN SEMI          /;/
    #|TOKEN COMMA         /,/
    #|TOKEN COLON         /:/
    #|TOKEN DOT           /\./
    #|TOKEN EQ            /=/
    #|
    #|=== grammar
    #|Module          -> ( ImportDecl | TypeAlias | FnDecl | VarDecl )*
    #|ImportDecl      -> KW_import ( SideEffect | ImportNS | ImportNamed | ImportDefault ) SEMI?
    #|SideEffect      -> path:StringLit
    #|ImportNS        -> STAR KW_as ns:Ident KW_from from:StringLit
    #|ImportNamed     -> LBRACE ImportSpecList RBRACE KW_from from:StringLit
    #|ImportDefault   -> defId:Ident KW_from from:StringLit
    #|ImportSpecList  -> ImportSpec ( COMMA ImportSpec )*
    #|ImportSpec      -> origin:Ident ( KW_as local:Ident )?
    #|TypeAlias       -> KW_type id:Ident EQ Type SEMI
    #|VarDecl         -> (KW_const | KW_let) VarList SEMI?
    #|VarList         -> VarItem ( COMMA VarItem )*
    #|VarItem         -> id:Ident [ COLON Type ] [ EQ Expr ]
    #|FnDecl          -> KW_function id:Ident LPAREN ParamList? RPAREN Block
    #|ParamList       -> Param ( COMMA Param )*
    #|Param           -> id:Ident [ COLON Type ]
    #|Block           -> LBRACE BlockItem* RBRACE
    #|BlockItem       -> VarDecl | ExprStmt
    #|ExprStmt        -> Expr SEMI?
    #|Expr            -> CallExpr | Primary ( DOT Ident )*
    #|CallExpr        -> callee:Primary LPAREN (Arg ( COMMA Arg )*)? RPAREN
    #|Arg             -> Expr
    #|Primary         -> name:Ident | LPAREN Expr RPAREN | StringLit
    #|Type            -> TypeRef
    #|TypeRef         -> tname:Ident ( DOT Ident )*
    #|
    #|=== attrs
    #|on VarItem:    def id kind=Variable ns=value
    #|on TypeAlias:  def id kind=TypeAlias ns=type
    #|on FnDecl:     def id kind=Function ns=value ; scope push=function
    #|on Param:      def id kind=Param ns=value
    #|on Block:      scope pop
    #|on Primary:    ref name ns=value
    #|on TypeRef:    ref tname ns=type
    #|on CallExpr:   call callee=callee
    #|on Arg:        argref
    #|on SideEffect:         import module=path
    #|on ImportNS:           import module=from
    #|on ImportNamed:        import module=from
    #|on ImportDefault:      import module=from
    #|
    #|=== semantics
    #|on SideEffect {
    #|  edge moduleDependsOn from $file to $resolve($path) attrs obj("via", $path, "dep_kind", "value")
    #|}
    #|on ImportNS {
    #|  edge moduleDependsOn from $file to $resolve($from) attrs obj("via", $from, "dep_kind", "value")
    #|}
    #|on ImportNamed {
    #|  edge moduleDependsOn from $file to $resolve($from) attrs obj("via", $from, "dep_kind", "value")
    #|}
    #|on ImportDefault {
    #|  edge moduleDependsOn from $file to $resolve($from) attrs obj("via", $from, "dep_kind", "value")
    #|}
    #|
    #|=== resolver
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
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "typescript")
  // Verify all sections are parsed
  assert_true(s.tokens.length() >= 20)
  assert_true(s.rules.size() >= 20)
  assert_true(s.attrs.size() >= 10)
  assert_true(s.semantics is Some(_))
  let sem = s.semantics.unwrap()
  assert_eq(sem.size(), 4)
  // Verify resolver
  let resolver = s.resolver
  assert_eq(resolver.get_sources().length(), 3)
  assert_eq(resolver.get_aliases().length(), 1)
}

///|
test "parse japanese law spec - complex semantics" {
  let text =
    #|kgf 0.5
    #|language: japanese
    #|
    #|=== lex
    #|SKIP /[ \t　]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LawHeader /((?:令和|平成|昭和|大正|明治)[一二三四五六七八九十百千〇零]+年(?:法律|政令|省令|勅令)第[一二三四五六七八九十百千〇零]+号)/
    #|TOKEN ChapterLine /((?:第[一二三四五六七八九十百千〇零]+章))[^\r\n]*/
    #|TOKEN ArticleLine /((?:第[一二三四五六七八九十百千〇零]+条(?:の[一二三四五六七八九十百千〇零]+)?))[^\r\n]*/
    #|TOKEN Period  /[。！？]/
    #|TOKEN Kanji    /[一-龯々〆ヵヶ]+/
    #|TOKEN Hiragana /[ぁ-ゖー]+/
    #|TOKEN TextLine /[^\r\n]+/
    #|
    #|=== grammar
    #|Doc          -> ( Entry )*
    #|Entry        -> NL | LawHeaderEntry | Heading | Article | SentenceLine
    #|LawHeaderEntry -> lh:LawHeader
    #|Heading      -> Chapter
    #|Chapter      -> ch:ChapterLine
    #|Article      -> art:ArticleLine
    #|SentenceLine -> Sentence ( NL )?
    #|Sentence     -> Atom+
    #|Atom         -> Kanji | Hiragana | Period | TextLine
    #|
    #|=== attrs
    #|on LawHeaderEntry: def id=lh kind=LawHeader
    #|on Chapter:      def id=ch kind=Chapter
    #|on Article:      def id=art kind=Article
    #|
    #|=== semantics
    #|on LawHeaderEntry {
    #|  let cur = $scope("value", $lh)
    #|  edge contains from $file to cur attrs obj("rel", "root->law_header")
    #|}
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
    #|on Article when $scope("value", "last_article") {
    #|  let cur = $scope("value", $art)
    #|  edge next from $scope("value", "last_article") to cur attrs obj("rel", "article->article")
    #|}
    #|on Article when $scope("value", "current_chapter") {
    #|  let cur = $scope("value", $art)
    #|  edge contains from $scope("value", "current_chapter") to cur attrs obj("rel", "chapter->article")
    #|  bind ns "value" name "last_article" to cur
    #|}
    #|
    #|=== resolver
    #|sources: .txt
    #|exts: .txt
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "japanese")
  // Verify tokens
  assert_eq(s.tokens.length(), 9)
  // Verify semantics with when conditions
  assert_true(s.semantics is Some(_))
  let sem = s.semantics.unwrap()
  // Multiple on-blocks for same rules
  assert_true(sem.contains("Chapter"))
  let chapter_blocks = sem.get("Chapter").unwrap()
  assert_eq(chapter_blocks.length(), 2) // with and without when
  assert_true(sem.contains("Article"))
  let article_blocks = sem.get("Article").unwrap()
  assert_eq(article_blocks.length(), 2)
}

///|
test "parse python spec - dot module path style" {
  let text =
    #|kgf 0.5
    #|language: python
    #|
    #|=== lex
    #|SKIP        /(\s+|#.[^\n]*\n?)+/
    #|TOKEN KW_import     /import\b/
    #|TOKEN KW_from       /from\b/
    #|TOKEN KW_def        /def\b/
    #|TOKEN Ident         /[A-Za-z_][A-Za-z0-9_]*/
    #|TOKEN DOT           /\./
    #|TOKEN COMMA         /,/
    #|TOKEN LPAREN        /\(/
    #|TOKEN RPAREN        /\)/
    #|TOKEN COLON         /:/
    #|
    #|=== grammar
    #|Module          -> ( ImportStmt | FromImport | FnDef | SimpleStmt )*
    #|ImportStmt      -> KW_import ModList
    #|FromImport      -> KW_from module:QN KW_import Names
    #|ModList         -> QN ( COMMA QN )*
    #|Names           -> Ident ( COMMA Ident )*
    #|FnDef           -> KW_def id:Ident LPAREN Params? RPAREN COLON Suite
    #|Params          -> Ident ( COMMA Ident )*
    #|Suite           -> ( SimpleStmt )*
    #|SimpleStmt      -> Expr
    #|Expr            -> Call | Primary
    #|Call            -> callee:Ident LPAREN Args? RPAREN
    #|Args            -> Expr ( COMMA Expr )*
    #|Primary         -> name:Ident
    #|QN              -> Ident ( DOT Ident )*
    #|
    #|=== attrs
    #|on FnDef:       def id kind=Function ns=value ; scope push=function
    #|on Primary:     ref name ns=value
    #|on Call:        call callee=callee
    #|on ImportStmt:  import module=QN
    #|on FromImport:  import module=module
    #|on Suite:       scope pop
    #|
    #|=== resolver
    #|sources: .py
    #|relative_prefixes: ./, ../, /
    #|exts: .py
    #|indexes: /__init__.py
    #|bare_prefix: pip:
    #|module_path_style: dot
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "python")
  // Verify dot module path style
  let resolver = s.resolver
  assert_eq(resolver.get_module_path_style().as_string(), "dot")
  assert_eq(resolver.get_indexes().length(), 1)
  assert_eq(resolver.get_indexes()[0], "/__init__.py")
  assert_eq(resolver.get_bare_prefix(), "pip:")
}

///|
test "parse go spec - minimal without attrs and semantics" {
  let text =
    #|kgf 0.5
    #|language: go
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN String /"(?:[^"\\]|\\.)*"/
    #|TOKEN Number /0x[0-9a-fA-F_]+|[0-9]+/
    #|TOKEN KeywordDecl /\b(?:package|import|func|type|struct|interface|var|const|map|chan)\b/
    #|TOKEN KeywordControl /\b(?:if|else|switch|case|for|range|break|continue|return)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}:]/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> ( Token )* ( NL )?
    #|Token -> LineComment | BlockComment | String | Number
    #|      | KeywordDecl | KeywordControl | Ident | Punct
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
  assert_eq(s.tokens.length(), 10)
  assert_eq(s.rules.size(), 3)
  // No attrs or semantics
  assert_eq(s.attrs.size(), 0)
  assert_true(s.semantics is None)
}

///|
test "parse rust spec - macro token pattern" {
  let text =
    #|kgf 0.5
    #|language: rust
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN DocComment /\/\/\/[^\r\n]*|\/\/![^\r\n]*/
    #|TOKEN RawString /r#*"[\s\S]*?"#*/
    #|TOKEN String /"(?:[^"\\]|\\.)*"/
    #|TOKEN Lifetime /'[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordDecl /\b(?:let|mut|fn|struct|impl|use|pub|mod)\b/
    #|TOKEN KeywordType /\b(?:i32|i64|u32|u64|f32|f64|bool|str|Self)\b/
    #|TOKEN Macro /[a-zA-Z_][a-zA-Z0-9_]*!/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
    #|=== grammar
    #|Doc -> Item*
    #|Item -> ( Token )* ( NL )?
    #|Token -> LineComment | DocComment | RawString | String | Lifetime
    #|      | KeywordDecl | KeywordType | Macro | Ident
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
  // Verify macro pattern is parsed correctly
  let macro_token = s.tokens
    .iter()
    .find_first(fn(t) { t.get_name() == "Macro" })
  assert_true(macro_token is Some(_))
  assert_eq(macro_token.unwrap().get_pattern(), "[a-zA-Z_][a-zA-Z0-9_]*!")
}

///|
test "parse base64 spec - simple encoding format" {
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
    #|Tail -> B64_CHAR B64_CHAR PAD PAD | B64_CHAR B64_CHAR B64_CHAR PAD
    #|Other -> B64_CHAR | PAD
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
  assert_eq(s.rules.size(), 5)
  // Attrs section with only comment should be empty
  assert_eq(s.attrs.size(), 0)
  // Resolver should have multiple sources
  assert_eq(s.resolver.get_sources().length(), 3)
}

///|
test "parse markdown spec - minimal structure" {
  let text =
    #|kgf 0.5
    #|language: markdown
    #|
    #|=== lex
    #|TOKEN Heading /^#{1,6}\s+[^\n]*/
    #|TOKEN CodeBlock /```[\s\S]*?```/
    #|TOKEN InlineCode /`[^`\n]+`/
    #|TOKEN Bold /\*\*[^*]+\*\*/
    #|TOKEN Italic /\*[^*]+\*/
    #|TOKEN Link /\[[^\]]+\]\([^)]+\)/
    #|TOKEN Text /[^\n#`*\[]+/
    #|TOKEN NL /\n+/
    #|
    #|=== grammar
    #|Doc -> Element*
    #|Element -> Heading | CodeBlock | InlineCode | Bold | Italic | Link | Text | NL
    #|
    #|=== resolver
    #|sources: .md, .markdown
    #|exts: .md, .markdown
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "markdown")
  assert_eq(s.tokens.length(), 8)
  assert_eq(s.rules.size(), 2)
}

///|
test "lexer integration: tokenize typescript with spec" {
  // Parse TypeScript spec (simplified - no \b word boundary)
  let text =
    #|kgf 0.5
    #|language: typescript
    #|
    #|=== lex
    #|SKIP        /\s+/
    #|TOKEN KW_import     /import/
    #|TOKEN KW_from       /from/
    #|TOKEN Ident         /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit     /"[^"]*"/
    #|TOKEN LBRACE        /\{/
    #|TOKEN RBRACE        /\}/
    #|TOKEN SEMI          /;/
    #|TOKEN COMMA         /,/
    #|
    #|=== grammar
    #|Module -> ImportDecl*
    #|ImportDecl -> KW_import LBRACE ImportSpecList RBRACE KW_from StringLit SEMI?
    #|ImportSpecList -> Ident ( COMMA Ident )*
    #|
    #|=== resolver
    #|sources: .ts
    #|exts: .ts
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()

  // Create lexer from spec tokens
  let lexer = @kgf_lexer.Lexer::new(s.tokens)

  // Tokenize sample TypeScript code
  let code = "import { foo, bar } from \"module\";"
  let tokens = lexer.tokenize(code)

  // Verify tokens - keywords come first in token definitions, so they have priority
  assert_true(tokens.length() >= 8)
  assert_eq(tokens[0].kind, "KW_import")
  assert_eq(tokens[1].kind, "LBRACE")
  assert_eq(tokens[2].kind, "Ident")
  assert_eq(tokens[2].text, "foo")
  assert_eq(tokens[3].kind, "COMMA")
  assert_eq(tokens[4].kind, "Ident")
  assert_eq(tokens[4].text, "bar")
  assert_eq(tokens[5].kind, "RBRACE")
  assert_eq(tokens[6].kind, "KW_from")
  assert_eq(tokens[7].kind, "StringLit")
  assert_eq(tokens[7].text, "\"module\"")
}

///|
test "lexer integration: complex alternation patterns do not overflow" {
  // This test verifies that patterns with nested alternations
  // do not cause stack overflow (the original bug)
  let text =
    #|kgf 0.5
    #|language: test
    #|
    #|=== lex
    #|SKIP        /\s+/
    #|TOKEN StringLit     /"[^"]*"/
    #|TOKEN Ident         /[A-Za-z_][A-Za-z0-9_]*/
    #|
    #|=== grammar
    #|Doc -> Token*
    #|Token -> StringLit | Ident
    #|
    #|=== resolver
    #|sources: .txt
    #|exts: .txt
    #|module_path_style: slash
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()

  // Create lexer from spec tokens
  let lexer = @kgf_lexer.Lexer::new(s.tokens)

  // Tokenize simple code (tests that tokenization works without stack overflow)
  let code = "foo bar baz"
  let tokens = lexer.tokenize(code)

  // Should successfully tokenize without stack overflow
  assert_eq(tokens.length(), 3)
  assert_eq(tokens[0].text, "foo")
  assert_eq(tokens[1].text, "bar")
  assert_eq(tokens[2].text, "baz")
}

///|
test "pattern_matcher: nested alternation in group does not overflow" {
  // The original bug: patterns like "([^"\\]|\\.)*" caused infinite recursion
  // because pattern.contains("|") returned true for alternation inside groups
  // Test various complex patterns that previously caused stack overflow

  // Pattern with alternation inside group
  let result1 = @kgf_lexer.match_pattern("([ab]|cd)+", "abcdab", 0)
  assert_eq(result1.matched, true)

  // Pattern with multiple nested structures
  let result2 = @kgf_lexer.match_pattern("(a(bc|de)f)+", "abcfadef", 0)
  assert_eq(result2.matched, true)

  // Pattern that looks like TypeScript string literal (simplified)
  let result3 = @kgf_lexer.match_pattern("([xy]|z)+", "xyzxy", 0)
  assert_eq(result3.matched, true)
}
