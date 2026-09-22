///|
/// # KGF Lex Section Syntax
///
/// The `=== lex` section defines token rules for lexical analysis.
/// Tokens are matched in declaration order; first match wins.
///
/// ## EBNF Grammar
///
/// ```ebnf
/// LexSection   ::= LexRule*
/// LexRule      ::= SkipRule | TokenRule | KeywordRule | LayoutRule
///                | Comment | BlankLine
/// SkipRule     ::= "SKIP" Pattern
/// TokenRule    ::= "TOKEN" TokenName Pattern Flags?
/// KeywordRule  ::= "KEYWORD" TokenName Pattern Flags?
/// LayoutRule   ::= "LAYOUT" LayoutField+
/// LayoutField  ::= LayoutKey "=" KindList
/// LayoutKey    ::= "newline" | "indent" | "dedent" | "comment"
///                | "open" | "close"
/// KindList     ::= TokenName ( "," TokenName )*
/// TokenName    ::= UPPER_IDENT           (* e.g., "Ident", "KW_fn" *)
/// Pattern      ::= "/" RegexBody "/"     (* JavaScript-style regex *)
/// Flags        ::= [gimsuy]+             (* Optional regex flags *)
/// Comment      ::= "#" ANY_CHAR* NL
/// ```
///
/// ## Token Types
///
/// | Type | Syntax | Description |
/// |------|--------|-------------|
/// | Skip | `SKIP /pattern/` | Matched but not emitted (whitespace, comments) |
/// | Token | `TOKEN NAME /pattern/` | Matched and emitted with kind=NAME |
/// | Keyword | `KEYWORD NAME /pattern/` | Emitted with kind=NAME, classified as keyword |
///
/// `KEYWORD` produces the same TokenDef as `TOKEN` but additionally registers
/// the token name in `LexResult.keyword_kinds`, making the classification
/// queryable without relying on naming conventions.
///
/// ## LAYOUT — indentation-sensitive languages
///
/// A regex cannot compare one line's indentation with the previous line's, so
/// a lexer alone cannot tell nesting depth in Python, YAML, Haskell or any
/// other layout-sensitive language. `LAYOUT` declares how the engine should
/// derive depth from the token stream after lexing. A post-lex pass
/// (`@lexer.apply_layout`) then maintains an indentation stack and injects
/// zero-width `indent` / `dedent` tokens, so grammar rules can bracket a body
/// exactly:
///
/// ```kgf
/// === lex
/// TOKEN NL_INDENT /\r?\n[ \t]+/
/// TOKEN NL        /\r?\n/
/// TOKEN Comment   /#[^\r\n]*/
/// TOKEN LPAREN    /\(/
/// ...
/// LAYOUT newline=NL_INDENT,NL indent=INDENT dedent=DEDENT comment=Comment \
///        open=LPAREN,LBRACKET,LBRACE close=RPAREN,RBRACKET,RBRACE
/// ```
///
/// (written on one line; the continuation above is only for this comment).
///
/// | Field | Required | Meaning |
/// |-------|----------|---------|
/// | `newline` | yes | token kind(s) whose text is a line break plus the *next* line's leading whitespace. Everything after the line break character(s) in the token's text is that line's indentation. Several kinds may be listed when a spec splits indented and column-0 line breaks into different tokens |
/// | `indent` | yes | synthetic kind emitted when a line is indented deeper than the enclosing one |
/// | `dedent` | yes | synthetic kind emitted once per level closed when a line is indented less |
/// | `comment` | no | comment token kind. A line whose first token is a comment carries no layout, matching Python and YAML |
/// | `open` / `close` | no | bracket kinds. While a bracket is open, layout is suppressed: flow collections span lines freely |
///
/// The `indent` and `dedent` kinds are *synthetic*: they must NOT have a
/// `TOKEN` definition (nothing in the source text matches them) but they are
/// valid grammar symbols. `kgf check` enforces both halves of that rule.
///
/// ## Pattern Syntax
///
/// Patterns use JavaScript-compatible regular expressions:
/// - Character classes: `[a-z]`, `[^"\\]`, `\s`, `\d`, `\w`
/// - Quantifiers: `*`, `+`, `?`, `{n,m}`
/// - Groups: `(...)`, `(?:...)`, `(?=...)`, `(?!...)`
/// - Escapes: `\/` for literal slash, `\\` for backslash
///
/// ## Examples
///
/// ```kgf
/// === lex
/// # Skip whitespace and comments
/// SKIP /(\s+|\/\/[^\n]*|\/\*[\s\S]*?\*\/)+/
///
/// # Keywords (order matters - check before identifiers)
/// KEYWORD KW_fn     /fn\b/
/// KEYWORD KW_let    /let\b/
///
/// # Identifiers and literals
/// TOKEN Ident     /[a-zA-Z_][a-zA-Z0-9_]*/
/// TOKEN Number    /[0-9]+(\.[0-9]+)?/
/// TOKEN String    /"([^"\\]|\\.)*"/
///
/// # Operators (longer patterns first)
/// TOKEN ARROW     /->/
/// TOKEN EQ        /=/
/// ```

