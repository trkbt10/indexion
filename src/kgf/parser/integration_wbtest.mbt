// Integration tests for parsing reference KGF spec files.
// These tests verify that the parser can handle real-world spec files.

// Note: The actual spec files are stored in kgf/kgfs/ directory.
// These tests use embedded spec content to verify parsing behavior.

///|
test "parse typescript spec - full structure" {
  let text =
    #|kgf 0.6
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
    #|module_path_style: slash
    #|aliases:
    #|  -
    #|    pattern: ^@/(.*)$
    #|    replace: src/\1
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: package.json
    #|    query: exports["."].types
    #|    when: type
    #|  - manifest: package.json @ exports["."].import | exports["."].default | main | module
    #|  - index: /index.ts, /index.tsx, /index.d.ts, /index.js
    #|  - ext: .ts, .tsx, .d.ts, .js
    #|  - fallback: npm:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "typescript")
  // Verify all sections are parsed
  assert_true(s.tokens.length() >= 20)
  assert_true(s.rules.length() >= 20)
  assert_true(s.attrs.length() >= 10)
  assert_true(s.semantics is Some(_))
  let sem = s.semantics.unwrap()
  assert_eq(sem.length(), 4)
  // Verify resolver
  let resolver = s.resolver
  assert_eq(resolver.get_sources().length(), 3)
  assert_eq(resolver.get_aliases().length(), 1)
  // Verify resolve chain
  assert_true(resolver.has_resolve_chain())
  assert_eq(resolver.get_resolve_chain().length(), 5)
}

///|
test "parse japanese law spec - complex semantics" {
  let text =
    #|kgf 0.6
    #|language: japanese-law
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
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .txt
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "japanese-law")
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
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
}

///|
test "parse python spec - dot module path style" {
  let text =
    #|kgf 0.6
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
    #|module_path_style: dot
    #|resolve:
    #|  - marker: __init__.py
    #|  - ext: .py
    #|  - fallback: pip:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "python")
  // Verify dot module path style
  let resolver = s.resolver
  assert_eq(resolver.get_module_path_style().as_string(), "dot")
  // Verify resolve chain
  assert_true(resolver.has_resolve_chain())
  assert_eq(resolver.get_resolve_chain().length(), 3)
  assert_eq(
    resolver.get_resolve_chain()[0].get_step_type().as_string(),
    "marker",
  )
}

///|
test "parse go spec - minimal without attrs and semantics" {
  let text =
    #|kgf 0.6
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
    #|Item -> Token+ NL?
    #|     | NL
    #|Token -> LineComment | BlockComment | String | Number
    #|      | KeywordDecl | KeywordControl | Ident | Punct
    #|
    #|=== resolver
    #|sources: .go
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .go
    #|  - fallback: go:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "go")
  assert_eq(s.tokens.length(), 10)
  assert_eq(s.rules.length(), 3)
  // No attrs or semantics
  assert_eq(s.attrs.length(), 0)
  assert_true(s.semantics is None)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
}

///|
test "parse rust spec - macro token pattern" {
  let text =
    #|kgf 0.6
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
    #|Item -> Token+ NL?
    #|     | NL
    #|Token -> LineComment | DocComment | RawString | String | Lifetime
    #|      | KeywordDecl | KeywordType | Macro | Ident
    #|
    #|=== resolver
    #|sources: .rs
    #|relative_prefixes: ./
    #|module_path_style: coloncol
    #|resolve:
    #|  - manifest: Cargo.toml @ lib.path
    #|  - index: /mod.rs, /lib.rs
    #|  - sibling: .rs
    #|  - ext: .rs
    #|  - fallback: crate:
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
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 5)
}

///|
test "parse base64 spec - simple encoding format" {
  let text =
    #|kgf 0.6
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
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .b64, .base64, .txt
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "base64")
  assert_eq(s.tokens.length(), 3)
  assert_eq(s.rules.length(), 5)
  // Attrs section with only comment should be empty
  assert_eq(s.attrs.length(), 0)
  // Resolver should have multiple sources
  assert_eq(s.resolver.get_sources().length(), 3)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
}

///|
test "parse markdown spec - minimal structure" {
  let text =
    #|kgf 0.6
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
    #|module_path_style: slash
    #|resolve:
    #|  - index: /README.md, /index.md
    #|  - ext: .md, .markdown
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "markdown")
  assert_eq(s.tokens.length(), 8)
  assert_eq(s.rules.length(), 2)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
}

///|
test "lexer integration: tokenize typescript with spec" {
  // Parse TypeScript spec (simplified - no \b word boundary)
  let text =
    #|kgf 0.6
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
    #|module_path_style: slash
    #|resolve:
    #|  - index: /index.ts
    #|  - ext: .ts
    #|  - fallback: npm:
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
    #|kgf 0.6
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
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .txt
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

///|
test "parse html spec - web document structure" {
  let text =
    #|kgf 0.6
    #|language: html
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /<!--[\s\S]*?-->/
    #|TOKEN Doctype /<!DOCTYPE[^>]*>/i
    #|TOKEN TagOpen /<[a-zA-Z][a-zA-Z0-9-]*/
    #|TOKEN TagClose /<\/[a-zA-Z][a-zA-Z0-9-]*>/
    #|TOKEN TagSelfClose /\/>/
    #|TOKEN TagEnd />/
    #|TOKEN AttrName /[a-zA-Z_:][a-zA-Z0-9_:.-]*/
    #|TOKEN AttrValue /"[^"]*"|'[^']*'/
    #|TOKEN EQ /=/
    #|TOKEN Text /[^<]+/
    #|
    #|=== grammar
    #|Doc -> ( Element | Comment | Doctype | Text | NL )*
    #|Element -> TagOpen Attributes? ( TagSelfClose | TagEnd Content TagClose )
    #|Attributes -> Attribute+
    #|Attribute -> AttrName ( EQ AttrValue )?
    #|Content -> ( Element | Comment | Text | NL )*
    #|
    #|=== attrs
    #|on Attribute: def id=AttrName kind=Attribute
    #|
    #|=== resolver
    #|sources: .html, .htm
    #|relative_prefixes: ./, ../, /
    #|module_path_style: slash
    #|resolve:
    #|  - index: /index.html, /index.htm, /default.html
    #|  - ext: .html, .htm
    #|  - fallback: url:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "html")
  assert_eq(s.tokens.length(), 12)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 3)
  assert_eq(
    s.resolver.get_resolve_chain()[0].get_step_type().as_string(),
    "index",
  )
  assert_eq(
    s.resolver.get_resolve_chain()[2].get_step_type().as_string(),
    "fallback",
  )
}

///|
test "parse javascript spec - esm module system" {
  let text =
    #|kgf 0.6
    #|language: javascript
    #|
    #|=== lex
    #|SKIP /(\s+|\/\/[^\n]*|\/\*[\s\S]*?\*\/)+/
    #|TOKEN KW_import /import\b/
    #|TOKEN KW_export /export\b/
    #|TOKEN KW_from /from\b/
    #|TOKEN KW_default /default\b/
    #|TOKEN KW_function /function\b/
    #|TOKEN KW_const /const\b/
    #|TOKEN KW_let /let\b/
    #|TOKEN KW_var /var\b/
    #|TOKEN KW_as /as\b/
    #|TOKEN STAR /\*/
    #|TOKEN Ident /[A-Za-z_\$][A-Za-z0-9_\$]*/
    #|TOKEN StringLit /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'|`([^`\\]|\\.)*`/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN LPAREN /\(/
    #|TOKEN RPAREN /\)/
    #|TOKEN SEMI /;/
    #|TOKEN COMMA /,/
    #|TOKEN DOT /\./
    #|TOKEN EQ /=/
    #|
    #|=== grammar
    #|Module -> ( ImportDecl | ExportDecl | VarDecl | FnDecl )*
    #|ImportDecl -> KW_import ( ImportNS | ImportNamed | ImportDefault | StringLit ) KW_from? StringLit? SEMI?
    #|ImportNS -> STAR KW_as Ident
    #|ImportNamed -> LBRACE ImportSpec ( COMMA ImportSpec )* RBRACE
    #|ImportSpec -> Ident ( KW_as Ident )?
    #|ImportDefault -> Ident
    #|ExportDecl -> KW_export ( KW_default? ( VarDecl | FnDecl ) | ExportNamed )
    #|ExportNamed -> LBRACE Ident ( COMMA Ident )* RBRACE
    #|VarDecl -> ( KW_const | KW_let | KW_var ) Ident EQ Expr SEMI?
    #|FnDecl -> KW_function Ident LPAREN RPAREN LBRACE RBRACE
    #|Expr -> Ident | StringLit
    #|
    #|=== attrs
    #|on ImportDecl: import module=StringLit
    #|on VarDecl: def id=Ident kind=Variable
    #|on FnDecl: def id=Ident kind=Function
    #|
    #|=== resolver
    #|sources: .js, .mjs, .cjs
    #|relative_prefixes: ./, ../, /
    #|module_path_style: slash
    #|resolve:
    #|  - manifest: package.json @ exports["."].import | exports["."].default | main | module
    #|  - index: /index.js, /index.mjs
    #|  - ext: .js, .mjs, .cjs
    #|  - fallback: npm:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "javascript")
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 4)
  assert_eq(
    s.resolver.get_resolve_chain()[0].get_step_type().as_string(),
    "manifest",
  )
}

///|
test "parse css spec - stylesheet structure" {
  let text =
    #|kgf 0.6
    #|language: css
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /\/\*[\s\S]*?\*\//
    #|TOKEN AtRule /@[a-zA-Z-]+/
    #|TOKEN Selector /[.#]?[a-zA-Z_-][a-zA-Z0-9_-]*/
    #|TOKEN Property /[a-zA-Z-]+/
    #|TOKEN Value /[^;{}]+/
    #|TOKEN LBRACE /\{/
    #|TOKEN RBRACE /\}/
    #|TOKEN COLON /:/
    #|TOKEN SEMI /;/
    #|TOKEN URL /url\([^)]*\)/
    #|TOKEN String /"[^"]*"|'[^']*'/
    #|
    #|=== grammar
    #|Doc -> ( Rule | AtRule | Comment | NL )*
    #|Rule -> Selector LBRACE Declaration* RBRACE
    #|Declaration -> Property COLON Value SEMI?
    #|
    #|=== resolver
    #|sources: .css
    #|relative_prefixes: ./, ../, /
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .css
    #|  - fallback: url:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "css")
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 2)
}

///|
test "parse c spec - system programming language" {
  let text =
    #|kgf 0.6
    #|language: c
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN Preprocessor /#\s*(include|define|ifdef|ifndef|endif|if|else|elif|undef|pragma|error|warning)[^\r\n]*/
    #|TOKEN IncludeSystem /<[^>]+>/
    #|TOKEN IncludeLocal /"[^"]+"/
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F]+|0b[01]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?[fFlLuU]*/
    #|TOKEN KeywordType /\b(void|int|char|short|long|float|double|signed|unsigned|struct|union|enum|typedef|const|volatile|static|extern|register|auto|inline|_Bool|_Complex|_Imaginary)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|case|default|for|while|do|break|continue|return|goto|sizeof)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||<<|>>|->|\.\.\./
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|Module -> ( PreprocessorDirective | FunctionDef | Declaration | NL )*
    #|PreprocessorDirective -> Preprocessor NL?
    #|                      | Preprocessor IncludeSystem NL?
    #|                      | Preprocessor IncludeLocal NL?
    #|FunctionDef -> TypeSpec id:Ident LPAREN ParamList? RPAREN Block
    #|Declaration -> TypeSpec VarList SEMI
    #|TypeSpec -> KeywordType+
    #|VarList -> VarDecl ( COMMA VarDecl )*
    #|VarDecl -> Ident ( EQ Expr )?
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> TypeSpec Ident
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> Declaration | ExprStmt | ControlStmt | Block | NL
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> Ident | Number | String | Char
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on FunctionDef: def id kind=Function ns=value
    #|on VarDecl: def id=Ident kind=Variable ns=value
    #|on PreprocessorDirective: import module=IncludeLocal
    #|
    #|=== semantics
    #|on PreprocessorDirective when $IncludeLocal {
    #|  edge moduleDependsOn from $file to $resolve($IncludeLocal) attrs obj("via", $IncludeLocal, "dep_kind", "include")
    #|}
    #|
    #|=== resolver
    #|sources: .c, .h
    #|relative_prefixes: ./, ../
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .h, .c
    #|  - fallback: system:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "c")
  assert_true(s.tokens.length() >= 15)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 2)
  assert_eq(
    s.resolver.get_resolve_chain()[0].get_step_type().as_string(),
    "ext",
  )
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "system:")
}

