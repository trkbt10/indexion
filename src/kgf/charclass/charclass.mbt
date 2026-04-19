///|
/// Character classification used by the KGF lexer, the PEG expression
/// tokenizer, the .kgf file parser, the spec checker and the semantics
/// evaluator. Consolidating these predicates here avoids four near-identical
/// copies drifting apart over time (each copy used slightly different
/// boundary rules before, e.g. whether `'_'` counts as `is_ident_start`).

///|
/// `true` for ASCII space, tab, carriage return, and line feed.
pub fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// `true` for ASCII digits `0`..`9`.
pub fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// `true` for ASCII letters and `_` — the first character of an identifier.
pub fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// `true` for identifier-continuation characters: ident-start plus digits.
pub fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || is_digit(c)
}

///|
/// `true` for ASCII hex digits `0`..`9`, `a`..`f`, `A`..`F`.
pub fn is_hex_char(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}
