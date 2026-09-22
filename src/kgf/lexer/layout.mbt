///|
/// Indentation layout synthesis — the post-lex pass for languages whose
/// nesting is expressed by indentation rather than by brackets.
///
/// # Why a pass and not a token rule
///
/// A KGF lex rule is a regular expression over the source text. A regex can
/// recognise "a line break followed by whitespace", but it cannot compare that
/// whitespace with the previous line's, because that comparison needs memory
/// across matches. So a regex-only lexer cannot tell a sibling from a child:
/// both look like "a line break and some spaces". This pass adds exactly that
/// memory — an indentation stack — and turns the depth it derives into
/// ordinary tokens the PEG grammar can match.
///
/// # What it emits
///
/// Between the newline token that starts a line and the line's first real
/// token, the pass inserts:
///
/// - one `indent` token when the line's indentation is longer than the top of
///   the stack (the new depth is pushed);
/// - one `dedent` token per stack level that the line's indentation closes.
///
/// At end of input every level still open is closed with a `dedent`, so a body
/// that runs to the last line of the file is still bracketed.
///
/// The synthetic tokens are zero-width: their text is empty and their `pos` is
/// the position of the line's first real token. Positions therefore stay
/// monotonic and stay inside the source, which is what `_text` accumulation
/// (`META_TEXT`, built by concatenating the tokens a rule consumed), the
/// source map and every `pos`-based diagnostic rely on. A rule that spans an
/// `INDENT` sees the same text it would have seen without the pass.
///
/// # What it ignores
///
/// - **Blank lines.** A newline token immediately followed by another newline
///   token starts a line with no content; its indentation is meaningless. Also
///   the last newline of the file, which starts no line at all.
/// - **Comment-only lines.** When the layout declares a `comment` kind, a line
///   whose first token is a comment is skipped: it neither opens nor closes a
///   level. Python and YAML both let a comment sit at any column.
/// - **Everything inside brackets.** While a declared `open` bracket is
///   unclosed, no layout token is emitted at all. Python and YAML flow
///   collections (`[1,\n  2]`, `{a: 1,\n b: 2}`) may be laid out freely, and a
///   parameter list routinely indents deeper than the body that follows it.
///
/// # Tabs versus spaces
///
/// Indentation is compared as the raw whitespace string's **length in
/// characters**: one tab counts as one character, the same as one space. This
/// is deliberate and it is the only choice that needs no per-language tab
/// width: it is exact for a file that is indented consistently (all tabs or
/// all spaces, which every modern style guide and formatter enforces), and for
/// a file that mixes them it degrades to a stable, if arbitrary, ordering
/// rather than to a wrong one. Python itself rejects ambiguous mixing with a
/// TabError, so a file whose depth this pass would misread is not a file the
/// language accepts either.
///
/// # Recovery
///
/// A line that dedents to a column that is not on the stack (Python's
/// "unindent does not match any outer indentation level") is not an error
/// here: the pass emits a `dedent` for every level it closes and then adopts
/// the line's column as the current level. `kgf` is an analyser, not a
/// compiler — it must keep extracting declarations from a file that does not
/// compile.