///|
test "parse cpp spec - c++ with namespaces and templates" {
  let text =
    #|kgf 0.6
    #|language: cpp
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN Preprocessor /#\s*(include|define|ifdef|ifndef|endif|if|else|elif|undef|pragma|error|warning)[^\r\n]*/
    #|TOKEN IncludeSystem /<[^>]+>/
    #|TOKEN IncludeLocal /"[^"]+"/
    #|TOKEN String /"([^"\\]|\\.)*"|R"[^(]*\([^)]*\)[^"]*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F]+|0b[01]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?[fFlLuU]*/
    #|TOKEN KeywordType /\b(void|int|char|short|long|float|double|bool|wchar_t|char8_t|char16_t|char32_t|signed|unsigned|auto|decltype|const|volatile|mutable|static|extern|register|inline|virtual|explicit|constexpr|consteval|constinit)\b/
    #|TOKEN KeywordClass /\b(class|struct|union|enum|namespace|template|typename|public|private|protected|friend|using|typedef)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|case|default|for|while|do|break|continue|return|goto|throw|try|catch|new|delete|sizeof|alignof|typeid|noexcept|co_await|co_yield|co_return)\b/
    #|TOKEN KeywordOther /\b(this|nullptr|true|false|static_cast|dynamic_cast|const_cast|reinterpret_cast|operator|override|final)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN ScopeOp /::/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||<<|>>|->|\.\.\.|<=>|\*\*|##/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|Module -> ( PreprocessorDirective | NamespaceDecl | ClassDecl | FunctionDef | Declaration | NL )*
    #|PreprocessorDirective -> Preprocessor NL?
    #|                      | Preprocessor IncludeSystem NL?
    #|                      | Preprocessor IncludeLocal NL?
    #|NamespaceDecl -> KeywordClass ns:Ident LBRACE Module RBRACE
    #|ClassDecl -> KeywordClass id:Ident LBRACE ClassBody RBRACE SEMI?
    #|ClassBody -> ( AccessSpec | MemberDecl | NL )*
    #|AccessSpec -> KeywordClass COLON
    #|MemberDecl -> TypeSpec Ident SEMI
    #|          | FunctionDef
    #|FunctionDef -> TypeSpec id:Ident LPAREN ParamList? RPAREN Block
    #|Declaration -> TypeSpec VarList SEMI
    #|TypeSpec -> ( KeywordType | QualifiedName )+
    #|QualifiedName -> Ident ( ScopeOp Ident )*
    #|VarList -> VarDecl ( COMMA VarDecl )*
    #|VarDecl -> Ident ( EQ Expr )?
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> TypeSpec Ident
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> Declaration | ExprStmt | ControlStmt | Block | NL
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> QualifiedName | Number | String | Char
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|COLON -> Punct
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on NamespaceDecl: def id=ns kind=Namespace ns=type ; scope push=namespace
    #|on ClassDecl: def id kind=Class ns=type
    #|on FunctionDef: def id kind=Function ns=value
    #|on VarDecl: def id=Ident kind=Variable ns=value
    #|on PreprocessorDirective: import module=IncludeLocal
    #|
    #|=== semantics
    #|on PreprocessorDirective when $IncludeLocal {
    #|  edge moduleDependsOn from $file to $resolve($IncludeLocal) attrs obj("via", $IncludeLocal, "dep_kind", "include")
    #|}
    #|on PreprocessorDirective when $IncludeSystem {
    #|  edge moduleDependsOn from $file to concat("system:", $IncludeSystem) attrs obj("via", $IncludeSystem, "dep_kind", "system")
    #|}
    #|
    #|=== resolver
    #|sources: .cpp, .cc, .cxx, .hpp, .hxx, .h, .hh
    #|relative_prefixes: ./, ../
    #|module_path_style: slash
    #|resolve:
    #|  - ext: .hpp, .hxx, .h, .hh, .cpp, .cc, .cxx
    #|  - fallback: system:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "cpp")
  assert_true(s.tokens.length() >= 18)
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 2)
  // Verify sources include common C++ extensions
  assert_eq(s.resolver.get_sources().length(), 7)
}

///|
test "parse csharp spec - .NET language with namespaces" {
  let text =
    #|kgf 0.6
    #|language: csharp
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\/\/[^\r\n]*/
    #|TOKEN String /"([^"\\]|\\.)*"|@"[^"]*"|$"([^"\\{]|\\.|\{[^}]*\})*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F]+|0b[01]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?[fFdDmMlLuU]*/
    #|TOKEN KeywordType /\b(void|int|byte|sbyte|short|ushort|long|ulong|float|double|decimal|bool|char|string|object|dynamic|var)\b/
    #|TOKEN KeywordClass /\b(class|struct|interface|enum|record|namespace|using|static|abstract|sealed|partial|public|private|protected|internal|virtual|override|new|readonly|const|volatile|extern|unsafe|ref|out|in|params)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|case|default|for|foreach|while|do|break|continue|return|goto|throw|try|catch|finally|lock|yield|async|await|when|is|as|typeof|sizeof|nameof|stackalloc)\b/
    #|TOKEN KeywordOther /\b(this|base|null|true|false|value|get|set|init|add|remove|event|delegate|where|select|from|orderby|group|join|let|into)\b/
    #|TOKEN Ident /[a-zA-Z_@][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||<<|>>|=>|->|\?\?|\?\.|\?\[/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|Module -> ( UsingDirective | NamespaceDecl | TypeDecl | NL )*
    #|UsingDirective -> KW_using ns:QualifiedName SEMI
    #|KW_using -> KeywordClass
    #|NamespaceDecl -> KW_namespace ns:QualifiedName LBRACE Module RBRACE
    #|KW_namespace -> KeywordClass
    #|TypeDecl -> Modifiers? TypeKind id:Ident LBRACE TypeBody RBRACE
    #|Modifiers -> KeywordClass+
    #|TypeKind -> KeywordClass
    #|TypeBody -> ( MemberDecl | NL )*
    #|MemberDecl -> Modifiers? TypeSpec Ident ( MethodDecl | PropertyDecl | FieldDecl )
    #|MethodDecl -> LPAREN ParamList? RPAREN Block
    #|PropertyDecl -> LBRACE AccessorDecl+ RBRACE
    #|AccessorDecl -> KeywordOther ( Block | SEMI )
    #|FieldDecl -> ( EQ Expr )? SEMI
    #|TypeSpec -> ( KeywordType | QualifiedName ) GenericArgs?
    #|QualifiedName -> Ident ( DOT Ident )*
    #|GenericArgs -> LT TypeSpec ( COMMA TypeSpec )* GT
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> TypeSpec Ident
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> Declaration | ExprStmt | ControlStmt | Block | NL
    #|Declaration -> TypeSpec VarDecl ( COMMA VarDecl )* SEMI
    #|VarDecl -> Ident ( EQ Expr )?
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> QualifiedName | Number | String | Char
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|LT -> Operator
    #|GT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on UsingDirective: import module=ns
    #|on NamespaceDecl: def id=ns kind=Namespace ns=type ; scope push=namespace
    #|on TypeDecl: def id kind=Class ns=type
    #|on MethodDecl: def id=Ident kind=Function ns=value
    #|on VarDecl: def id=Ident kind=Variable ns=value
    #|
    #|=== semantics
    #|on UsingDirective {
    #|  edge moduleDependsOn from $file to $resolve($ns) attrs obj("via", $ns, "dep_kind", "using")
    #|}
    #|
    #|=== resolver
    #|sources: .cs
    #|relative_prefixes: ./, ../
    #|module_path_style: dot
    #|resolve:
    #|  - ext: .cs
    #|  - fallback: nuget:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "csharp")
  assert_true(s.tokens.length() >= 15)
  // Verify module path style is dot (C# uses namespaces like System.Collections.Generic)
  assert_eq(s.resolver.get_module_path_style().as_string(), "dot")
  // Verify resolve chain
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 2)
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "nuget:")
}

