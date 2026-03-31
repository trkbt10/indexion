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
/// LexRule      ::= SkipRule | TokenRule | Comment | BlankLine
/// SkipRule     ::= "SKIP" Pattern
/// TokenRule    ::= "TOKEN" TokenName Pattern Flags?
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
/// TOKEN KW_fn     /fn\b/
/// TOKEN KW_let    /let\b/
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
/// Parses the lex section into token definitions with optional SKIP rules.
///
/// Syntax:
///   SKIP /pattern/
///   TOKEN NAME /pattern/[flags]
pub fn parse_lex(text : String) -> Array[@types.TokenDef] {
  let lines = split_lines(text)
  let result : Array[@types.TokenDef] = []
  for line in lines {
    let ln = trim_str(line)
    // Skip empty lines and comments
    if ln.length() == 0 || starts_with(ln, "#") {
      continue
    }
    // Parse SKIP rules
    if starts_with(ln, "SKIP") {
      match parse_skip_rule(ln) {
        Some(tok) => result.push(tok)
        None => ()
      }
      continue
    }
    // Parse TOKEN rules
    if starts_with(ln, "TOKEN") {
      match parse_token_rule(ln) {
        Some(tok) => result.push(tok)
        None => ()
      }
    }
  }
  result
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
/// Parses a TOKEN rule: TOKEN NAME /pattern/[flags] [skip_value]
fn parse_token_rule(line : String) -> @types.TokenDef? {
  // Skip "TOKEN " prefix
  let after_token = skip_whitespace(line, 6)
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
/// Parses token attributes after the pattern: flags, skip_value
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
  if start >= arr.length() || not(is_ident_start(arr[start])) {
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
    if not(c == 'g' || c == 'i' || c == 'm' || c == 's' || c == 'u' || c == 'y') {
      return false
    }
  }
  true
}
