///|
/// Tests for `kgfs/dsl/kgf.kgf`, the spec that lets indexion index KGF specs
/// themselves.
///
/// The authority for KGF syntax is the hand-written parser in
/// `src/kgf/parser/`, which is line-oriented: it splits a file on `=== name`
/// at line starts and walks each section body one trimmed line at a time.
/// The spec has to model the same shape, and these tests pin the three
/// properties that made the previous version unable to parse a single real
/// spec:
///
/// 1. tokenization — a `/…/` pattern is ONE token, and a version like `0.6`
///    is a Number. A catch-all token used to be declared before `Number` and
///    `Ident`, so every word in every spec lexed as a regex body.
/// 2. completeness — every file under `kgfs/` must lex without errors and
///    parse to the last token. A section body used to be an ordered choice
///    whose first alternative matched the empty string, so no section other
///    than `lex` could ever be entered.
/// 3. extraction — the `declares` edges that make `indexion search` and
///    `indexion grep` over `kgfs/` meaningful.
///
/// `PipelineResult` / `run_pipeline_with_registry` come from
/// `project_wbtest.mbt` in this package; the helpers below only specialize
/// them to the `kgf` spec.

///|
/// Run lex, parse and semantics for one KGF source under the `kgf` spec.
///
/// `parse_ok` alone is not a useful assertion: the start rule produces a
/// result even when it matched a mere prefix and everything after the
/// stopping point was dropped. `PipelineResult::parse_complete` compares
/// consumed against total tokens, and `lex_errors` counts the characters the
/// lexer could not turn into a token at all.
fn selfspec_run(source : String, file_path : String) -> PipelineResult {
  run_pipeline_with_registry(get_fixture_registry(), "kgf", source, file_path)
}

///|
/// The (kind, text) pairs the `kgf` spec's lexer produces for `source`, in
/// order.
///
/// The token type itself is not named: this package imports the lexer but not
/// `@types`, so the tokens are projected to plain pairs at the boundary.
fn selfspec_lex(source : String) -> Array[(String, String)] {
  let registry = get_fixture_registry()
  let out : Array[(String, String)] = []
  let spec = match registry.get_spec("kgf") {
    Some(s) => s
    None => return out
  }
  for token in @lexer.Lexer::new(spec.get_tokens()).tokenize(source) {
    out.push((token.kind, token.text))
  }
  out
}

///|
/// Token kinds the `kgf` spec's lexer produces for `source`, in order.
fn selfspec_token_kinds(source : String) -> Array[String] {
  let kinds : Array[String] = []
  for token in selfspec_lex(source) {
    kinds.push(token.0)
  }
  kinds
}

///|
/// How many tokens of kind `kind` the `kgf` lexer produces for `source`.
fn selfspec_count_kind(source : String, kind : String) -> Int {
  let mut n = 0
  for token in selfspec_lex(source) {
    if token.0 == kind {
      n = n + 1
    }
  }
  n
}

///|
/// The text of the first token of kind `kind`, or "" when there is none.
fn selfspec_first_text(source : String, kind : String) -> String {
  for token in selfspec_lex(source) {
    if token.0 == kind {
      return token.1
    }
  }
  ""
}

///|
/// The `declares` edges of `source` as (name, kind) pairs, in emission order.
fn selfspec_declares(source : String) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for edge in selfspec_run(source, "spec.kgf").edges {
    if !(edge.kind is @graph.Declares) {
      continue
    }
    result.push(
      (
        edge.attrs.get("name").unwrap_or(""),
        edge.attrs.get("kind").unwrap_or(""),
      ),
    )
  }
  result
}

///|
/// True when `pairs` holds a declares edge for `name` with kind `kind`.
fn selfspec_has_declare(
  pairs : Array[(String, String)],
  name : String,
  kind : String,
) -> Bool {
  pairs.iter().any(fn(p) { p.0 == name && p.1 == kind })
}

///|
/// How many of `pairs` have kind `kind`.
fn selfspec_count_declare_kind(
  pairs : Array[(String, String)],
  kind : String,
) -> Int {
  let mut n = 0
  for pair in pairs {
    if pair.1 == kind {
      n = n + 1
    }
  }
  n
}