///|
test "parse moonbit spec - moon ecosystem with packages" {
  let text =
    #|kgf 0.6
    #|language: moonbit
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN DocComment /\/\/\/\|[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN MultiLineString /#\|[^\r\n]*/
    #|TOKEN Char /'([^'\\]|\\.)'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN KeywordType /\b(Int|Int64|UInt|UInt64|Float|Double|Bool|Char|String|Byte|Bytes|Unit|Array|Map|Option|Result|Error|Self|Any)\b/
    #|TOKEN KeywordDecl /\b(fn|let|mut|const|type|struct|enum|trait|impl|pub|priv|readonly|test|derive)\b/
    #|TOKEN KeywordControl /\b(if|else|match|for|while|loop|break|continue|return|guard|raise|try|catch|not|and|or)\b/
    #|TOKEN KeywordOther /\b(true|false|Some|None|Ok|Err|self|as|is|in|with)\b/
    #|TOKEN PackageRef /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||=>|->|\.\.|\.\.=/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|Module -> ( TopDecl | NL )*
    #|TopDecl -> PubMod? ( FnDecl | StructDecl | EnumDecl | TypeDecl | TraitDecl | ImplDecl | LetDecl | TestDecl )
    #|PubMod -> KeywordDecl
    #|FnDecl -> KW_fn id:Ident GenericParams? LPAREN ParamList? RPAREN ReturnType? FnBody
    #|KW_fn -> KeywordDecl
    #|GenericParams -> LBRACKET TypeParam ( COMMA TypeParam )* RBRACKET
    #|TypeParam -> TypeIdent ( COLON TypeBound )?
    #|TypeBound -> TypeRef ( PLUS TypeRef )*
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> id:Ident COLON TypeRef
    #|ReturnType -> ARROW TypeRef
    #|FnBody -> Block | EQ Expr
    #|StructDecl -> KW_struct id:TypeIdent GenericParams? LBRACE StructBody RBRACE
    #|KW_struct -> KeywordDecl
    #|StructBody -> ( FieldDecl | NL )*
    #|FieldDecl -> id:Ident COLON TypeRef
    #|EnumDecl -> KW_enum id:TypeIdent GenericParams? LBRACE EnumBody RBRACE
    #|KW_enum -> KeywordDecl
    #|EnumBody -> ( Variant | NL )*
    #|Variant -> id:TypeIdent ( LPAREN TypeRef ( COMMA TypeRef )* RPAREN )?
    #|TypeDecl -> KW_type id:TypeIdent GenericParams? EQ TypeRef
    #|KW_type -> KeywordDecl
    #|TraitDecl -> KW_trait id:TypeIdent LBRACE TraitBody RBRACE
    #|KW_trait -> KeywordDecl
    #|TraitBody -> ( TraitMethod | NL )*
    #|TraitMethod -> KW_fn id:Ident LPAREN ParamList? RPAREN ReturnType?
    #|ImplDecl -> KW_impl TypeRef ( KW_for TypeRef )? ( KW_with ImplMethod )+
    #|KW_impl -> KeywordDecl
    #|KW_for -> KeywordControl
    #|KW_with -> KeywordOther
    #|ImplMethod -> Ident LPAREN ParamList? RPAREN ReturnType? FnBody
    #|LetDecl -> KW_let Mutability? id:Ident ( COLON TypeRef )? EQ Expr
    #|KW_let -> KeywordDecl
    #|Mutability -> KeywordDecl
    #|TestDecl -> KW_test StringLit? Block
    #|KW_test -> KeywordDecl
    #|StringLit -> String
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> LetDecl | ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr SEMI?
    #|ControlStmt -> IfExpr | MatchExpr | ForExpr | WhileExpr
    #|IfExpr -> KeywordControl Expr Block ( KeywordControl Block )?
    #|MatchExpr -> KeywordControl Expr LBRACE MatchArm* RBRACE
    #|MatchArm -> Pattern ARROW Expr COMMA?
    #|Pattern -> Ident | TypeIdent | UNDERSCORE
    #|ForExpr -> KeywordControl Ident KeywordOther Expr Block
    #|WhileExpr -> KeywordControl Expr Block
    #|Expr -> Primary ( DOT MethodCall )* | QualifiedRef
    #|QualifiedRef -> pkg:PackageRef DOT path:Ident ( DOT Ident )*
    #|MethodCall -> Ident LPAREN ArgList? RPAREN
    #|ArgList -> Expr ( COMMA Expr )*
    #|Primary -> Ident | TypeIdent | Number | String | Char | PackageRef | LPAREN Expr RPAREN
    #|TypeRef -> TypeIdent GenericArgs? | PackageRef DOT TypeIdent GenericArgs?
    #|GenericArgs -> LBRACKET TypeRef ( COMMA TypeRef )* RBRACKET
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|COLON -> Punct
    #|DOT -> Punct
    #|ARROW -> Operator
    #|EQ -> Operator
    #|PLUS -> Operator
    #|UNDERSCORE -> Ident
    #|
    #|=== attrs
    #|on FnDecl: def id kind=Function ns=value
    #|on StructDecl: def id kind=Struct ns=type
    #|on EnumDecl: def id kind=Enum ns=type
    #|on TypeDecl: def id kind=TypeAlias ns=type
    #|on TraitDecl: def id kind=Trait ns=type
    #|on ImplDecl: impl type=TypeRef
    #|on FieldDecl: def id kind=Field ns=value
    #|on Variant: def id kind=Variant ns=type
    #|on Param: def id kind=Param ns=value
    #|on LetDecl: def id kind=Variable ns=value
    #|on TestDecl: def kind=Test
    #|on QualifiedRef: import module=pkg ; ref path ns=value
    #|
    #|=== semantics
    #|on QualifiedRef {
    #|  edge moduleDependsOn from $file to $resolve($pkg) attrs obj("via", $pkg, "dep_kind", "value")
    #|}
    #|
    #|=== resolver
    #|sources: .mbt
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: moon.pkg.json
    #|    query: import
    #|  - marker: moon.pkg.json
    #|  - ext: .mbt
    #|  - fallback: moon:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "moonbit")
  // 17 TOKEN definitions in lex section
  assert_true(s.tokens.length() >= 17)
  // Verify attrs includes package reference handling
  assert_true(s.attrs.length() >= 11)
  // Verify resolver
  assert_eq(s.resolver.get_sources().length(), 1)
  assert_eq(s.resolver.get_sources()[0], ".mbt")
  // Verify resolve chain - moonbit uses moon.pkg.json manifest
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 4)
  // First step: manifest for moon.pkg.json
  assert_eq(
    s.resolver.get_resolve_chain()[0].get_step_type().as_string(),
    "manifest",
  )
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "moon.pkg.json")
  // Second step: marker for package detection
  assert_eq(
    s.resolver.get_resolve_chain()[1].get_step_type().as_string(),
    "marker",
  )
  // Last step: fallback to moon registry
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "moon:")
}

///|
test "parse java spec - maven/gradle ecosystem" {
  let text =
    #|kgf 0.6
    #|language: java
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\*\*[\s\S]*?\*\//
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?[fFdDlL]?/
    #|TOKEN Annotation /@[a-zA-Z_][a-zA-Z0-9_.]*/
    #|TOKEN KeywordPackage /\b(package|import)\b/
    #|TOKEN KeywordType /\b(void|int|byte|short|long|float|double|boolean|char|var)\b/
    #|TOKEN KeywordClass /\b(class|interface|enum|record|extends|implements|abstract|final|static|public|private|protected|default|sealed|non-sealed|permits)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|case|for|while|do|break|continue|return|throw|try|catch|finally|assert|yield)\b/
    #|TOKEN KeywordOther /\b(new|this|super|null|true|false|instanceof|synchronized|volatile|transient|native|strictfp|throws)\b/
    #|TOKEN Ident /[a-zA-Z_$][a-zA-Z0-9_$]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||<<|>>|>>>|->|::/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|CompilationUnit -> PackageDecl? ImportDecl* TypeDecl*
    #|PackageDecl -> KeywordPackage pkg:QualifiedName SEMI
    #|ImportDecl -> KeywordPackage imp:QualifiedName ( DOT STAR )? SEMI
    #|TypeDecl -> Annotation* Modifiers? TypeKind id:Ident GenericParams? Inheritance? LBRACE ClassBody RBRACE
    #|Modifiers -> KeywordClass+
    #|TypeKind -> KeywordClass
    #|GenericParams -> LT TypeParam ( COMMA TypeParam )* GT
    #|TypeParam -> Ident ( KeywordClass TypeRef )?
    #|Inheritance -> KeywordClass TypeRef ( COMMA TypeRef )*
    #|ClassBody -> ( FieldDecl | MethodDecl | ConstructorDecl | TypeDecl | NL )*
    #|FieldDecl -> Annotation* Modifiers? TypeRef id:Ident ( EQ Expr )? SEMI
    #|MethodDecl -> Annotation* Modifiers? GenericParams? TypeRef id:Ident LPAREN ParamList? RPAREN ThrowsClause? ( Block | SEMI )
    #|ConstructorDecl -> Annotation* Modifiers? id:Ident LPAREN ParamList? RPAREN ThrowsClause? Block
    #|ThrowsClause -> KeywordOther TypeRef ( COMMA TypeRef )*
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> Annotation* TypeRef Ident
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> LocalVarDecl | ExprStmt | ControlStmt | Block | NL
    #|LocalVarDecl -> TypeRef Ident ( EQ Expr )? SEMI
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> QualifiedName | Number | String | Char
    #|QualifiedName -> Ident ( DOT Ident )*
    #|TypeRef -> QualifiedName GenericArgs?
    #|GenericArgs -> LT TypeRef ( COMMA TypeRef )* GT
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|STAR -> Operator
    #|LT -> Operator
    #|GT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on PackageDecl: def id=pkg kind=Package ns=type
    #|on ImportDecl: import module=imp
    #|on TypeDecl: def id kind=Class ns=type
    #|on FieldDecl: def id kind=Field ns=value
    #|on MethodDecl: def id kind=Method ns=value
    #|on ConstructorDecl: def id kind=Constructor ns=value
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .java
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  - ext: .java
    #|  - fallback: maven:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "java")
  assert_true(s.tokens.length() >= 15)
  assert_eq(s.resolver.get_module_path_style().as_string(), "dot")
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "maven:")
}

///|
test "parse ruby spec - rubygems/bundler ecosystem" {
  let text =
    #|kgf 0.6
    #|language: ruby
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /#[^\r\n]*/
    #|TOKEN HereDoc /<<[-~]?['"]?[A-Z_]+['"]?/
    #|TOKEN String /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    #|TOKEN Regex /\/([^\/\\]|\\.)*\/[imxo]*/
    #|TOKEN Symbol /:[a-zA-Z_][a-zA-Z0-9_]*|:'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN KeywordDef /\b(def|class|module|end|do|begin|rescue|ensure|raise|return|yield|self|super|alias|undef)\b/
    #|TOKEN KeywordControl /\b(if|elsif|else|unless|case|when|while|until|for|in|break|next|redo|retry|then)\b/
    #|TOKEN KeywordRequire /\b(require|require_relative|load|autoload|include|extend|prepend)\b/
    #|TOKEN KeywordOther /\b(nil|true|false|and|or|not|defined\?|__FILE__|__LINE__|__ENCODING__|__dir__)\b/
    #|TOKEN ConstIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*[?!=]?/
    #|TOKEN InstanceVar /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN ClassVar /@@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN GlobalVar /\$[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=]+|&&|\|\||<<|>>|<=>|=~|!~|\.\.\.?/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}:]/
    #|
    #|=== grammar
    #|Program -> ( Statement | NL )*
    #|Statement -> RequireStmt | ClassDef | ModuleDef | MethodDef | Assignment | ExprStmt
    #|RequireStmt -> KeywordRequire path:String
    #|ClassDef -> KeywordDef id:ConstIdent ( LT ConstIdent )? NL? ClassBody KeywordDef
    #|ModuleDef -> KeywordDef id:ConstIdent NL? ClassBody KeywordDef
    #|ClassBody -> ( MethodDef | Statement | NL )*
    #|MethodDef -> KeywordDef id:Ident LPAREN? ParamList? RPAREN? NL? MethodBody KeywordDef
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> Ident ( EQ Expr )?
    #|MethodBody -> Statement*
    #|Assignment -> ( Ident | InstanceVar | ClassVar | GlobalVar ) EQ Expr
    #|ExprStmt -> Expr NL?
    #|Expr -> MethodCall | Primary
    #|MethodCall -> receiver:Primary? DOT? method:Ident LPAREN? ArgList? RPAREN? Block?
    #|ArgList -> Expr ( COMMA Expr )*
    #|Block -> ( LBRACE | KeywordDef ) Statement* ( RBRACE | KeywordDef )
    #|Primary -> Ident | ConstIdent | InstanceVar | Number | String | Symbol | Regex
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Punct
    #|LT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on RequireStmt: import module=path
    #|on ClassDef: def id kind=Class ns=type
    #|on ModuleDef: def id kind=Module ns=type
    #|on MethodDef: def id kind=Method ns=value
    #|
    #|=== semantics
    #|on RequireStmt {
    #|  edge moduleDependsOn from $file to $resolve($path) attrs obj("via", $path, "dep_kind", "require")
    #|}
    #|
    #|=== resolver
    #|sources: .rb
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|resolve:
    #|  - index: /lib.rb
    #|  - ext: .rb
    #|  - fallback: gem:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "ruby")
  assert_true(s.tokens.length() >= 18)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[2].get_prefix(), "gem:")
}

