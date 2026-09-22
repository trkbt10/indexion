///|
/// LayoutSpec declares indentation-sensitive layout for a language.
///
/// The KGF lexer is regex-only: a pattern can recognise "a newline followed by
/// whitespace" but cannot compare that whitespace against the previous line's,
/// so it cannot tell nesting depth. A spec that needs depth declares a
/// `LAYOUT` directive in its `=== lex` section; the engine then runs a
/// post-lex pass (`@lexer.apply_layout`) that maintains an indentation stack
/// and injects synthetic INDENT / DEDENT tokens between the lexer's tokens.
/// Grammar rules can then bracket a body as `INDENT ... DEDENT`, which is
/// exact regardless of how deeply it nests.
///
/// The fields name token kinds, never literal syntax — every language-specific
/// string lives in the .kgf spec:
///
/// | Field | Meaning |
/// |-------|---------|
/// | `newline` | the kind(s) whose text is the line break plus the next line's leading whitespace; everything after the line break character(s) is that line's indentation. Several kinds may be listed: a spec that splits indented from column-0 line breaks (Python's `NL_INDENT` / `NL`) lists both, and a column-0 break is simply an indentation of length zero |
/// | `indent` / `dedent` | the synthetic kinds to emit. They must NOT be defined as lex TOKENs (nothing in the source matches them) but are valid grammar symbols |
/// | `comment` | optional: the kind of a comment token. A line whose first token is a comment carries no layout (its indentation is free), matching the layout rules of Python and YAML |
/// | `open` / `close` | bracket kinds. While any of them is open, layout is suppressed entirely: Python and YAML flow collections span lines with arbitrary indentation |
pub struct LayoutSpec {
  newline : Array[String]
  indent : String
  dedent : String
  comment : String?
  open : Array[String]
  close : Array[String]
} derive(Eq, Debug)

///|
/// Creates a LayoutSpec. `open` and `close` are positionally independent: the
/// pass only needs to know which kinds increase and which decrease the bracket
/// depth, not which closer matches which opener (the lexer already guarantees
/// each bracket token is one character of the source).
pub fn LayoutSpec::new(
  newline : Array[String],
  indent : String,
  dedent : String,
  comment? : String? = None,
  open? : Array[String] = [],
  close? : Array[String] = [],
) -> LayoutSpec {
  { newline, indent, dedent, comment, open, close, }
}

///|
/// The token kinds that carry a line break and the following line's
/// indentation.
pub fn LayoutSpec::get_newline(self : LayoutSpec) -> Array[String] {
  self.newline
}

///|
/// The synthetic kind emitted when a line is indented deeper than the one
/// before it.
pub fn LayoutSpec::get_indent(self : LayoutSpec) -> String {
  self.indent
}

///|
/// The synthetic kind emitted when a line is indented less than the one
/// before it (once per closed level).
pub fn LayoutSpec::get_dedent(self : LayoutSpec) -> String {
  self.dedent
}

///|
/// The comment token kind, when the spec declared one. A line that begins with
/// a token of this kind is skipped by the layout pass.
pub fn LayoutSpec::get_comment(self : LayoutSpec) -> String? {
  self.comment
}

///|
/// Token kinds that open a bracket inside which layout is suppressed.
pub fn LayoutSpec::get_open(self : LayoutSpec) -> Array[String] {
  self.open
}

///|
/// Token kinds that close a bracket.
pub fn LayoutSpec::get_close(self : LayoutSpec) -> Array[String] {
  self.close
}

///|
/// The synthetic token kinds this layout introduces — kinds that exist in the
/// token stream and in grammar rules but have no lex TOKEN definition.
///
/// This is the single source of truth for "which kinds are synthetic": spec
/// validation (`kgf check`) consults it both to accept INDENT/DEDENT as
/// grammar symbols and to reject a spec that also defines them as TOKENs.
pub fn LayoutSpec::synthetic_kinds(self : LayoutSpec) -> Array[String] {
  [self.indent, self.dedent]
}

///|
/// The token kinds this layout refers to that the lex section must define:
/// the newline kinds, the optional comment kind, and every bracket kind.
pub fn LayoutSpec::referenced_kinds(self : LayoutSpec) -> Array[String] {
  let kinds : Array[String] = []
  for kind in self.newline {
    kinds.push(kind)
  }
  match self.comment {
    Some(c) => kinds.push(c)
    None => ()
  }
  for kind in self.open {
    kinds.push(kind)
  }
  for kind in self.close {
    kinds.push(kind)
  }
  kinds
}