///|
/// The `pattern` attr of the declares edge that names token `name`, or ""
/// when there is none.
fn selfspec_pattern_of(source : String, name : String) -> String {
  for edge in selfspec_run(source, "spec.kgf").edges {
    if edge.kind is @graph.Declares &&
      edge.attrs.get("kind").unwrap_or("") == "Token" &&
      edge.attrs.get("name").unwrap_or("") == name {
      return edge.attrs.get("pattern").unwrap_or("")
    }
  }
  ""
}

///|
/// Read one real spec under `kgfs/`. Returns "" when missing; the caller
/// asserts on that, since a silently skipped file is how a broken spec keeps
/// passing.
fn selfspec_read_kgf(rel : String) -> String {
  @fs.read_file_to_string(get_kgfs_dir() + rel) catch {
    _ => ""
  }
}

// ---------------------------------------------------------------------------
// 1. Tokenization
// ---------------------------------------------------------------------------

///|
/// A version number must lex as a Number.
///
/// The previous spec declared a catch-all `RegexBody /[^\/ \t\r\n]+/` before
/// both `Number` and `Ident`, and token rules are first-match-wins, so `0.6`
/// on the very first line lexed as a regex body. Every real spec failed with
/// "1:5 expected Number, found RegexBody".
test "kgf selfspec: a version number lexes as Number, not as a regex body" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
  let kinds = selfspec_token_kinds(source)
  assert_eq(kinds[0], "KW_kgf")
  assert_eq(kinds[1], "Number")
  assert_eq(selfspec_first_text(source, "Number"), "0.6")
}

///|
/// A `/…/` pattern is a single Regex token whose escapes are honoured.
///
/// This mirrors `parse_lex.find_closing_slash`: a backslash escapes the next
/// character and the first unescaped `/` closes the pattern. A pattern that
/// contains `\/` must therefore stay whole rather than being cut in three.
test "kgf selfspec: an escaped slash does not end a pattern" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|TOKEN Path /[^\/ \t]+\/[a-z]*/
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
  // One Regex token for the whole pattern, and no stray Slash tokens.
  assert_eq(selfspec_count_kind(source, "Regex"), 1)
  assert_eq(selfspec_count_kind(source, "Slash"), 0)
  let expected =
    #|/[^\/ \t]+\/[a-z]*/
  assert_eq(selfspec_first_text(source, "Regex"), expected)
}

///|
/// Nothing in a spec may be unlexable. Free-form sections hold JSON, globs,
/// box drawing and CJK punctuation, and a spec is only fully parseable when
/// the lexer turns every character into a token.
test "kgf selfspec: free-form punctuation lexes without errors" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== ignore
    #|node_modules/
    #|*.egg-info/
    #|__pycache__/
    #|
    #|=== preprocess
    #|blankLineIfRegex:^\d{1,3}\s*$
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
}

// ---------------------------------------------------------------------------
// 2. Completeness
// ---------------------------------------------------------------------------

///|
/// A spec may begin with a blank line; ten of the specs under `kgfs/` do.
/// The header used to require `kgf` as the very first token and failed with
/// "expected KW_kgf, found NL".
test "kgf selfspec: a leading blank line does not break the header" {
  let source =
    #|
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|TOKEN Ident /[a-z]+/
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
}

///|
/// Every section must be entered, not just the first one.
///
/// `SectionBody` used to be an ordered choice `LexRule* / GrammarRule* / …`.
/// The first alternative matches the empty string, so it always succeeded and
/// no other alternative was ever tried: every section after `lex` was left
/// unparsed and the parse stopped at the second `===`.
test "kgf selfspec: every section is entered, not only the first" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN Ident /[a-z]+/
    #|
    #|=== grammar
    #|Doc -> Ident*
    #|
    #|=== attrs
    #|on Doc: def id kind=Function
    #|
    #|=== features
    #|identifier_kinds: Ident
    #|
    #|=== semantics
    #|on Doc {
    #|  edge declares from $file to $id
    #|}
    #|
    #|=== resolver
    #|module_path_style: slash
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
}

///|
/// A section name that collides with one of this lexer's own keywords must
/// still be recognised. `=== attrs` lexes its name as KW_attrs, not Ident,
/// so a section header that accepted only Ident stopped the parse there.
test "kgf selfspec: a keyword-named section header is recognised" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== attrs
    #|on Doc: def id kind=Function
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
}