///|
test "parse php spec - composer/psr-4 ecosystem" {
  let text =
    #|kgf 0.6
    #|language: php
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\*\*[\s\S]*?\*\//
    #|TOKEN PHPOpen /<\?php|\?>/
    #|TOKEN String /"([^"\\$]|\\.|\$[^{])*"|'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
    #|TOKEN Variable /\$[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordNamespace /\b(namespace|use|as)\b/
    #|TOKEN KeywordClass /\b(class|interface|trait|enum|extends|implements|abstract|final|static|public|private|protected|readonly|const)\b/
    #|TOKEN KeywordFunction /\b(function|fn|return|yield|match)\b/
    #|TOKEN KeywordControl /\b(if|elseif|else|switch|case|default|for|foreach|while|do|break|continue|throw|try|catch|finally)\b/
    #|TOKEN KeywordOther /\b(new|clone|instanceof|self|parent|static|null|true|false|array|callable|iterable|mixed|void|never|object|bool|int|float|string)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN NamespaceSep /\\/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=.?:]+|&&|\|\||<<|>>|<=>|=>|->|\?\?|\.\.\.|\*\*/
    #|TOKEN Punct /[;,\(\)\[\]\{\}@]/
    #|
    #|=== grammar
    #|File -> PHPOpen? ( NamespaceDecl | UseDecl | ClassDecl | FunctionDecl | Statement | NL )*
    #|NamespaceDecl -> KeywordNamespace ns:QualifiedName SEMI
    #|UseDecl -> KeywordNamespace imp:QualifiedName ( KeywordNamespace alias:Ident )? SEMI
    #|QualifiedName -> NamespaceSep? Ident ( NamespaceSep Ident )*
    #|ClassDecl -> Modifiers? TypeKind id:Ident Inheritance? LBRACE ClassBody RBRACE
    #|Modifiers -> KeywordClass+
    #|TypeKind -> KeywordClass
    #|Inheritance -> KeywordClass QualifiedName ( COMMA QualifiedName )*
    #|ClassBody -> ( PropertyDecl | MethodDecl | ConstDecl | NL )*
    #|PropertyDecl -> Modifiers? Variable ( EQ Expr )? SEMI
    #|ConstDecl -> Modifiers? KeywordClass id:Ident EQ Expr SEMI
    #|MethodDecl -> Modifiers? KeywordFunction id:Ident LPAREN ParamList? RPAREN ReturnType? ( Block | SEMI )
    #|ReturnType -> COLON QualifiedName
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> QualifiedName? Variable ( EQ Expr )?
    #|FunctionDecl -> KeywordFunction id:Ident LPAREN ParamList? RPAREN ReturnType? Block
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> Variable | QualifiedName | Number | String
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|COLON -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on NamespaceDecl: def id=ns kind=Namespace ns=type
    #|on UseDecl: import module=imp
    #|on ClassDecl: def id kind=Class ns=type
    #|on MethodDecl: def id kind=Method ns=value
    #|on FunctionDecl: def id kind=Function ns=value
    #|on PropertyDecl: def id=Variable kind=Property ns=value
    #|
    #|=== semantics
    #|on UseDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "use")
    #|}
    #|
    #|=== resolver
    #|sources: .php
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|ns_prefix: vendor/
    #|ns_segments: 2
    #|resolve:
    #|  - ext: .php
    #|  - fallback: composer:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "php")
  assert_true(s.tokens.length() >= 16)
  // PHP uses namespace prefix for PSR-4 autoloading
  assert_eq(s.resolver.get_ns_segments(), 2)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "composer:")
}

///|
test "parse swift spec - swift package manager ecosystem" {
  let text =
    #|kgf 0.6
    #|language: swift
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\/\/[^\r\n]*/
    #|TOKEN String /"([^"\\]|\\.)*"|#"[^"]*"#|"""[\s\S]*?"""/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN Attribute /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordImport /\b(import)\b/
    #|TOKEN KeywordDecl /\b(let|var|func|class|struct|enum|protocol|extension|typealias|associatedtype|init|deinit|subscript|operator|precedencegroup)\b/
    #|TOKEN KeywordMod /\b(public|private|internal|fileprivate|open|final|static|lazy|weak|unowned|mutating|nonmutating|override|required|convenience|dynamic|infix|prefix|postfix)\b/
    #|TOKEN KeywordControl /\b(if|else|guard|switch|case|default|for|in|while|repeat|do|break|continue|fallthrough|return|throw|defer|where|try|catch|async|await)\b/
    #|TOKEN KeywordOther /\b(self|Self|super|nil|true|false|as|is|Any|AnyObject|some|any|Type|Protocol|inout|throws|rethrows|get|set|willSet|didSet|actor|isolated|nonisolated)\b/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?]+|&&|\|\||\.\.\.|\.\.<|->|=>|\?\?/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}:@#]/
    #|
    #|=== grammar
    #|Module -> ( ImportDecl | TopDecl | NL )*
    #|ImportDecl -> KeywordImport imp:ModulePath
    #|ModulePath -> Ident ( DOT Ident )*
    #|TopDecl -> Attribute* Modifiers? ( ClassDecl | StructDecl | EnumDecl | ProtocolDecl | ExtensionDecl | FuncDecl | VarDecl | TypealiasDecl )
    #|Modifiers -> KeywordMod+
    #|ClassDecl -> KeywordDecl id:TypeIdent GenericParams? Inheritance? LBRACE ClassBody RBRACE
    #|StructDecl -> KeywordDecl id:TypeIdent GenericParams? Inheritance? LBRACE ClassBody RBRACE
    #|EnumDecl -> KeywordDecl id:TypeIdent GenericParams? Inheritance? LBRACE EnumBody RBRACE
    #|ProtocolDecl -> KeywordDecl id:TypeIdent Inheritance? LBRACE ProtocolBody RBRACE
    #|ExtensionDecl -> KeywordDecl TypeRef Inheritance? LBRACE ClassBody RBRACE
    #|GenericParams -> LT TypeParam ( COMMA TypeParam )* GT
    #|TypeParam -> TypeIdent ( COLON TypeRef )?
    #|Inheritance -> COLON TypeRef ( COMMA TypeRef )*
    #|ClassBody -> ( VarDecl | FuncDecl | InitDecl | NL )*
    #|EnumBody -> ( CaseDecl | FuncDecl | NL )*
    #|CaseDecl -> KeywordControl id:Ident AssociatedValues?
    #|AssociatedValues -> LPAREN TypeRef ( COMMA TypeRef )* RPAREN
    #|ProtocolBody -> ( FuncSignature | VarSignature | NL )*
    #|FuncSignature -> KeywordDecl id:Ident LPAREN ParamList? RPAREN ReturnType?
    #|VarSignature -> KeywordDecl id:Ident COLON TypeRef AccessorBlock?
    #|AccessorBlock -> LBRACE AccessorDecl+ RBRACE
    #|AccessorDecl -> KeywordOther
    #|FuncDecl -> KeywordDecl id:Ident GenericParams? LPAREN ParamList? RPAREN Throws? ReturnType? WhereClause? Block
    #|Throws -> KeywordOther
    #|ReturnType -> ARROW TypeRef
    #|WhereClause -> KeywordControl Constraint ( COMMA Constraint )*
    #|Constraint -> TypeRef COLON TypeRef
    #|InitDecl -> KeywordDecl LPAREN ParamList? RPAREN Throws? Block
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> ( Ident Ident? | Ident ) COLON TypeRef ( EQ Expr )?
    #|VarDecl -> KeywordDecl id:Ident ( COLON TypeRef )? ( EQ Expr )? AccessorBlock?
    #|TypealiasDecl -> KeywordDecl id:TypeIdent GenericParams? EQ TypeRef
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> VarDecl | ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr NL?
    #|ControlStmt -> KeywordControl
    #|Expr -> Primary ( DOT Ident )*
    #|Primary -> Ident | TypeIdent | Number | String
    #|TypeRef -> TypeIdent GenericArgs? QUESTION? | LBRACKET TypeRef RBRACKET
    #|GenericArgs -> LT TypeRef ( COMMA TypeRef )* GT
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Punct
    #|QUESTION -> Operator
    #|ARROW -> Operator
    #|LT -> Operator
    #|GT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on ImportDecl: import module=imp
    #|on ClassDecl: def id kind=Class ns=type
    #|on StructDecl: def id kind=Struct ns=type
    #|on EnumDecl: def id kind=Enum ns=type
    #|on ProtocolDecl: def id kind=Protocol ns=type
    #|on FuncDecl: def id kind=Function ns=value
    #|on VarDecl: def id kind=Variable ns=value
    #|on TypealiasDecl: def id kind=TypeAlias ns=type
    #|on CaseDecl: def id kind=EnumCase ns=value
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .swift
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: Package.swift
    #|    query: dependencies
    #|  - marker: Package.swift
    #|  - ext: .swift
    #|  - fallback: spm:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "swift")
  assert_true(s.tokens.length() >= 16)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain().length(), 4)
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "Package.swift")
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "spm:")
}

///|
test "parse kotlin spec - gradle/maven ecosystem" {
  let text =
    #|kgf 0.6
    #|language: kotlin
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\*\*[\s\S]*?\*\//
    #|TOKEN String /"([^"\\$]|\\.|\$[^{])*"|"""[\s\S]*?"""/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?[fFLuU]?/
    #|TOKEN Annotation /@[a-zA-Z_][a-zA-Z0-9_.:]*/
    #|TOKEN KeywordPackage /\b(package|import)\b/
    #|TOKEN KeywordDecl /\b(fun|val|var|class|interface|object|enum|sealed|data|value|inline|infix|operator|suspend|tailrec|external|typealias|companion|annotation)\b/
    #|TOKEN KeywordMod /\b(public|private|internal|protected|open|final|abstract|override|lateinit|const|vararg|noinline|crossinline|reified|inner|out|in|actual|expect)\b/
    #|TOKEN KeywordControl /\b(if|else|when|for|while|do|break|continue|return|throw|try|catch|finally|is|as|in|!in|!is|where)\b/
    #|TOKEN KeywordOther /\b(this|super|null|true|false|it|field|by|get|set|init|constructor|dynamic)\b/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*|`[^`]+`/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||\.\.|\?:|->|=>|\?\./
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}@#]/
    #|
    #|=== grammar
    #|File -> PackageDecl? ImportDecl* TopDecl*
    #|PackageDecl -> KeywordPackage pkg:QualifiedName NL?
    #|ImportDecl -> KeywordPackage imp:QualifiedName ( DOT STAR )? NL?
    #|QualifiedName -> Ident ( DOT Ident )*
    #|TopDecl -> Annotation* Modifiers? ( ClassDecl | ObjectDecl | FunDecl | PropertyDecl | TypealiasDecl ) NL?
    #|Modifiers -> ( KeywordMod | KeywordDecl )+
    #|ClassDecl -> KeywordDecl id:TypeIdent GenericParams? PrimaryConstructor? Inheritance? LBRACE ClassBody RBRACE
    #|ObjectDecl -> KeywordDecl id:TypeIdent Inheritance? LBRACE ClassBody RBRACE
    #|PrimaryConstructor -> LPAREN ParamList? RPAREN
    #|GenericParams -> LT TypeParam ( COMMA TypeParam )* GT
    #|TypeParam -> TypeIdent ( COLON TypeRef )?
    #|Inheritance -> COLON DelegationSpecifier ( COMMA DelegationSpecifier )*
    #|DelegationSpecifier -> TypeRef ( LPAREN ArgList? RPAREN )?
    #|ClassBody -> ( PropertyDecl | FunDecl | InitBlock | CompanionObject | NL )*
    #|InitBlock -> KeywordOther Block
    #|CompanionObject -> KeywordDecl KeywordDecl LBRACE ClassBody RBRACE
    #|FunDecl -> KeywordDecl GenericParams? ( TypeRef DOT )? id:Ident LPAREN ParamList? RPAREN ReturnType? WhereClause? ( Block | EQ Expr )?
    #|ReturnType -> COLON TypeRef
    #|WhereClause -> KeywordControl Constraint ( COMMA Constraint )*
    #|Constraint -> TypeIdent COLON TypeRef
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> ( KeywordDecl | KeywordMod )* Ident COLON TypeRef ( EQ Expr )?
    #|PropertyDecl -> ( KeywordDecl | KeywordMod )* id:Ident ( COLON TypeRef )? ( EQ Expr | KeywordOther )? Accessors?
    #|Accessors -> ( Getter Setter? | Setter Getter? )
    #|Getter -> KeywordOther ( LPAREN RPAREN )? ( Block | EQ Expr )?
    #|Setter -> KeywordOther LPAREN Ident RPAREN ( Block | EQ Expr )?
    #|TypealiasDecl -> KeywordDecl id:TypeIdent GenericParams? EQ TypeRef
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> PropertyDecl | ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr NL?
    #|ControlStmt -> KeywordControl
    #|Expr -> Primary ( DOT Ident )*
    #|ArgList -> Expr ( COMMA Expr )*
    #|Primary -> Ident | TypeIdent | Number | String | Char
    #|TypeRef -> TypeIdent GenericArgs? QUESTION?
    #|GenericArgs -> LT TypeRef ( COMMA TypeRef )* GT
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Punct
    #|STAR -> Operator
    #|QUESTION -> Operator
    #|LT -> Operator
    #|GT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on PackageDecl: def id=pkg kind=Package ns=type
    #|on ImportDecl: import module=imp
    #|on ClassDecl: def id kind=Class ns=type
    #|on ObjectDecl: def id kind=Object ns=type
    #|on FunDecl: def id kind=Function ns=value
    #|on PropertyDecl: def id kind=Property ns=value
    #|on TypealiasDecl: def id kind=TypeAlias ns=type
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .kt, .kts
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  - ext: .kt, .kts
    #|  - fallback: maven:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "kotlin")
  assert_true(s.tokens.length() >= 16)
  assert_eq(s.resolver.get_module_path_style().as_string(), "dot")
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "maven:")
}

