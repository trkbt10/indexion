///|
/// Tests for the indentation layout pass (layout.mbt).
///
/// Every test builds a miniature layout-sensitive language — a newline token
/// that carries the next line's indentation, a comment, brackets and one word
/// token — and asserts on the kinds the lexer produces once the pass has run.
/// The spec fields are named after the KGF `LAYOUT` directive fields.

///|
/// A lexer for the toy layout language, with the layout declaration attached
/// exactly as `Lexer::for_spec` would attach a spec's.
fn layout_lexer() -> Lexer {
  Lexer::new(
    [
      // NL_INDENT must precede NL: the first matching rule wins, and a bare
      // NL would otherwise take the line break and leave the indentation to
      // the whitespace SKIP.
      @types.TokenDef::new("NL_INDENT", "\\r?\\n[ \\t]+"),
      @types.TokenDef::new("NL", "\\r?\\n"),
      @types.TokenDef::new("SKIP", "[ \\t]+", skip=true),
      @types.TokenDef::new("Comment", "#[^\\r\\n]*"),
      @types.TokenDef::new("LPAREN", "\\("),
      @types.TokenDef::new("RPAREN", "\\)"),
      @types.TokenDef::new("COMMA", ","),
      @types.TokenDef::new("COLON", ":"),
      @types.TokenDef::new("Word", "[A-Za-z_][A-Za-z0-9_]*"),
    ],
    layout=Some(
      @types.LayoutSpec::new(
        ["NL_INDENT", "NL"],
        "INDENT",
        "DEDENT",
        comment=Some("Comment"),
        open=["LPAREN"],
        close=["RPAREN"],
      ),
    ),
  )
}

///|
/// The kinds of a token stream, for compact assertions.
fn kinds_of(tokens : Array[@types.Tok]) -> Array[String] {
  let out : Array[String] = []
  for tok in tokens {
    out.push(tok.get_kind())
  }
  out
}

///|
test "layout: a deeper line opens a level and end of input closes it" {
  let tokens = layout_lexer().tokenize("a:\n  b\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: a shallower line closes exactly the levels it leaves" {
  // Three levels open, then a line back at column 2 closes the two innermost.
  let tokens = layout_lexer().tokenize("a:\n  b:\n    c:\n      d\n  e\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", // a: -> level 2
     "Word", "COLON", "NL_INDENT", "INDENT", // b: -> level 4
     "Word", "COLON", "NL_INDENT", "INDENT", // c: -> level 6
     "Word", "NL_INDENT", "DEDENT", "DEDENT", // d, back to level 2
     "Word", "NL", "DEDENT", // e, then end of input
  ])
}

///|
test "layout: a body that runs to the last line is still closed" {
  // Two levels open at end of input; both DEDENTs are emitted, in order.
  let tokens = layout_lexer().tokenize("a:\n  b:\n    c\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "COLON", "NL_INDENT", "INDENT",
    "Word", "NL", "DEDENT", "DEDENT",
  ])
}

///|
test "layout: input without a trailing newline is closed too" {
  let tokens = layout_lexer().tokenize("a:\n  b")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "DEDENT",
  ])
}