///|
/// A language name is free-form text, not an identifier: `go-mod`,
/// `typescript-jsx` and `moon-mod-toml` all contain dashes, and the name may
/// itself be a keyword of this lexer (`language: kgf`).
///
/// The whole name must reach the edge. A label on a repetition holds only the
/// last atom, so the name comes from `$lang_text`; taking `$lang` instead
/// reported `go-mod` as `mod`.
test "kgf selfspec: a dashed or keyword language name parses whole" {
  let dashed =
    #|kgf 0.6
    #|language: go-mod
    #|sources: go.mod
    #|
  assert_true(selfspec_run(dashed, "spec.kgf").parse_complete())
  let dashed_declares = selfspec_declares(dashed)
  assert_true(selfspec_has_declare(dashed_declares, "go-mod", "Language"))
  let keyword =
    #|kgf 0.6
    #|language: kgf
    #|sources: .kgf
    #|
  assert_true(selfspec_run(keyword, "spec.kgf").parse_complete())
  let keyword_declares = selfspec_declares(keyword)
  assert_true(selfspec_has_declare(keyword_declares, "kgf", "Language"))
}

///|
/// A spec need not declare sources at all (`kgfs/toy/reltext.kgf` does not),
/// and may declare an empty list.
test "kgf selfspec: a missing or empty sources line is accepted" {
  let missing =
    #|kgf 0.6
    #|language: reltext
    #|
    #|=== lex
    #|TOKEN Ident /[a-z]+/
    #|
  assert_true(selfspec_run(missing, "spec.kgf").parse_complete())
  let empty =
    #|kgf 0.6
    #|language: reltext
    #|sources:
    #|
  assert_true(selfspec_run(empty, "spec.kgf").parse_complete())
}

///|
/// A grammar rule may continue on following indented lines, and the rule
/// that follows the continuation must still be seen as a new rule rather
/// than being swallowed as more continuation.
test "kgf selfspec: a continued grammar rule ends at the next rule head" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== grammar
    #|Item -> FnDecl
    #|      / StructDecl
    #|      / VarDecl
    #|FnDecl -> KW_fn Ident
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_true(result.parse_complete())
  let declares = selfspec_declares(source)
  assert_true(selfspec_has_declare(declares, "Item", "Rule"))
  assert_true(selfspec_has_declare(declares, "FnDecl", "Rule"))
}

///|
/// A `}` that closes one block and opens the `else` block on the same line is
/// its own structural line, and braces nested inside an `obj(...)` argument
/// or a regex literal must not unbalance the block.
test "kgf selfspec: else blocks and nested braces do not unbalance a block" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== grammar
    #|Chapter -> Ident
    #|
    #|=== semantics
    #|on Chapter when $scope("value", "last") {
    #|  edge next from $scope("value", "last") to $id
    #|} else {
    #|  note counted payload obj("re", "^\d{1,3}$", "n", 1)
    #|}
    #|
  let result = selfspec_run(source, "spec.kgf")
  assert_eq(result.lex_errors, 0)
  assert_true(result.parse_complete())
  let declares = selfspec_declares(source)
  assert_true(selfspec_has_declare(declares, "Chapter", "Semantics"))
}

///|
/// Every real spec under `kgfs/` must reach a complete parse with no lexer
/// errors. These cover the shapes that previously broke: a large programming
/// spec, a spec whose body is mostly free-form, a spec with a resolve chain,
/// a spec with no sources line, and the self-spec itself.
test "kgf selfspec: real specs under kgfs parse completely" {
  for
    rel in [
      "/programming/python.kgf", "/programming/typescript.kgf", "/dsl/kgf.kgf", "/dsl/markdown.kgf",
      "/project/go-mod.kgf", "/toy/reltext.kgf", "/natural/japanese.kgf",
    ] {
    let source = selfspec_read_kgf(rel)
    assert_true(source.length() > 0)
    let result = selfspec_run(source, "kgfs" + rel)
    assert_eq(result.lex_errors, 0)
    assert_true(result.parse_complete())
  }
}

// ---------------------------------------------------------------------------
// 3. Extraction
// ---------------------------------------------------------------------------