///|
test "parse dart spec - pub ecosystem" {
  let text =
    #|kgf 0.6
    #|language: dart
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN DocComment /\/\/\/[^\r\n]*/
    #|TOKEN String /'([^'\\]|\\.)*'|"([^"\\]|\\.)*"|'''[\s\S]*?'''|"""[\s\S]*?"""|r'[^']*'|r"[^"]*"/
    #|TOKEN Number /0x[0-9a-fA-F]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
    #|TOKEN Annotation /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordImport /\b(import|export|part|part of|library|show|hide|as|deferred)\b/
    #|TOKEN KeywordDecl /\b(class|mixin|extension|enum|typedef|abstract|sealed|base|interface|final|const|var|late|required|covariant|static|external|factory)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|case|default|for|in|while|do|break|continue|return|throw|rethrow|try|on|catch|finally|assert|yield|async|await|sync)\b/
    #|TOKEN KeywordOther /\b(this|super|null|true|false|new|is|as|get|set|operator|extends|implements|with|dynamic|void|Function|Never|Object)\b/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=?:]+|&&|\|\||\.\.\.?|\?\?|=>|->|\?\.|\?\[/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}@#]/
    #|
    #|=== grammar
    #|Library -> LibraryDecl? ImportDecl* TopDecl*
    #|LibraryDecl -> KeywordImport QualifiedName SEMI
    #|ImportDecl -> KeywordImport uri:String ( KeywordImport id:Ident )? Combinators? SEMI
    #|Combinators -> ( ShowClause | HideClause )+
    #|ShowClause -> KeywordImport IdentList
    #|HideClause -> KeywordImport IdentList
    #|IdentList -> Ident ( COMMA Ident )*
    #|QualifiedName -> Ident ( DOT Ident )*
    #|TopDecl -> Annotation* Modifiers? ( ClassDecl | MixinDecl | EnumDecl | ExtensionDecl | FunctionDecl | VarDecl | TypedefDecl ) NL?
    #|Modifiers -> KeywordDecl+
    #|ClassDecl -> KeywordDecl id:TypeIdent GenericParams? SuperClause? Interfaces? MixinClause? LBRACE ClassBody RBRACE
    #|MixinDecl -> KeywordDecl id:TypeIdent GenericParams? Interfaces? LBRACE ClassBody RBRACE
    #|EnumDecl -> KeywordDecl id:TypeIdent Interfaces? LBRACE EnumBody RBRACE
    #|ExtensionDecl -> KeywordDecl id:TypeIdent? KeywordOther TypeRef LBRACE ClassBody RBRACE
    #|GenericParams -> LT TypeParam ( COMMA TypeParam )* GT
    #|TypeParam -> TypeIdent ( KeywordOther TypeRef )?
    #|SuperClause -> KeywordOther TypeRef
    #|Interfaces -> KeywordOther TypeRef ( COMMA TypeRef )*
    #|MixinClause -> KeywordOther TypeRef ( COMMA TypeRef )*
    #|ClassBody -> ( FieldDecl | MethodDecl | ConstructorDecl | NL )*
    #|EnumBody -> EnumValue ( COMMA EnumValue )* SEMI? ClassBody?
    #|EnumValue -> Annotation* id:Ident Arguments?
    #|FieldDecl -> Modifiers? TypeRef? id:Ident ( EQ Expr )? SEMI
    #|MethodDecl -> Modifiers? TypeRef? KeywordOther? id:Ident GenericParams? LPAREN ParamList? RPAREN ( Block | ARROW Expr SEMI | SEMI )
    #|ConstructorDecl -> Modifiers? id:TypeIdent ( DOT Ident )? LPAREN ParamList? RPAREN Initializers? ( Block | SEMI )
    #|Initializers -> COLON Initializer ( COMMA Initializer )*
    #|Initializer -> ( KeywordOther | Ident ) Arguments?
    #|Arguments -> LPAREN ArgList? RPAREN
    #|ArgList -> Arg ( COMMA Arg )*
    #|Arg -> ( Ident COLON )? Expr
    #|FunctionDecl -> TypeRef? id:Ident GenericParams? LPAREN ParamList? RPAREN ( Block | ARROW Expr SEMI )
    #|VarDecl -> Modifiers? TypeRef? id:Ident ( EQ Expr )? SEMI
    #|TypedefDecl -> KeywordDecl id:TypeIdent GenericParams? EQ TypeRef SEMI
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> Modifiers? TypeRef? Ident ( EQ Expr )?
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> VarDecl | ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr SEMI
    #|ControlStmt -> KeywordControl
    #|Expr -> Primary ( DOT Ident )*
    #|Primary -> Ident | TypeIdent | Number | String
    #|TypeRef -> TypeIdent GenericArgs? QUESTION?
    #|GenericArgs -> LT TypeRef ( COMMA TypeRef )* GT
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Punct
    #|QUESTION -> Operator
    #|ARROW -> Operator
    #|LT -> Operator
    #|GT -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on ImportDecl: import module=uri
    #|on ClassDecl: def id kind=Class ns=type
    #|on MixinDecl: def id kind=Mixin ns=type
    #|on EnumDecl: def id kind=Enum ns=type
    #|on ExtensionDecl: def id kind=Extension ns=type
    #|on MethodDecl: def id kind=Method ns=value
    #|on FunctionDecl: def id kind=Function ns=value
    #|on FieldDecl: def id kind=Field ns=value
    #|on VarDecl: def id kind=Variable ns=value
    #|on TypedefDecl: def id kind=TypeAlias ns=type
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($uri) attrs obj("via", $uri, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .dart
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: pubspec.yaml
    #|    query: dependencies
    #|  - ext: .dart
    #|  - fallback: pub:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "dart")
  assert_true(s.tokens.length() >= 14)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "pubspec.yaml")
  assert_eq(s.resolver.get_resolve_chain()[2].get_prefix(), "pub:")
}

///|
test "parse scala spec - sbt/maven ecosystem" {
  let text =
    #|kgf 0.6
    #|language: scala
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN BlockComment /\/\*[\s\S]*?\*\//
    #|TOKEN String /"([^"\\]|\\.)*"|"""[\s\S]*?"""|s"([^"\\$]|\\.|\$[^{])*"|f"([^"\\$]|\\.|\$[^{])*"|raw"[^"]*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Symbol /'[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?[fFdDlL]?/
    #|TOKEN Annotation /@[a-zA-Z_][a-zA-Z0-9_.]*/
    #|TOKEN KeywordPackage /\b(package|import)\b/
    #|TOKEN KeywordDecl /\b(def|val|var|lazy|type|class|trait|object|enum|given|using|extension|case|sealed|abstract|final|private|protected|override|implicit|inline|transparent|opaque|erased)\b/
    #|TOKEN KeywordControl /\b(if|else|then|match|while|for|do|return|throw|try|catch|finally|yield|with|extends|derives|end|new)\b/
    #|TOKEN KeywordOther /\b(this|super|null|true|false|Nil)\b/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=:?@#]+|=>|<-|->|<:|>:|=>>|::/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}]/
    #|
    #|=== grammar
    #|CompilationUnit -> PackageClause? ImportDecl* TopDef*
    #|PackageClause -> KeywordPackage pkg:QualifiedName NL?
    #|ImportDecl -> KeywordPackage imp:ImportExpr ( COMMA ImportExpr )* NL?
    #|ImportExpr -> QualifiedName ( DOT LBRACE ImportSelectors RBRACE | DOT STAR )?
    #|ImportSelectors -> ImportSelector ( COMMA ImportSelector )*
    #|ImportSelector -> Ident ( ARROW ( Ident | UNDERSCORE ) )?
    #|QualifiedName -> Ident ( DOT Ident )*
    #|TopDef -> Annotation* Modifiers? ( ClassDef | ObjectDef | TraitDef | EnumDef | GivenDef | ExtensionDef | TypeDef | ValDef | DefDef )
    #|Modifiers -> KeywordDecl+
    #|ClassDef -> KeywordDecl id:TypeIdent TypeParams? ClassParamClauses? Inheritance? TemplateBody?
    #|ObjectDef -> KeywordDecl id:TypeIdent Inheritance? TemplateBody?
    #|TraitDef -> KeywordDecl id:TypeIdent TypeParams? Inheritance? TemplateBody?
    #|EnumDef -> KeywordDecl id:TypeIdent TypeParams? Inheritance? LBRACE EnumCases RBRACE
    #|GivenDef -> KeywordDecl ( id:Ident COLON )? TypeRef ( KeywordControl TypeRef )? ( EQ Expr | TemplateBody )
    #|ExtensionDef -> KeywordDecl TypeParams? LPAREN ParamClause RPAREN DefDef+
    #|TypeParams -> LBRACKET TypeParam ( COMMA TypeParam )* RBRACKET
    #|TypeParam -> ( PLUS | MINUS )? TypeIdent TypeBounds?
    #|TypeBounds -> ( LT COLON TypeRef )? ( GT COLON TypeRef )?
    #|ClassParamClauses -> LPAREN ParamClause? RPAREN+
    #|ParamClause -> ClassParam ( COMMA ClassParam )*
    #|ClassParam -> Modifiers? Ident COLON TypeRef ( EQ Expr )?
    #|Inheritance -> KeywordControl TypeRef ( KeywordControl TypeRef )*
    #|TemplateBody -> LBRACE TemplateStat* RBRACE
    #|TemplateStat -> Import | Def | NL
    #|EnumCases -> ( EnumCase NL? )+
    #|EnumCase -> KeywordDecl id:TypeIdent ClassParamClauses? Inheritance?
    #|TypeDef -> KeywordDecl id:TypeIdent TypeParams? ( EQ TypeRef | TypeBounds )
    #|ValDef -> KeywordDecl id:Ident ( COLON TypeRef )? EQ Expr
    #|DefDef -> KeywordDecl id:Ident TypeParams? ParamClauses? ( COLON TypeRef )? ( EQ Expr | Block )?
    #|ParamClauses -> LPAREN Params? RPAREN+
    #|Params -> Param ( COMMA Param )*
    #|Param -> Modifiers? Ident COLON TypeRef ( EQ Expr )?
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> ValDef | DefDef | ExprStmt | NL
    #|ExprStmt -> Expr NL?
    #|Expr -> Primary ( DOT Ident )*
    #|Primary -> Ident | TypeIdent | Number | String | Char | Symbol
    #|TypeRef -> TypeIdent TypeArgs? | LPAREN TypeRef ( COMMA TypeRef )* RPAREN | TypeRef ARROW TypeRef
    #|TypeArgs -> LBRACKET TypeRef ( COMMA TypeRef )* RBRACKET
    #|Import -> KeywordPackage ImportExpr ( COMMA ImportExpr )*
    #|Def -> ValDef | DefDef | TypeDef | ClassDef | ObjectDef | TraitDef
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Operator
    #|STAR -> Operator
    #|UNDERSCORE -> Ident
    #|PLUS -> Operator
    #|MINUS -> Operator
    #|LT -> Operator
    #|GT -> Operator
    #|ARROW -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on PackageClause: def id=pkg kind=Package ns=type
    #|on ImportDecl: import module=imp
    #|on ClassDef: def id kind=Class ns=type
    #|on ObjectDef: def id kind=Object ns=type
    #|on TraitDef: def id kind=Trait ns=type
    #|on EnumDef: def id kind=Enum ns=type
    #|on DefDef: def id kind=Method ns=value
    #|on ValDef: def id kind=Value ns=value
    #|on TypeDef: def id kind=TypeAlias ns=type
    #|on EnumCase: def id kind=EnumCase ns=type
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .scala, .sc
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  - ext: .scala, .sc
    #|  - fallback: maven:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "scala")
  assert_true(s.tokens.length() >= 15)
  assert_eq(s.resolver.get_module_path_style().as_string(), "dot")
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[1].get_prefix(), "maven:")
}