///|
test "layout: blank and whitespace-only lines carry no layout" {
  // Both in-between lines are a newline token followed directly by another
  // newline token: the empty line lexes as NL and the whitespace-only line as
  // NL_INDENT carrying its own spaces. Neither may open or close a level —
  // note in particular that the whitespace-only line's three spaces do not
  // make it a deeper level than the body's two.
  let tokens = layout_lexer().tokenize("a:\n  b\n\n   \n  c\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL", "NL_INDENT", "NL_INDENT",
    "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: a comment-only line carries no layout at any column" {
  // The comment sits deeper than the body and then shallower than it; neither
  // position may open or close a level, so the body keeps its one INDENT.
  let tokens = layout_lexer().tokenize("a:\n  b\n      # deep\n# flush\n  c\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL_INDENT", "Comment", "NL",
    "Comment", "NL_INDENT", "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: a line that starts with a comment but continues is laid out" {
  // The comment kind here is a line comment, so this cannot arise in the toy
  // language; the pass still only skips a line whose comment IS the whole
  // line, which is what keeps a block-comment-prefixed line significant.
  let tokens = layout_lexer().tokenize("a:\n  # c\n  b\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "Comment", "NL_INDENT", "INDENT", "Word", "NL",
    "DEDENT",
  ])
}

///|
test "layout: nothing is emitted inside brackets" {
  // A call whose arguments span lines at varying indentation must not open a
  // level, and the body that follows the closing bracket is measured from the
  // enclosing level as if the bracket had been one line.
  let tokens = layout_lexer().tokenize("f(\n    a,\n  b\n):\n  c\n")
  assert_eq(kinds_of(tokens), [
    "Word", "LPAREN", "NL_INDENT", "Word", "COMMA", "NL_INDENT", "Word", "NL", "RPAREN",
    "COLON", "NL_INDENT", "INDENT", "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: an unbalanced closing bracket does not suppress later layout" {
  // A stray `)` must not drive the bracket depth negative — every later line
  // would then look as if it were inside a bracket.
  let tokens = layout_lexer().tokenize(")\na:\n  b\n")
  assert_eq(kinds_of(tokens), [
    "RPAREN", "NL", "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: a dedent to a column between two levels is tolerated" {
  // Column 3 is on no open level (2 and 6 are). The pass closes what it can
  // and adopts 3 as the current level instead of reporting an error, so the
  // lines after it are still measured against something.
  let tokens = layout_lexer().tokenize("a:\n  b:\n      c\n   d\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", // level 2
     "Word", "COLON", "NL_INDENT", "INDENT", // level 6
     "Word", "NL_INDENT", "DEDENT", "INDENT", // close 6, reopen at 3
     "Word", "NL", "DEDENT", "DEDENT", // end of input closes 3 and 2
  ])
}

///|
test "layout: a tab counts as one character, like a space" {
  // The body is indented with one tab; the line after it with two spaces.
  // Compared by length, two spaces are deeper than one tab, so the second
  // line opens a further level. This is the documented rule, and it is exact
  // for the consistently-indented files real code consists of.
  let tokens = layout_lexer().tokenize("a:\n\tb\n  c\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL_INDENT", "INDENT", "Word",
    "NL", "DEDENT", "DEDENT",
  ])
}

///|
test "layout: a tab-indented body is closed like a space-indented one" {
  let tokens = layout_lexer().tokenize("a:\n\tb:\n\t\tc\n\td\n")
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "COLON", "NL_INDENT", "INDENT",
    "Word", "NL_INDENT", "DEDENT", "Word", "NL", "DEDENT",
  ])
}

///|
test "layout: synthetic tokens are zero-width and keep positions monotonic" {
  let source = "a:\n  b\n"
  let tokens = layout_lexer().tokenize(source)
  let mut previous = 0
  for tok in tokens {
    assert_true(tok.get_pos() >= previous)
    assert_true(tok.get_pos() <= source.length())
    previous = tok.get_pos()
  }
  // The INDENT sits at the position of the line's first real token, so the
  // text a rule accumulates across it is unchanged.
  let indent = tokens[3]
  assert_eq(indent.get_kind(), "INDENT")
  assert_eq(indent.get_text(), "")
  assert_eq(indent.get_pos(), tokens[4].get_pos())
}

///|
test "layout: a lexer without a layout declaration is unaffected" {
  let plain = Lexer::new([
    @types.TokenDef::new("NL_INDENT", "\\r?\\n[ \\t]+"),
    @types.TokenDef::new("NL", "\\r?\\n"),
    @types.TokenDef::new("SKIP", "[ \\t]+", skip=true),
    @types.TokenDef::new("Word", "[A-Za-z_][A-Za-z0-9_]*"),
  ])
  assert_eq(plain.get_layout(), None)
  assert_eq(kinds_of(plain.tokenize("a\n  b\n")), [
    "Word", "NL_INDENT", "Word", "NL",
  ])
}

///|
test "layout: the diagnostic path applies the pass too" {
  // `kgf check` tokenizes through tokenize_with_diagnostics; it must see the
  // same stream the pipeline does, or it would report parse errors the
  // pipeline never hits.
  let (tokens, diagnostics) = layout_lexer().tokenize_with_diagnostics(
    "a:\n  b\n",
  )
  assert_eq(diagnostics.length(), 0)
  assert_eq(kinds_of(tokens), [
    "Word", "COLON", "NL_INDENT", "INDENT", "Word", "NL", "DEDENT",
  ])
}