///|
/// The structure worth indexing: one declares edge per grammar rule, per
/// token, and per semantics `on` block, so that `indexion search` and
/// `indexion grep` over `kgfs/` can reach a spec through what it defines.
test "kgf selfspec: rules, tokens and semantics blocks become declares edges" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|SKIP /[ \t]+/
    #|TOKEN Ident /[a-z]+/
    #|KEYWORD KW_fn /fn\b/
    #|
    #|=== grammar
    #|Doc -> FnDecl*
    #|FnDecl -> KW_fn id:Ident
    #|
    #|=== attrs
    #|on FnDecl: def id kind=Function
    #|
    #|=== semantics
    #|on FnDecl {
    #|  edge declares from $file to $id
    #|}
    #|
  let declares = selfspec_declares(source)

  // The language names the spec.
  assert_true(selfspec_has_declare(declares, "toy", "Language"))

  // One edge per grammar rule.
  assert_true(selfspec_has_declare(declares, "Doc", "Rule"))
  assert_true(selfspec_has_declare(declares, "FnDecl", "Rule"))

  // One edge per named token, for both TOKEN and KEYWORD. `SKIP` has no name
  // and must not produce one.
  assert_true(selfspec_has_declare(declares, "Ident", "Token"))
  assert_true(selfspec_has_declare(declares, "KW_fn", "Token"))
  assert_eq(selfspec_count_declare_kind(declares, "Token"), 2)

  // One edge per semantics block and per attrs line.
  assert_true(selfspec_has_declare(declares, "FnDecl", "Semantics"))
  assert_true(selfspec_has_declare(declares, "FnDecl", "Attrs"))
}

///|
/// A token's edge carries its pattern, so a search can reach a token through
/// what it matches and not only through its name.
///
/// The pattern is the body WITHOUT its `/` delimiters — the same string
/// `parse_lex` stores in the TokenDef. The Regex token gets this by wrapping
/// its body in the one capture group, since the lexer takes a token's value
/// from the first capture group that participated in the match.
///
/// The second case is the one that matters: a body containing an escaped
/// slash must survive whole. The previous spec could not even represent it,
/// because it lexed a pattern as a run of slash-delimited fragments.
test "kgf selfspec: a token edge carries its pattern without the delimiters" {
  let plain =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
    #|
  assert_eq(selfspec_pattern_of(plain, "Ident"), "[a-zA-Z_][a-zA-Z0-9_]*")
  let escaped =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== lex
    #|TOKEN Path /[^\/ \t]+\/[a-z]*/
    #|
  let expected =
    #|[^\/ \t]+\/[a-z]*
  assert_eq(selfspec_pattern_of(escaped, "Path"), expected)
}

///|
/// A semantics block guarded by `when` must still be recognised as a block.
///
/// The condition runs up to the opening brace, and `LineAtom` includes the
/// brace, so an unguarded repetition swallowed the `{` and the whole
/// `on Rule when cond {` line degraded to an unstructured line — no
/// Semantics edge was emitted for any guarded block.
test "kgf selfspec: a when-guarded semantics block still declares its rule" {
  let source =
    #|kgf 0.6
    #|language: toy
    #|sources: .toy
    #|
    #|=== grammar
    #|MethodDef -> Ident
    #|NestedClass -> Ident
    #|
    #|=== semantics
    #|on MethodDef when $scope("value", "current_class") {
    #|  edge declares from $file to $id
    #|}
    #|on NestedClass {
    #|  edge declares from $file to $id
    #|}
    #|
  let declares = selfspec_declares(source)
  assert_true(selfspec_has_declare(declares, "MethodDef", "Semantics"))
  assert_true(selfspec_has_declare(declares, "NestedClass", "Semantics"))
}

///|
/// The real python spec is the file the original bug report named. It must
/// yield edges for the rules, tokens and semantics blocks it actually
/// contains.
test "kgf selfspec: the python spec yields its own structure" {
  let source = selfspec_read_kgf("/programming/python.kgf")
  assert_true(source.length() > 0)
  let result = selfspec_run(source, "kgfs/programming/python.kgf")
  assert_true(result.parse_complete())
  let declares : Array[(String, String)] = []
  for edge in result.edges {
    if edge.kind is @graph.Declares {
      declares.push(
        (
          edge.attrs.get("name").unwrap_or(""),
          edge.attrs.get("kind").unwrap_or(""),
        ),
      )
    }
  }
  assert_true(selfspec_has_declare(declares, "python", "Language"))
  assert_true(selfspec_has_declare(declares, "FunctionDef", "Rule"))
  assert_true(selfspec_has_declare(declares, "KW_def", "Token"))
  assert_true(selfspec_has_declare(declares, "Docstring", "Token"))
  // A `when`-guarded block near the end of the file: reaching it proves both
  // that the parse ran to the end and that guarded blocks are structural.
  assert_true(selfspec_has_declare(declares, "MethodDef", "Semantics"))
  assert_true(selfspec_has_declare(declares, "FunctionDef", "Attrs"))
}