///|
test "parse elixir spec - mix/hex ecosystem" {
  let text =
    #|kgf 0.6
    #|language: elixir
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /#[^\r\n]*/
    #|TOKEN DocString /@(doc|moduledoc|typedoc)\s+(~[sSwwcCaA])?"""[\s\S]*?"""|@(doc|moduledoc|typedoc)\s+false/
    #|TOKEN String /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'|~[sSwwcCaA]?"""[\s\S]*?"""|~[sSwwcCaA]?"([^"\\]|\\.)*"|~[sSwwcCaA]?'([^'\\]|\\.)*'/
    #|TOKEN Atom /:[a-zA-Z_][a-zA-Z0-9_@]*|:"([^"\\]|\\.)*"/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN ModuleAttr /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordDef /\b(defmodule|defprotocol|defimpl|defstruct|defexception|defmacro|defmacrop|defguard|defguardp|def|defp|defdelegate|defoverridable)\b/
    #|TOKEN KeywordControl /\b(if|unless|case|cond|with|for|try|receive|after|rescue|catch|else|raise|throw|reraise|end|do|fn)\b/
    #|TOKEN KeywordOther /\b(require|import|alias|use|quote|unquote|unquote_splicing|super|nil|true|false|and|or|not|in|when)\b/
    #|TOKEN ModuleIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_]*[?!]?/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=]+|&&|\|\||<>|<-|->|=>|\|>|\\\\|\+\+|--|\.\.\.?|::|\^\^/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}@#]/
    #|
    #|=== grammar
    #|File -> ( ModuleDecl | TopExpr | NL )*
    #|ModuleDecl -> KeywordDef mod:ModuleAlias KeywordControl ModuleBody KeywordControl
    #|ModuleAlias -> ModuleIdent ( DOT ModuleIdent )*
    #|ModuleBody -> ( UseDecl | ImportDecl | AliasDecl | RequireDecl | ModuleAttrDecl | FunctionDecl | MacroDecl | NL )*
    #|UseDecl -> KeywordOther mod:ModuleAlias Options?
    #|ImportDecl -> KeywordOther mod:ModuleAlias Options?
    #|AliasDecl -> KeywordOther mod:ModuleAlias Options?
    #|RequireDecl -> KeywordOther mod:ModuleAlias
    #|Options -> COMMA Keyword
    #|Keyword -> Atom COLON Expr
    #|ModuleAttrDecl -> ModuleAttr Expr
    #|FunctionDecl -> KeywordDef id:Ident LPAREN ParamList? RPAREN Guards? FunctionBody
    #|MacroDecl -> KeywordDef id:Ident LPAREN ParamList? RPAREN Guards? FunctionBody
    #|Guards -> KeywordOther Expr
    #|FunctionBody -> COMMA KeywordControl COLON Expr | KeywordControl Block KeywordControl
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> ( Ident | Pattern ) ( BACKSLASH Expr )?
    #|Pattern -> Atom | Ident | LBRACE PatternList? RBRACE | LBRACKET PatternList? RBRACKET
    #|PatternList -> Pattern ( COMMA Pattern )*
    #|Block -> ( Statement | NL )*
    #|Statement -> Expr NL?
    #|TopExpr -> Expr NL?
    #|Expr -> Primary ( DOT Ident )*
    #|Primary -> ModuleAlias | Ident | Atom | Number | String | LBRACKET Expr* RBRACKET | LBRACE Expr* RBRACE
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|COMMA -> Punct
    #|DOT -> Punct
    #|COLON -> Operator
    #|BACKSLASH -> Operator
    #|
    #|=== attrs
    #|on ModuleDecl: def id=mod kind=Module ns=type
    #|on UseDecl: import module=mod
    #|on ImportDecl: import module=mod
    #|on AliasDecl: import module=mod
    #|on RequireDecl: import module=mod
    #|on FunctionDecl: def id kind=Function ns=value
    #|on MacroDecl: def id kind=Macro ns=value
    #|
    #|=== semantics
    #|on UseDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "use")
    #|}
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "import")
    #|}
    #|on RequireDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "require")
    #|}
    #|
    #|=== resolver
    #|sources: .ex, .exs
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: mix.exs
    #|    query: deps
    #|  - marker: mix.exs
    #|  - ext: .ex, .exs
    #|  - fallback: hex:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "elixir")
  assert_true(s.tokens.length() >= 14)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "mix.exs")
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "hex:")
}

///|
test "parse haskell spec - cabal/stack ecosystem" {
  let text =
    #|kgf 0.6
    #|language: haskell
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /--[^\r\n]*/
    #|TOKEN BlockComment /\{-[\s\S]*?-\}/
    #|TOKEN Pragma /\{-#[\s\S]*?#-\}/
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F]+|0o[0-7]+|0b[01]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
    #|TOKEN KeywordModule /\b(module|import|qualified|as|hiding)\b/
    #|TOKEN KeywordDecl /\b(data|newtype|type|class|instance|deriving|where|let|in|do|case|of|if|then|else|default|foreign)\b/
    #|TOKEN KeywordOther /\b(infixl|infixr|infix)\b/
    #|TOKEN ConIdent /[A-Z][a-zA-Z0-9_']*/
    #|TOKEN VarIdent /[a-z_][a-zA-Z0-9_']*/
    #|TOKEN Operator /[!#$%&*+.\/<=>?@\\^|\-~:]+/
    #|TOKEN Punct /[;,\(\)\[\]\{\}`]/
    #|
    #|=== grammar
    #|Module -> ModuleDecl? ImportDecl* TopDecl*
    #|ModuleDecl -> KeywordModule mod:ModuleName ExportList? KeywordDecl
    #|ModuleName -> ConIdent ( DOT ConIdent )*
    #|ExportList -> LPAREN ExportItem ( COMMA ExportItem )* RPAREN
    #|ExportItem -> VarIdent | ConIdent ExportSub?
    #|ExportSub -> LPAREN ( DOT DOT | VarIdent ( COMMA VarIdent )* )? RPAREN
    #|ImportDecl -> KeywordModule Qualified? imp:ModuleName AsClause? HidingClause? NL?
    #|Qualified -> KeywordModule
    #|AsClause -> KeywordModule ConIdent
    #|HidingClause -> KeywordModule? LPAREN ImportItem ( COMMA ImportItem )* RPAREN
    #|ImportItem -> VarIdent | ConIdent ExportSub?
    #|TopDecl -> DataDecl | TypeDecl | ClassDecl | InstanceDecl | FunDecl | TypeSig | NL
    #|DataDecl -> KeywordDecl id:ConIdent TypeParams? EQ Constructors Deriving?
    #|TypeDecl -> KeywordDecl id:ConIdent TypeParams? EQ TypeExpr
    #|ClassDecl -> KeywordDecl Context? id:ConIdent TypeParams KeywordDecl ClassBody
    #|InstanceDecl -> KeywordDecl Context? ConIdent TypeExprs KeywordDecl ClassBody
    #|Context -> LPAREN Constraint ( COMMA Constraint )* RPAREN ARROW | Constraint ARROW
    #|Constraint -> ConIdent TypeExprs
    #|TypeParams -> VarIdent+
    #|Constructors -> Constructor ( PIPE Constructor )*
    #|Constructor -> id:ConIdent TypeExprs?
    #|Deriving -> KeywordDecl DerivingClause
    #|DerivingClause -> ConIdent | LPAREN ConIdent ( COMMA ConIdent )* RPAREN
    #|ClassBody -> FunDecl*
    #|FunDecl -> id:VarIdent Patterns? EQ Expr ( KeywordDecl LocalDecls )? NL?
    #|TypeSig -> VarIdent COLON COLON TypeExpr NL?
    #|Patterns -> Pattern+
    #|Pattern -> VarIdent | ConIdent | LPAREN Pattern RPAREN | Literal
    #|LocalDecls -> ( FunDecl | TypeSig )+
    #|TypeExpr -> TypeAtom ( ARROW TypeExpr )?
    #|TypeAtom -> ConIdent | VarIdent | LPAREN TypeExpr ( COMMA TypeExpr )* RPAREN | LBRACKET TypeExpr RBRACKET
    #|TypeExprs -> TypeAtom+
    #|Expr -> ExprAtom+
    #|ExprAtom -> VarIdent | ConIdent | Literal | LPAREN Expr RPAREN | LBRACKET Expr ( COMMA Expr )* RBRACKET
    #|Literal -> Number | String | Char
    #|DOT -> Punct
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|COMMA -> Punct
    #|PIPE -> Operator
    #|ARROW -> Operator
    #|EQ -> Operator
    #|COLON -> Operator
    #|
    #|=== attrs
    #|on ModuleDecl: def id=mod kind=Module ns=type
    #|on ImportDecl: import module=imp
    #|on DataDecl: def id kind=DataType ns=type
    #|on TypeDecl: def id kind=TypeAlias ns=type
    #|on ClassDecl: def id kind=TypeClass ns=type
    #|on FunDecl: def id kind=Function ns=value
    #|on Constructor: def id kind=Constructor ns=value
    #|
    #|=== semantics
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .hs, .lhs
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: package.yaml
    #|    query: dependencies
    #|  - marker: package.yaml, .cabal
    #|  - ext: .hs, .lhs
    #|  - fallback: hackage:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "haskell")
  assert_true(s.tokens.length() >= 14)
  assert_eq(s.resolver.get_module_path_style().as_string(), "dot")
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "hackage:")
}

