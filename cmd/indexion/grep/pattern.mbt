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
/// Build a reverse alias table from a single KGF spec: literal text → token kind.
///
/// Two kinds of aliases are derived purely from spec contents — no token
/// name is hardcoded here:
///
///   1. **Keyword aliases.** For each token marked `KEYWORD` whose pattern
///      ends with `\b` (the conventional KGF keyword form `pub\b`,
///      `fn\b`, ...), strip the trailing `\b` and register the literal as
///      an alias to the kind name. E.g. `TOKEN KW_pub /pub\b/` becomes
///      `"pub" → "KW_pub"`.
///   2. **Punctuation aliases.** For any token whose entire pattern is a
///      literal string (modulo regex meta-character escapes), register
///      that literal as an alias to the kind name. E.g.
///      `TOKEN LPAREN /\(/` becomes `"(" → "LPAREN"`,
///      `TOKEN DCOLON /::/` becomes `"::" → "DCOLON"`, and
///      `TOKEN FATARROW /=>/` becomes `"=>" → "FATARROW"`.
///      Literal extraction is delegated to `TokenDef::literal_text` —
///      regex-grammar interpretation lives on the type that owns the
///      pattern, not in this consumer.
///
/// Keyword aliases take precedence over punctuation aliases for the same
/// literal so that `pub` always resolves to `KW_pub`, never to a stray
/// punctuation kind that happens to use the literal text "pub".
///
/// The table is per-spec because different KGF specs use different names
/// for the same literal (MoonBit's `LPAREN` vs Mermaid's `RoundOpen` both
/// declare `TOKEN ... /\(/`). A global union would silently lose entries
/// to name collisions; pinning the table to one spec keeps grep correct
/// in mixed-language projects.
pub fn build_alias_table(spec : @kgf_types.KGFSpec?) -> Map[String, String] {
  let aliases : Map[String, String] = {}
  let spec_value = match spec {
    Some(s) => s
    None => return aliases
  }
  for tok_def in spec_value.get_tokens() {
    if tok_def.is_skip() {
      continue
    }
    let name = tok_def.get_name()
    let pattern = tok_def.get_pattern()
    // (1) Keyword aliases derived from `<literal>\b` patterns.
    if spec_value.is_keyword(name) && pattern.has_suffix("\\b") {
      let literal = @config.substring(
        pattern,
        0,
        pattern.to_array().length() - 2,
      )
      if literal.length() > 0 {
        aliases[literal] = name
        continue
      }
    }
    // (2) Punctuation/operator aliases derived from purely-literal
    //     patterns. The "is this regex a fixed literal?" question is
    //     answered by the regex engine itself via
    //     `CompiledPattern::literal_text`, so regex grammar knowledge
    //     stays inside `@regexp`. Skip when the literal would shadow a
    //     keyword.
    let literal_opt = match @regexp.compile_pattern(pattern) {
      Some(compiled) => compiled.literal_text()
      None => None
    }
    match literal_opt {
      Some(literal) => if !aliases.contains(literal) { aliases[literal] = name }
      None => ()
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
/// Collect the set of token-kind names defined by a single KGF spec.
/// Used by `parse_pattern_with_aliases` to decide whether a bare pattern
/// part (e.g. `TypeIdent`, `KW_fn`) refers to a real token kind. Per-spec
/// so that a pattern like `TypeIdent` (a MoonBit kind) is treated as a
/// Kind matcher when grepping MoonBit but falls back to a Text matcher
/// when grepping a language that has no such kind.
pub fn build_kind_set(spec : @kgf_types.KGFSpec?) -> Map[String, Bool] {
  let kinds : Map[String, Bool] = {}
  let spec_value = match spec {
    Some(s) => s
    None => return kinds
  }
  for tok_def in spec_value.get_tokens() {
    if tok_def.is_skip() {
      continue
    }
    kinds[tok_def.get_name()] = true
  }
  kinds
}

///|
/// Convenience wrapper that resolves the KGF spec for `path` from
/// `registry` and parses `pattern` against that spec. Returns an empty
/// matcher list if the pattern is empty or the registry has no entry for
/// the file (in which case parsing falls back to language-agnostic
/// heuristics, so plain text patterns like `version` still work).
pub fn parse_pattern_for_path(
  pattern : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[TokenMatcher] {
  let spec = match registry {
    Some(reg) =>
      match reg.detect_from_path(path) {
        Some(lang) => reg.get_spec(lang)
        None => None
      }
    None => None
  }
  let aliases = build_alias_table(spec)
  let kinds = build_kind_set(spec)
  parse_pattern_with_aliases(pattern, aliases, kinds~)
}

///|
/// Parse a space-separated pattern string into token matchers.
/// Supports natural language aliases: "pub fn *" is equivalent to "KW_pub KW_fn *".
pub fn parse_pattern(pattern : String) -> Array[TokenMatcher] {
  parse_pattern_with_aliases(pattern, {})
}

///|
/// Parse pattern with alias resolution from KGF spec.
///
/// A bare pattern part becomes a `Kind` matcher when it names a real token
/// kind from the loaded KGF registry, and a `Text` matcher otherwise. The
/// `kinds` argument carries that set (see `build_kind_set`). When `kinds`
/// is empty — typically because no registry is available, as in tests that
/// only pass a literal alias map — the parser falls back to a lexical
/// heuristic so callers without a registry still get plausible behavior.
pub fn parse_pattern_with_aliases(
  pattern : String,
  aliases : Map[String, String],
  kinds? : Map[String, Bool] = {},
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
        if resolved != part || is_known_kind(part, kinds) {
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
/// Decide whether `part` names a token kind that should be matched
/// structurally rather than as text. When the KGF registry is available
/// (`kinds` non-empty) we authoritatively check against the set of declared
/// kinds — this avoids the historical bug where PascalCase identifiers like
/// `Handle` were treated as kind names even though no spec defines such a
/// kind. With no registry loaded (`kinds` empty), fall back to the original
/// lexical heuristic so test fixtures that pass only an alias map keep
/// working.
fn is_known_kind(part : String, kinds : Map[String, Bool]) -> Bool {
  if kinds.is_empty() {
    return looks_like_token_kind(part)
  }
  kinds.contains(part)
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
  let token_lines = build_token_lines(tokens)
  // Filter out structurally insignificant tokens (newlines, indentation,
  // whitespace) before pattern matching. The set of kinds to drop is
  // derived from the active KGF spec rather than hardcoded — see
  // `@kgf_features.build_insignificant_token_set`. Original indices are
  // preserved for position reporting.
  let insignificant = @kgf_features.build_insignificant_token_set(spec~)
  let significant : Array[(Int, @kgf_types.Tok)] = []
  for i, tok in tokens {
    if !insignificant.contains(tok.get_kind()) {
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
/// Map each token index to the 1-indexed line where the token begins.
/// Advances the line counter by the number of `\n` characters in each
/// token's own text, which is correct regardless of how a given KGF spec
/// names its newline-bearing tokens (NL, NL_INDENT, ...) and also accounts
/// for multi-line tokens like block comments and multi-line strings.
fn build_token_lines(tokens : Array[@kgf_types.Tok]) -> Array[Int] {
  let token_lines : Array[Int] = Array::make(tokens.length(), 1)
  let mut line = 1
  for i, tok in tokens {
    token_lines[i] = line
    for ch in tok.get_text() {
      if ch == '\n' {
        line += 1
      }
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