///|
/// Applies a spec's `LAYOUT` declaration to a lexed token stream, returning a
/// new stream with synthetic indent/dedent tokens inserted.
///
/// This is the single implementation of the pass; every tokenization entry
/// point reaches it through `Lexer::tokenize` / `Lexer::tokenize_with_diagnostics`,
/// which carry the layout their spec declared. A spec without a `LAYOUT`
/// directive never calls it.
pub fn apply_layout(
  tokens : Array[@types.Tok],
  layout : @types.LayoutSpec,
) -> Array[@types.Tok] {
  let newline_kinds = kind_set(layout.get_newline())
  let open_kinds = kind_set(layout.get_open())
  let close_kinds = kind_set(layout.get_close())
  let comment_kind = layout.get_comment()
  let indent_kind = layout.get_indent()
  let dedent_kind = layout.get_dedent()
  let result : Array[@types.Tok] = []
  // Indentation widths of the levels currently open, innermost last. The
  // implicit outermost level is column 0 and is never pushed, so an empty
  // stack means "at the outermost level".
  let stack : Array[Int] = []
  let mut bracket_depth = 0
  for i, tok in tokens {
    result.push(tok)
    let kind = tok.get_kind()
    if open_kinds.contains(kind) {
      bracket_depth += 1
      continue
    }
    if close_kinds.contains(kind) {
      // A stray closer (unbalanced source) must not drive the depth negative,
      // which would make every later line look like it is inside a bracket.
      bracket_depth = if bracket_depth > 0 { bracket_depth - 1 } else { 0 }
      continue
    }
    if bracket_depth > 0 || !newline_kinds.contains(kind) {
      continue
    }
    // This token starts a line. Find the line's first real token to decide
    // whether the line carries layout at all.
    let next = if i + 1 < tokens.length() { Some(tokens[i + 1]) } else { None }
    guard next is Some(next_tok) else {
      // Trailing newline: no line follows, so nothing to open or close here.
      // The end-of-input dedents below close whatever is still open.
      continue
    }
    let next_kind = next_tok.get_kind()
    if newline_kinds.contains(next_kind) {
      // Blank (or whitespace-only) line: the next thing is another line break.
      continue
    }
    if comment_kind is Some(c) && next_kind == c {
      // Comment-only line — but only when the comment IS the whole line, i.e.
      // the token after it ends the line. A comment that opens a line with
      // code after it cannot occur (a comment runs to the line end), so this
      // holds for every spec whose comment kind is a line comment; for a block
      // comment kind it correctly keeps `/* c */ code` on the layout path.
      let after = if i + 2 < tokens.length() {
        Some(tokens[i + 2])
      } else {
        None
      }
      let comment_is_whole_line = match after {
        Some(a) => newline_kinds.contains(a.get_kind())
        None => true
      }
      if comment_is_whole_line {
        continue
      }
    }
    let width = indentation_width(tok.get_text())
    let pos = next_tok.get_pos()
    let current = if stack.is_empty() { 0 } else { stack[stack.length() - 1] }
    if width > current {
      stack.push(width)
      result.push(@types.Tok::new(indent_kind, "", pos, value=Some("")))
      continue
    }
    if width == current {
      continue
    }
    // Dedent: close every level the line is shallower than.
    while !stack.is_empty() && stack[stack.length() - 1] > width {
      let _ = stack.pop()
      result.push(@types.Tok::new(dedent_kind, "", pos, value=Some("")))
    }
    // The line may have landed between two levels (an inconsistent dedent).
    // Adopt its column as the current level so the lines that follow it are
    // measured against something, instead of reporting an error and stopping.
    let reopened = if stack.is_empty() { 0 } else { stack[stack.length() - 1] }
    if width > reopened {
      stack.push(width)
      result.push(@types.Tok::new(indent_kind, "", pos, value=Some("")))
    }
  }
  // End of input: close everything still open, at the end of the source.
  let end_pos = match tokens.last() {
    Some(tok) => tok.get_pos() + tok.get_text().length()
    None => 0
  }
  while !stack.is_empty() {
    let _ = stack.pop()
    result.push(@types.Tok::new(dedent_kind, "", end_pos, value=Some("")))
  }
  result
}

///|
/// The indentation a newline token's text carries: everything after the line
/// break characters. A newline token's text is the break (`\n` or `\r\n`)
/// followed by the next line's leading whitespace, so the indentation is the
/// suffix that follows the last break character.
fn indentation_width(text : String) -> Int {
  let chars = text.to_array()
  let mut start = 0
  for i, c in chars {
    if c == '\n' || c == '\r' {
      start = i + 1
    }
  }
  chars.length() - start
}

///|
/// Builds a membership set from a list of token kinds.
fn kind_set(kinds : Array[String]) -> Map[String, Bool] {
  let set : Map[String, Bool] = Map([])
  for kind in kinds {
    set[kind] = true
  }
  set
}