///|
test "parse ocaml spec - opam/dune ecosystem" {
  let text =
    #|kgf 0.6
    #|language: ocaml
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /\(\*[\s\S]*?\*\)/
    #|TOKEN DocComment /\(\*\*[\s\S]*?\*\)/
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN KeywordModule /\b(open|include|module|struct|sig|end|functor)\b/
    #|TOKEN KeywordDecl /\b(let|rec|and|in|type|val|external|exception|class|object|method|inherit|initializer|constraint|virtual|private|mutable)\b/
    #|TOKEN KeywordControl /\b(if|then|else|match|with|when|function|fun|try|begin|as|of|for|to|downto|while|do|done|assert|lazy)\b/
    #|TOKEN KeywordOther /\b(true|false|new|ref|or|mod|land|lor|lxor|lsl|lsr|asr|not)\b/
    #|TOKEN ModuleIdent /[A-Z][a-zA-Z0-9_']*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_']*/
    #|TOKEN Operator /[!$%&*+\-.\/:<=>?@^|~]+|->|<-|;;|::|:=|\|>/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}'`#]/
    #|
    #|=== grammar
    #|Module -> ( OpenDecl | IncludeDecl | ModuleDecl | TypeDecl | LetDecl | ExternalDecl | ExceptionDecl | NL )*
    #|OpenDecl -> KeywordModule mod:ModulePath
    #|IncludeDecl -> KeywordModule mod:ModulePath
    #|ModulePath -> ModuleIdent ( DOT ModuleIdent )*
    #|ModuleDecl -> KeywordModule id:ModuleIdent ModuleParams? ModuleType? EQ ModuleExpr
    #|ModuleParams -> LPAREN ModuleParam RPAREN*
    #|ModuleParam -> ModuleIdent COLON ModuleType
    #|ModuleType -> KeywordModule | ModulePath
    #|ModuleExpr -> KeywordModule ModuleBody KeywordModule | ModulePath | KeywordModule ModuleExpr ModuleExpr
    #|ModuleBody -> ( TypeDecl | LetDecl | ModuleDecl | OpenDecl | NL )*
    #|TypeDecl -> KeywordDecl TypeParams? id:Ident TypeInfo?
    #|TypeParams -> QUOTE Ident | LPAREN QUOTE Ident ( COMMA QUOTE Ident )* RPAREN
    #|TypeInfo -> EQ TypeExpr | EQ TypeVariants | EQ LBRACE RecordFields RBRACE
    #|TypeVariants -> PIPE? TypeVariant ( PIPE TypeVariant )*
    #|TypeVariant -> id:ModuleIdent ( KeywordControl TypeExpr )?
    #|RecordFields -> RecordField ( SEMI RecordField )* SEMI?
    #|RecordField -> KeywordDecl? id:Ident COLON TypeExpr
    #|LetDecl -> KeywordDecl KeywordDecl? id:Ident Params? TypeAnnot? EQ Expr
    #|Params -> Param+
    #|Param -> Ident | LPAREN Ident COLON TypeExpr RPAREN | TILDE Ident | QUESTION Ident
    #|TypeAnnot -> COLON TypeExpr
    #|ExternalDecl -> KeywordDecl id:Ident COLON TypeExpr EQ String+
    #|ExceptionDecl -> KeywordDecl id:ModuleIdent ( KeywordControl TypeExpr )?
    #|TypeExpr -> TypeAtom ( ARROW TypeExpr )?
    #|TypeAtom -> Ident | ModulePath DOT Ident | LPAREN TypeExpr ( COMMA TypeExpr )* RPAREN | TypeExpr Ident
    #|Expr -> ExprAtom+
    #|ExprAtom -> Ident | ModuleIdent | Number | String | Char | LPAREN Expr RPAREN | LBRACKET Expr ( SEMI Expr )* RBRACKET
    #|DOT -> Punct
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|QUOTE -> Punct
    #|TILDE -> Operator
    #|QUESTION -> Operator
    #|PIPE -> Operator
    #|ARROW -> Operator
    #|EQ -> Operator
    #|COLON -> Operator
    #|
    #|=== attrs
    #|on OpenDecl: import module=mod
    #|on IncludeDecl: import module=mod
    #|on ModuleDecl: def id kind=Module ns=type
    #|on TypeDecl: def id kind=Type ns=type
    #|on LetDecl: def id kind=Value ns=value
    #|on ExternalDecl: def id kind=External ns=value
    #|on ExceptionDecl: def id kind=Exception ns=type
    #|on TypeVariant: def id kind=Constructor ns=value
    #|on RecordField: def id kind=Field ns=value
    #|
    #|=== semantics
    #|on OpenDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "open")
    #|}
    #|on IncludeDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "include")
    #|}
    #|
    #|=== resolver
    #|sources: .ml, .mli
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  - marker: dune, dune-project
    #|  - ext: .ml, .mli
    #|  - fallback: opam:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "ocaml")
  assert_true(s.tokens.length() >= 14)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[2].get_prefix(), "opam:")
}

///|
test "parse zig spec - zig package manager ecosystem" {
  let text =
    #|kgf 0.6
    #|language: zig
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /\/\/[^\r\n]*/
    #|TOKEN DocComment /\/\/\/[^\r\n]*/
    #|TOKEN String /"([^"\\]|\\.)*"|\\\\[^\r\n]*/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?/
    #|TOKEN Builtin /@[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN KeywordDecl /\b(const|var|fn|pub|extern|export|inline|noinline|threadlocal|comptime|test|usingnamespace|struct|enum|union|opaque|error)\b/
    #|TOKEN KeywordControl /\b(if|else|switch|while|for|break|continue|return|unreachable|defer|errdefer|catch|try|orelse|and|or)\b/
    #|TOKEN KeywordType /\b(void|bool|noreturn|type|anyerror|anytype|anyframe|anyopaque|null|undefined|true|false)\b/
    #|TOKEN PrimitiveType /\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f16|f32|f64|f80|f128|c_short|c_ushort|c_int|c_uint|c_long|c_ulong|c_longlong|c_ulonglong|c_longdouble|comptime_int|comptime_float)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=]+|\+\+|--|\.\.\.|\.\.|\.?\*|=>|->|\+%|-%-|-%|\*%|<<%|>>%/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}:?@]/
    #|
    #|=== grammar
    #|Root -> ContainerDecl*
    #|ContainerDecl -> ( PubDecl | PrivateDecl | TestDecl | UsingDecl | NL )*
    #|PubDecl -> KeywordDecl ( FnDecl | VarDecl | StructDecl | EnumDecl | UnionDecl )
    #|PrivateDecl -> FnDecl | VarDecl | StructDecl | EnumDecl | UnionDecl
    #|UsingDecl -> KeywordDecl imp:Builtin LPAREN String RPAREN SEMI?
    #|FnDecl -> KeywordDecl id:Ident LPAREN ParamList? RPAREN TypeExpr? Block
    #|VarDecl -> ( KeywordDecl | KeywordDecl ) id:Ident ( COLON TypeExpr )? ( EQ Expr )? SEMI?
    #|StructDecl -> KeywordDecl id:Ident? LBRACE StructBody RBRACE
    #|EnumDecl -> KeywordDecl ( LPAREN TypeExpr RPAREN )? LBRACE EnumBody RBRACE
    #|UnionDecl -> KeywordDecl ( LPAREN TypeExpr RPAREN )? LBRACE UnionBody RBRACE
    #|TestDecl -> KeywordDecl String Block
    #|StructBody -> ( FieldDecl | FnDecl | NL )*
    #|FieldDecl -> id:Ident COLON TypeExpr ( EQ Expr )? COMMA?
    #|EnumBody -> ( EnumField | FnDecl | NL )*
    #|EnumField -> id:Ident ( EQ Expr )? COMMA?
    #|UnionBody -> ( UnionField | FnDecl | NL )*
    #|UnionField -> id:Ident COLON TypeExpr COMMA?
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> Ident COLON TypeExpr
    #|TypeExpr -> PrimitiveType | KeywordType | Ident | STAR TypeExpr | LBRACKET Expr? RBRACKET TypeExpr | QUESTION TypeExpr
    #|Block -> LBRACE Statement* RBRACE
    #|Statement -> VarDecl | ExprStmt | ControlStmt | NL
    #|ExprStmt -> Expr SEMI?
    #|ControlStmt -> KeywordControl
    #|Expr -> Primary ( DOT Ident )* ( LPAREN ArgList? RPAREN )?
    #|ArgList -> Expr ( COMMA Expr )*
    #|Primary -> Ident | Number | String | Char | Builtin | LPAREN Expr RPAREN
    #|DOT -> Punct
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|SEMI -> Punct
    #|COMMA -> Punct
    #|COLON -> Punct
    #|STAR -> Operator
    #|QUESTION -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on UsingDecl: import module=imp
    #|on FnDecl: def id kind=Function ns=value
    #|on VarDecl: def id kind=Variable ns=value
    #|on StructDecl: def id kind=Struct ns=type
    #|on EnumDecl: def kind=Enum ns=type
    #|on UnionDecl: def kind=Union ns=type
    #|on FieldDecl: def id kind=Field ns=value
    #|on EnumField: def id kind=EnumValue ns=value
    #|on UnionField: def id kind=Field ns=value
    #|on TestDecl: def kind=Test
    #|
    #|=== semantics
    #|on UsingDecl {
    #|  edge moduleDependsOn from $file to $resolve($imp) attrs obj("via", $imp, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .zig
    #|relative_prefixes: ./
    #|module_path_style: slash
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: build.zig.zon
    #|    query: dependencies
    #|  - marker: build.zig.zon, build.zig
    #|  - ext: .zig
    #|  - fallback: zig:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "zig")
  assert_true(s.tokens.length() >= 14)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "build.zig.zon")
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "zig:")
}

///|
test "parse julia spec - pkg ecosystem" {
  let text =
    #|kgf 0.6
    #|language: julia
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /#[^\r\n]*/
    #|TOKEN BlockComment /#=[\s\S]*?=#/
    #|TOKEN DocString /"""[\s\S]*?"""/
    #|TOKEN String /"([^"\\]|\\.)*"|"""[\s\S]*?"""|`[^`]*`|raw"[^"]*"/
    #|TOKEN Char /'([^'\\]|\\.)*'/
    #|TOKEN Symbol /:[a-zA-Z_][a-zA-Z0-9_!]*/
    #|TOKEN Number /0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]+)?([eE][+-]?[0-9_]+)?([imf][0-9]+)?/
    #|TOKEN KeywordModule /\b(module|baremodule|using|import|export|as)\b/
    #|TOKEN KeywordDecl /\b(function|macro|struct|mutable|abstract|primitive|type|const|local|global|let|begin|quote|do|end)\b/
    #|TOKEN KeywordControl /\b(if|elseif|else|for|in|while|break|continue|return|try|catch|finally|throw|where)\b/
    #|TOKEN KeywordOther /\b(true|false|nothing|missing|Inf|NaN|new|isa|typeof)\b/
    #|TOKEN TypeIdent /[A-Z][a-zA-Z0-9_]*/
    #|TOKEN Ident /[a-z_][a-zA-Z0-9_!]*/
    #|TOKEN Operator /[+\-*\/%&|^~!<>=:]+|\.\.\.?|=>|->|<:|>:|::|&&|\|\||\/\/|\\\\/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}@$]/
    #|
    #|=== grammar
    #|Module -> ModuleDecl? ( UsingDecl | ImportDecl | ExportDecl | TopDecl | NL )*
    #|ModuleDecl -> KeywordModule id:TypeIdent NL?
    #|UsingDecl -> KeywordModule mod:ModulePath ( COLON ImportList )? NL?
    #|ImportDecl -> KeywordModule mod:ModulePath ( COLON ImportList )? NL?
    #|ExportDecl -> KeywordModule Ident ( COMMA Ident )* NL?
    #|ModulePath -> ( DOT+ )? TypeIdent ( DOT TypeIdent )*
    #|ImportList -> Ident ( COMMA Ident )*
    #|TopDecl -> FunctionDecl | MacroDecl | StructDecl | AbstractDecl | ConstDecl | NL
    #|FunctionDecl -> KeywordDecl id:Ident TypeParams? LPAREN ParamList? RPAREN WhereClause? ( NL FunctionBody KeywordDecl | EQ Expr )
    #|MacroDecl -> KeywordDecl id:Ident LPAREN ParamList? RPAREN NL MacroBody KeywordDecl
    #|StructDecl -> KeywordDecl? KeywordDecl id:TypeIdent TypeParams? Supertype? NL StructBody KeywordDecl
    #|AbstractDecl -> KeywordDecl KeywordDecl id:TypeIdent TypeParams? Supertype?
    #|TypeParams -> LBRACE TypeParam ( COMMA TypeParam )* RBRACE
    #|TypeParam -> TypeIdent ( LT COLON TypeExpr )?
    #|Supertype -> LT COLON TypeExpr
    #|WhereClause -> KeywordControl LBRACE Constraint ( COMMA Constraint )* RBRACE
    #|Constraint -> TypeIdent LT COLON TypeExpr
    #|StructBody -> ( FieldDecl | NL )*
    #|FieldDecl -> id:Ident ( COLON COLON TypeExpr )?
    #|ConstDecl -> KeywordDecl id:Ident EQ Expr
    #|FunctionBody -> Statement*
    #|MacroBody -> Statement*
    #|ParamList -> Param ( COMMA Param )*
    #|Param -> Ident ( COLON COLON TypeExpr )? ( EQ Expr )?
    #|TypeExpr -> TypeIdent TypeArgs? | TypeExpr PIPE TypeExpr
    #|TypeArgs -> LBRACE TypeExpr ( COMMA TypeExpr )* RBRACE
    #|Statement -> Expr NL? | ControlStmt NL? | LocalDecl
    #|LocalDecl -> KeywordDecl Ident EQ Expr
    #|ControlStmt -> KeywordControl
    #|Expr -> Primary ( DOT Ident )* ( LPAREN ArgList? RPAREN )?
    #|ArgList -> Expr ( COMMA Expr )*
    #|Primary -> Ident | TypeIdent | Number | String | Char | Symbol | LPAREN Expr RPAREN
    #|DOT -> Punct
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|COMMA -> Punct
    #|COLON -> Operator
    #|LT -> Operator
    #|PIPE -> Operator
    #|EQ -> Operator
    #|
    #|=== attrs
    #|on ModuleDecl: def id kind=Module ns=type
    #|on UsingDecl: import module=mod
    #|on ImportDecl: import module=mod
    #|on FunctionDecl: def id kind=Function ns=value
    #|on MacroDecl: def id kind=Macro ns=value
    #|on StructDecl: def id kind=Struct ns=type
    #|on AbstractDecl: def id kind=AbstractType ns=type
    #|on ConstDecl: def id kind=Constant ns=value
    #|on FieldDecl: def id kind=Field ns=value
    #|
    #|=== semantics
    #|on UsingDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "using")
    #|}
    #|on ImportDecl {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .jl
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: Project.toml
    #|    query: deps
    #|  - marker: Project.toml
    #|  - ext: .jl
    #|  - fallback: pkg:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "julia")
  assert_true(s.tokens.length() >= 15)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "Project.toml")
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "pkg:")
}