///|
/// Result of parsing a lex section.
/// Contains the token definitions and the set of token names declared as keywords.
pub struct LexResult {
  tokens : Array[@types.TokenDef]
  keyword_kinds : Map[String, Bool]
  layout : @types.LayoutSpec?
}

///|
pub fn LexResult::get_tokens(self : LexResult) -> Array[@types.TokenDef] {
  self.tokens
}

///|
pub fn LexResult::get_keyword_kinds(self : LexResult) -> Map[String, Bool] {
  self.keyword_kinds
}

///|
/// The `LAYOUT` directive of this lex section, when it declares one.
pub fn LexResult::get_layout(self : LexResult) -> @types.LayoutSpec? {
  self.layout
}

///|
/// Parses the lex section into token definitions and keyword classification.
///
/// Syntax:
///   SKIP /pattern/
///   TOKEN NAME /pattern/[flags]
///   KEYWORD NAME /pattern/[flags]
///   LAYOUT newline=NL indent=INDENT dedent=DEDENT [comment=C] [open=..] [close=..]
pub fn parse_lex(text : String) -> LexResult {
  let lines = split_lines(text)
  let tokens : Array[@types.TokenDef] = []
  let keyword_kinds : Map[String, Bool] = Map([])
  let mut layout : @types.LayoutSpec? = None
  for line in lines {
    let ln = trim_str(line)
    // Skip empty lines and comments
    if ln.length() == 0 || ln.has_prefix("#") {
      continue
    }
    // Parse the LAYOUT directive. A section declaring it more than once keeps
    // the last one, the same way a repeated TOKEN name lets the later rule
    // shadow the earlier one.
    if ln.has_prefix(LAYOUT_KEYWORD) {
      match parse_layout_rule(ln) {
        Some(spec) => layout = Some(spec)
        None => ()
      }
      continue
    }
    // Parse SKIP rules
    if ln.has_prefix("SKIP") {
      match parse_skip_rule(ln) {
        Some(tok) => tokens.push(tok)
        None => ()
      }
      continue
    }
    // Parse KEYWORD rules (same as TOKEN but registered as keyword)
    if ln.has_prefix("KEYWORD") {
      match parse_named_token_rule(ln, 7) {
        Some(tok) => {
          keyword_kinds[tok.get_name()] = true
          tokens.push(tok)
        }
        None => ()
      }
      continue
    }
    // Parse TOKEN rules
    if ln.has_prefix("TOKEN") {
      match parse_named_token_rule(ln, 5) {
        Some(tok) => tokens.push(tok)
        None => ()
      }
    }
  }
  { tokens, keyword_kinds, layout, }
}

///|
/// The directive keyword that introduces an indentation layout declaration.
const LAYOUT_KEYWORD : String = "LAYOUT"

///|
/// Field names of the `LAYOUT` directive. They are the wire format of the
/// directive, so they live here beside the parser that reads them.
const LAYOUT_FIELD_NEWLINE : String = "newline"

///|
const LAYOUT_FIELD_INDENT : String = "indent"

///|
const LAYOUT_FIELD_DEDENT : String = "dedent"

///|
const LAYOUT_FIELD_COMMENT : String = "comment"

///|
const LAYOUT_FIELD_OPEN : String = "open"

///|
const LAYOUT_FIELD_CLOSE : String = "close"

///|
/// Parses a LAYOUT directive:
///   LAYOUT newline=NL_INDENT indent=INDENT dedent=DEDENT comment=Comment
///          open=LPAREN,LBRACKET close=RPAREN,RBRACKET
///
/// Fields may appear in any order; `newline`, `indent` and `dedent` are
/// required and a directive missing any of them is ignored (the spec is then
/// tokenized without layout, and `kgf check` reports the incomplete
/// directive). Unknown field names are ignored so a future field does not
/// make an older engine reject the whole directive.
fn parse_layout_rule(line : String) -> @types.LayoutSpec? {
  let fields : Map[String, Array[String]] = Map([])
  for
    part in split_by_space(trim_str(substr_from(line, LAYOUT_KEYWORD.length()))) {
    let eq = find_char(part, 0, '=')
    if eq <= 0 {
      continue
    }
    let key = substr(part, 0, eq)
    // `parse_comma_list` is the section parsers' shared comma splitter: it
    // trims each item and drops the empty ones, which is what a trailing or
    // doubled comma in a field value should mean.
    fields[key] = parse_comma_list(substr_from(part, eq + 1))
  }
  let newline = fields.get(LAYOUT_FIELD_NEWLINE).unwrap_or([])
  let indent = single_field(fields, LAYOUT_FIELD_INDENT)
  let dedent = single_field(fields, LAYOUT_FIELD_DEDENT)
  guard newline.length() > 0 else { return None }
  guard indent is Some(indent_kind) else { return None }
  guard dedent is Some(dedent_kind) else { return None }
  Some(
    @types.LayoutSpec::new(
      newline,
      indent_kind,
      dedent_kind,
      comment=single_field(fields, LAYOUT_FIELD_COMMENT),
      open=fields.get(LAYOUT_FIELD_OPEN).unwrap_or([]),
      close=fields.get(LAYOUT_FIELD_CLOSE).unwrap_or([]),
    ),
  )
}

