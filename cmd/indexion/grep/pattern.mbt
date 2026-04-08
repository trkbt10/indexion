///|
/// Token pattern matching engine for KGF-aware grep.

///|
/// A single token matcher in a pattern.
pub enum TokenMatcher {
  /// Match exact token kind (e.g. "KW_fn")
  Kind(String)
  /// Match kind and text (e.g. "Ident:foo")
  KindText(String, String)
  /// Match normalized token text regardless of token kind
  Text(String)
  /// Match any single token
  Any
  /// Match zero or more tokens (non-greedy)
  Ellipsis
  /// Negation — match any token except this kind
  Not(String)
}

///|
/// Build a reverse alias table from KGF spec: literal keyword → token kind.
/// E.g. "pub" → "KW_pub", "fn" → "KW_fn".
/// Also maps punctuation/operators to their token kinds.
pub fn build_alias_table(
  registry : @kgf_registry.KGFRegistry?,
) -> Map[String, String] {
  let aliases : Map[String, String] = {}
  let reg = match registry {
    Some(r) => r
    None => return aliases
  }
  // Iterate all specs to collect token aliases
  for spec_entry in reg.specs {
    let spec = spec_entry.1
    let tokens = spec.get_tokens()
    for tok_def in tokens {
      let name = tok_def.get_name()
      let pattern = tok_def.get_pattern()
      if tok_def.is_skip() {
        continue
      }
      // Keywords (KEYWORD declarations) with pattern "pub\b" → alias "pub" → "KW_pub"
      if spec.is_keyword(name) && pattern.has_suffix("\\b") {
        let literal = @config.substring(
          pattern,
          0,
          pattern.to_array().length() - 2,
        )
        if literal.length() > 0 {
          aliases.set(literal, name)
        }
      }
      // Simple punctuation: name like LPAREN with single-char pattern
      // Map common symbols
      match name {
        "LPAREN" => aliases.set("(", name)
        "RPAREN" => aliases.set(")", name)
        "LBRACE" => aliases.set("{", name)
        "RBRACE" => aliases.set("}", name)
        "LBRACKET" => aliases.set("[", name)
        "RBRACKET" => aliases.set("]", name)
        "COMMA" => aliases.set(",", name)
        "COLON" => aliases.set(":", name)
        "DOT" => aliases.set(".", name)
        "EQ" => aliases.set("=", name)
        "ARROW" => aliases.set("->", name)
        "FATARROW" => aliases.set("=>", name)
        "DCOLON" => aliases.set("::", name)
        _ => ()
      }
    }
  }
  aliases
}

///|
/// Resolve a single pattern part using the alias table.
/// If the part matches an alias (e.g. "pub" → "KW_pub"), return the token kind.
/// Otherwise return the part unchanged.
fn resolve_alias(part : String, aliases : Map[String, String]) -> String {
  match aliases.get(part) {
    Some(kind) => kind
    None => part
  }
}

///|
/// Parse a space-separated pattern string into token matchers.
/// Supports natural language aliases: "pub fn *" is equivalent to "KW_pub KW_fn *".
pub fn parse_pattern(pattern : String) -> Array[TokenMatcher] {
  parse_pattern_with_aliases(pattern, {})
}

///|
/// Parse pattern with alias resolution from KGF spec.
pub fn parse_pattern_with_aliases(
  pattern : String,
  aliases : Map[String, String],
) -> Array[TokenMatcher] {
  let matchers : Array[TokenMatcher] = []
  let parts = split_pattern(pattern)
  for part in parts {
    if part == "*" {
      matchers.push(Any)
    } else if part == "..." {
      matchers.push(Ellipsis)
    } else if part.length() > 1 && part[0] == '!' {
      let negated = resolve_alias(@config.substring_from(part, 1), aliases)
      matchers.push(Not(negated))
    } else {
      // Check for kind:text pattern
      let colon = find_char(part, ':')
      if colon >= 0 {
        let kind = @config.substring(part, 0, colon)
        let text = @config.substring_from(part, colon + 1)
        let resolved_kind = resolve_alias(kind, aliases)
        matchers.push(KindText(resolved_kind, text))
      } else {
        let resolved = resolve_alias(part, aliases)
        if resolved != part || looks_like_token_kind(part) {
          matchers.push(Kind(resolved))
        } else {
          matchers.push(Text(normalize_token_text(part)))
        }
      }
    }
  }
  matchers
}

///|
fn looks_like_token_kind(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  let first = text[0]
  (first >= 'A' && first <= 'Z') || text.has_prefix("KW_")
}

///|
/// Split pattern string by spaces, respecting token boundaries.
fn split_pattern(s : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for c in s {
    if c == ' ' || c == '\t' {
      if buf.to_string().length() > 0 {
        parts.push(buf.to_string())
        buf.reset()
      }
    } else {
      buf.write_char(c)
    }
  }
  if buf.to_string().length() > 0 {
    parts.push(buf.to_string())
  }
  parts
}