///|
test "parse lua spec - luarocks ecosystem" {
  let text =
    #|kgf 0.6
    #|language: lua
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN LineComment /--[^\r\n]*/
    #|TOKEN BlockComment /--\[\[[\s\S]*?\]\]/
    #|TOKEN String /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'|\[\[[\s\S]*?\]\]|\[=\[[\s\S]*?\]=\]/
    #|TOKEN Number /0x[0-9a-fA-F]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
    #|TOKEN KeywordDecl /\b(function|local|end|return)\b/
    #|TOKEN KeywordControl /\b(if|then|elseif|else|for|in|while|do|repeat|until|break|goto)\b/
    #|TOKEN KeywordOther /\b(nil|true|false|and|or|not)\b/
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|TOKEN Operator /[+\-*\/%^#<>=~]+|\.\.\.?|==|~=|<=|>=|<<|>>|\/\/|&|\||~/
    #|TOKEN Punct /[;,\.\(\)\[\]\{\}:]/
    #|
    #|=== grammar
    #|Chunk -> ( Statement | NL )*
    #|Statement -> LocalDecl | FunctionDecl | Assignment | FunctionCall | ControlStmt | ReturnStmt | RequireStmt
    #|RequireStmt -> id:Ident EQ KeywordOther LPAREN mod:String RPAREN
    #|            |  KeywordDecl id:Ident EQ KeywordOther LPAREN mod:String RPAREN
    #|LocalDecl -> KeywordDecl id:Ident ( COMMA Ident )* ( EQ ExprList )?
    #|FunctionDecl -> KeywordDecl? KeywordDecl id:FunctionName LPAREN ParamList? RPAREN FunctionBody KeywordDecl
    #|FunctionName -> Ident ( DOT Ident )* ( COLON Ident )?
    #|ParamList -> Ident ( COMMA Ident )* ( COMMA DOTDOTDOT )? | DOTDOTDOT
    #|FunctionBody -> ( Statement | NL )*
    #|Assignment -> VarList EQ ExprList
    #|VarList -> Var ( COMMA Var )*
    #|Var -> Ident | PrefixExpr LBRACKET Expr RBRACKET | PrefixExpr DOT Ident
    #|ExprList -> Expr ( COMMA Expr )*
    #|FunctionCall -> PrefixExpr Args | PrefixExpr COLON Ident Args
    #|Args -> LPAREN ExprList? RPAREN | TableConstructor | String
    #|ControlStmt -> IfStmt | WhileStmt | ForStmt | RepeatStmt
    #|IfStmt -> KeywordControl Expr KeywordControl ( Statement | NL )* ElseIfPart* ElsePart? KeywordDecl
    #|ElseIfPart -> KeywordControl Expr KeywordControl ( Statement | NL )*
    #|ElsePart -> KeywordControl ( Statement | NL )*
    #|WhileStmt -> KeywordControl Expr KeywordControl ( Statement | NL )* KeywordDecl
    #|ForStmt -> KeywordControl Ident EQ Expr COMMA Expr ( COMMA Expr )? KeywordControl ( Statement | NL )* KeywordDecl
    #|        |  KeywordControl Ident ( COMMA Ident )* KeywordControl ExprList KeywordControl ( Statement | NL )* KeywordDecl
    #|RepeatStmt -> KeywordControl ( Statement | NL )* KeywordControl Expr
    #|ReturnStmt -> KeywordDecl ExprList?
    #|PrefixExpr -> Ident | LPAREN Expr RPAREN | PrefixExpr LBRACKET Expr RBRACKET | PrefixExpr DOT Ident | FunctionCall
    #|Expr -> Primary | Expr Operator Expr | KeywordOther Expr
    #|Primary -> KeywordOther | Number | String | DOTDOTDOT | FunctionDef | PrefixExpr | TableConstructor
    #|FunctionDef -> KeywordDecl LPAREN ParamList? RPAREN FunctionBody KeywordDecl
    #|TableConstructor -> LBRACE FieldList? RBRACE
    #|FieldList -> Field ( FieldSep Field )* FieldSep?
    #|Field -> LBRACKET Expr RBRACKET EQ Expr | Ident EQ Expr | Expr
    #|FieldSep -> COMMA | SEMI
    #|DOT -> Punct
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|COMMA -> Punct
    #|COLON -> Punct
    #|SEMI -> Punct
    #|EQ -> Operator
    #|DOTDOTDOT -> Operator
    #|
    #|=== attrs
    #|on RequireStmt: import module=mod ; def id kind=Module ns=value
    #|on FunctionDecl: def id kind=Function ns=value
    #|on LocalDecl: def id kind=Variable ns=value
    #|
    #|=== semantics
    #|on RequireStmt {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "require")
    #|}
    #|
    #|=== resolver
    #|sources: .lua
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  - marker: rockspec
    #|  - ext: .lua
    #|  - index: /init.lua
    #|  - fallback: luarocks:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "lua")
  assert_true(s.tokens.length() >= 11)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "luarocks:")
}

///|
test "parse clojure spec - deps.edn/leiningen ecosystem" {
  let text =
    #|kgf 0.6
    #|language: clojure
    #|
    #|=== lex
    #|SKIP /[ \t,]+/
    #|TOKEN NL /\r?\n+/
    #|TOKEN Comment /;[^\r\n]*/
    #|TOKEN String /"([^"\\]|\\.)*"/
    #|TOKEN Regex /#"([^"\\]|\\.)*"/
    #|TOKEN Number /[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?[MN]?|[+-]?0x[0-9a-fA-F]+|[+-]?0[0-7]+|[+-]?[0-9]+r[0-9a-zA-Z]+|[0-9]+\/[0-9]+/
    #|TOKEN Keyword /:[a-zA-Z_*+!?\-][a-zA-Z0-9_*+!?\-.:]*/
    #|TOKEN Symbol /[a-zA-Z_*+!?\-][a-zA-Z0-9_*+!?\-.]*/
    #|TOKEN NamespacedSymbol /[a-zA-Z_*+!?\-][a-zA-Z0-9_*+!?\-]*\/[a-zA-Z_*+!?\-][a-zA-Z0-9_*+!?\-]*/
    #|TOKEN SpecialForm /\b(def|defn|defmacro|defmethod|defmulti|defprotocol|defrecord|deftype|defstruct|fn|let|loop|recur|if|do|quote|var|throw|try|catch|finally|new|set!|monitor-enter|monitor-exit|\.)\b/
    #|TOKEN CoreMacro /\b(ns|require|use|import|refer|in-ns|create-ns|refer-clojure|load)\b/
    #|TOKEN Punct /[\(\)\[\]\{\}#'^`~@]/
    #|
    #|=== grammar
    #|File -> Form*
    #|Form -> NsForm | DefForm | Expr | NL
    #|NsForm -> LPAREN CoreMacro ns:Symbol NsBody RPAREN
    #|NsBody -> ( RequireForm | UseForm | ImportForm )*
    #|RequireForm -> LPAREN Keyword RequireSpecs RPAREN
    #|UseForm -> LPAREN Keyword UseSpecs RPAREN
    #|ImportForm -> LPAREN Keyword ImportSpecs RPAREN
    #|RequireSpecs -> ( Symbol | RequireSpec )*
    #|RequireSpec -> LBRACKET mod:Symbol RequireOpts RBRACKET
    #|RequireOpts -> ( Keyword ( Symbol | LBRACKET Symbol* RBRACKET ) )*
    #|UseSpecs -> ( Symbol | UseSpec )*
    #|UseSpec -> LBRACKET mod:Symbol UseOpts RBRACKET
    #|UseOpts -> ( Keyword ( Symbol | LBRACKET Symbol* RBRACKET ) )*
    #|ImportSpecs -> ( Symbol | ImportSpec )*
    #|ImportSpec -> LPAREN mod:Symbol Symbol* RPAREN
    #|DefForm -> LPAREN SpecialForm id:Symbol DefBody RPAREN
    #|DefBody -> DocString? Meta? ParamVec? Form*
    #|DocString -> String
    #|Meta -> Punct Map
    #|ParamVec -> LBRACKET Symbol* RBRACKET
    #|Expr -> Literal | Symbol | NamespacedSymbol | List | Vector | Map | Set | Quote | SyntaxQuote | Unquote | Deref | Meta
    #|Literal -> Number | String | Keyword | Regex | Char
    #|Char -> Punct Symbol
    #|List -> LPAREN Form* RPAREN
    #|Vector -> LBRACKET Form* RBRACKET
    #|Map -> LBRACE ( Form Form )* RBRACE
    #|Set -> Punct LBRACE Form* RBRACE
    #|Quote -> Punct Form
    #|SyntaxQuote -> Punct Form
    #|Unquote -> Punct Form
    #|Deref -> Punct Form
    #|LPAREN -> Punct
    #|RPAREN -> Punct
    #|LBRACKET -> Punct
    #|RBRACKET -> Punct
    #|LBRACE -> Punct
    #|RBRACE -> Punct
    #|
    #|=== attrs
    #|on NsForm: def id=ns kind=Namespace ns=type
    #|on RequireSpec: import module=mod
    #|on UseSpec: import module=mod
    #|on ImportSpec: import module=mod
    #|on DefForm: def id kind=Var ns=value
    #|
    #|=== semantics
    #|on RequireSpec {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "require")
    #|}
    #|on UseSpec {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "use")
    #|}
    #|on ImportSpec {
    #|  edge moduleDependsOn from $file to $resolve($mod) attrs obj("via", $mod, "dep_kind", "import")
    #|}
    #|
    #|=== resolver
    #|sources: .clj, .cljs, .cljc, .edn
    #|relative_prefixes: ./
    #|module_path_style: dot
    #|resolve:
    #|  -
    #|    type: manifest
    #|    file: deps.edn
    #|    query: deps
    #|  - marker: deps.edn, project.clj
    #|  - ext: .clj, .cljs, .cljc
    #|  - fallback: clojars:
  let spec = parse_kgf(text)
  assert_true(spec is Some(_))
  let s = spec.unwrap()
  assert_eq(s.language, "clojure")
  assert_true(s.tokens.length() >= 11)
  assert_true(s.resolver.has_resolve_chain())
  assert_eq(s.resolver.get_resolve_chain()[0].get_file(), "deps.edn")
  assert_eq(s.resolver.get_resolve_chain()[3].get_prefix(), "clojars:")
}