///|
/// The first value of a LAYOUT field, or None when the field is absent or
/// empty.
fn single_field(fields : Map[String, Array[String]], key : String) -> String? {
  match fields.get(key) {
    Some(values) => if values.length() > 0 { Some(values[0]) } else { None }
    None => None
  }
}

///|
/// Parses a SKIP rule: SKIP /pattern/
fn parse_skip_rule(line : String) -> @types.TokenDef? {
  // Find first slash
  let first_slash = find_char(line, 0, '/')
  guard first_slash >= 0 else { return None }
  // Find matching closing slash
  let pattern_start = first_slash + 1
  let pattern_end = find_closing_slash(line, pattern_start)
  guard pattern_end > pattern_start else { return None }
  let pattern = substr(line, pattern_start, pattern_end)
  Some(@types.TokenDef::new("SKIP", pattern, skip=true))
}

///|
/// Parses a named token rule (TOKEN or KEYWORD): PREFIX NAME /pattern/[flags] [skip_value]
/// `prefix_len` is the length of the leading keyword ("TOKEN" = 5, "KEYWORD" = 7).
fn parse_named_token_rule(line : String, prefix_len : Int) -> @types.TokenDef? {
  // Skip prefix + whitespace
  let after_token = skip_whitespace(line, prefix_len)
  // Read token name
  let (name, after_name) = read_identifier(line, after_token)
  guard name.length() > 0 else { return None }
  // Skip whitespace to find pattern
  let pattern_pos = skip_whitespace(line, after_name)
  guard pattern_pos < line.length() && char_at(line, pattern_pos) == '/' else {
    return None
  }
  // Find pattern and flags
  let pattern_start = pattern_pos + 1
  let pattern_end = find_closing_slash(line, pattern_start)
  guard pattern_end > pattern_start else { return None }
  let pattern = substr(line, pattern_start, pattern_end)
  // Parse remainder: flags, skip_value
  let remainder = trim_str(substr_from(line, pattern_end + 1))
  let (flags, skip_value) = parse_token_attrs(remainder)
  Some(@types.TokenDef::new(name, pattern, flags~, skip_value~))
}

///|
/// Parses token attributes after the pattern: flags, skip_value, category.
///
fn parse_token_attrs(text : String) -> (String?, Bool) {
  let mut flags : String? = None
  let mut skip_value = false
  let parts = split_by_space(text)
  for part in parts {
    if part == "skip_value" {
      skip_value = true
    } else if part.length() > 0 && is_valid_flags(part) {
      flags = Some(part)
    }
  }
  (flags, skip_value)
}

///|
/// Finds the closing slash, handling escaped characters.
fn find_closing_slash(text : String, start : Int) -> Int {
  let arr = text.to_array()
  let mut i = start
  while i < arr.length() {
    let c = arr[i]
    if c == '\\' && i + 1 < arr.length() {
      // Skip escaped character
      i += 2
    } else if c == '/' {
      return i
    } else {
      i += 1
    }
  }
  -1
}

///|
/// Skips whitespace characters.
fn skip_whitespace(text : String, start : Int) -> Int {
  let arr = text.to_array()
  let mut i = start
  while i < arr.length() && is_whitespace(arr[i]) {
    i += 1
  }
  i
}

///|
/// Reads an identifier from the text.
fn read_identifier(text : String, start : Int) -> (String, Int) {
  let arr = text.to_array()
  if start >= arr.length() || !is_ident_start(arr[start]) {
    return ("", start)
  }
  let mut end = start + 1
  while end < arr.length() && is_ident_char(arr[end]) {
    end += 1
  }
  (substr(text, start, end), end)
}

///|
/// Checks if a string contains only valid regex flags.
fn is_valid_flags(s : String) -> Bool {
  for c in s {
    if !(c == 'g' || c == 'i' || c == 'm' || c == 's' || c == 'u' || c == 'y') {
      return false
    }
  }
  true
}