///|
fn find_char(s : String, target : Char) -> Int {
  let mut i = 0
  for c in s {
    if c == target {
      return i
    }
    i += 1
  }
  -1
}

///|
/// Check if a single token matches a matcher.
fn matches_token(
  matcher : TokenMatcher,
  tok : @kgf_types.Tok,
  spec : @kgf_types.KGFSpec?,
) -> Bool {
  match matcher {
    Kind(kind) => tok.get_kind() == kind
    KindText(kind, text) => tok.get_kind() == kind && tok.get_text() == text
    Text(text) =>
      match spec {
        Some(value) =>
          @kgf_features.token_search_terms(tok, spec=value).contains(text)
        None => normalize_token_text(tok.get_text()) == text
      }
    Any => true
    Ellipsis => true // Should not be called directly
    Not(kind) => tok.get_kind() != kind
  }
}

///|
fn normalize_token_text(text : String) -> String {
  @kgf_features.to_lower_str(text)
}

///|
/// A match result with position information.
pub struct GrepMatch {
  file : String
  line : Int
  start_tok : Int
  end_tok : Int
  matched_text : String
}

///|
/// Search token stream for pattern matches.
/// Returns all non-overlapping matches.
pub fn find_matches(
  tokens : Array[@kgf_types.Tok],
  matchers : Array[TokenMatcher],
  file : String,
  content : String,
  spec? : @kgf_types.KGFSpec? = None,
) -> Array[GrepMatch] {
  let results : Array[GrepMatch] = []
  // Build token -> line number mapping
  let token_lines = build_token_lines(tokens)
  // Filter out whitespace/newline tokens for pattern matching
  // but keep track of original indices for position reporting
  let significant : Array[(Int, @kgf_types.Tok)] = []
  for i, tok in tokens {
    let kind = tok.get_kind()
    if kind != "NL" && kind != "WS" && kind != "SKIP" {
      significant.push((i, tok))
    }
  }
  let mut pos = 0
  while pos < significant.length() {
    match try_match_at(significant, matchers, pos, spec) {
      Some(end) => {
        let (start_idx, _) = significant[pos]
        let (end_idx, _) = significant[end - 1]
        let line = if start_idx < token_lines.length() {
          token_lines[start_idx]
        } else {
          1
        }
        let matched = extract_matched_text(
          significant, pos, end, content, token_lines,
        )
        results.push({
          file,
          line,
          start_tok: start_idx,
          end_tok: end_idx,
          matched_text: matched,
        })
        pos = end
      }
      None => pos += 1
    }
  }
  results
}

///|
fn build_token_lines(tokens : Array[@kgf_types.Tok]) -> Array[Int] {
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    if tok.get_kind() == "NL" {
      line += 1
    }
  }
  token_lines
}

///|
/// Try to match the pattern starting at position `pos` in the significant token array.
/// Returns the end position (exclusive) if matched, None otherwise.
fn try_match_at(
  tokens : Array[(Int, @kgf_types.Tok)],
  matchers : Array[TokenMatcher],
  pos : Int,
  spec : @kgf_types.KGFSpec?,
) -> Int? {
  match_recursive(tokens, matchers, 0, pos, spec)
}

///|
fn match_recursive(
  tokens : Array[(Int, @kgf_types.Tok)],
  matchers : Array[TokenMatcher],
  mat_idx : Int,
  tok_idx : Int,
  spec : @kgf_types.KGFSpec?,
) -> Int? {
  // All matchers consumed — success
  if mat_idx >= matchers.length() {
    return Some(tok_idx)
  }
  let matcher = matchers[mat_idx]
  match matcher {
    Ellipsis => {
      // Non-greedy: try matching rest at current position first, then expand
      let mut i = tok_idx
      while i <= tokens.length() {
        match match_recursive(tokens, matchers, mat_idx + 1, i, spec) {
          Some(end) => return Some(end)
          None => ()
        }
        i += 1
      }
      None
    }
    _ => {
      if tok_idx >= tokens.length() {
        return None
      }
      let (_, tok) = tokens[tok_idx]
      if matches_token(matcher, tok, spec) {
        match_recursive(tokens, matchers, mat_idx + 1, tok_idx + 1, spec)
      } else {
        None
      }
    }
  }
}

///|
fn extract_matched_text(
  significant : Array[(Int, @kgf_types.Tok)],
  start : Int,
  end : Int,
  _content : String,
  _token_lines : Array[Int],
) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    let (_, tok) = significant[i]
    if i > start {
      buf.write_string(" ")
    }
    buf.write_string(tok.get_text())
  }
  buf.to_string()
}
