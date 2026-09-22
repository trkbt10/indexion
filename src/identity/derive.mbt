/// Derive a name from content via KGF tokenisation.
///
/// The deriver tokenises text through the registry, keeps only the
/// kinds the spec declares as `identifier_kinds`, and joins the
/// surviving values with a separator. Everything language-specific
/// — what is a word, what is punctuation, what is a structural marker
/// — lives in the KGF spec, not in this code.
///
/// Two name "shapes" are surfaced because identity has two faces:
///
///   - `derive_id`      → kebab-case, lowercase, hyphen-joined, the
///     stable address. Suitable for filesystem ids and manifest keys.
///   - `derive_display` → the title text as the human read it (with
///     spaces preserved, original case kept). Suitable for UI labels.
///
/// Together they form a `Name`: `derive_name(text, hint, registry)`
/// returns a `Name { id, display }` with both roles populated from
/// the same underlying tokenisation. Callers that want only one face
/// can use the dedicated helper.

///|
/// Build the kebab-case identifier form of a piece of text. The
/// implementation walks `@kgf_tokenize.tokenize_file` output, keeps
/// tokens whose kind is declared an identifier kind, lowercases ASCII
/// letters in their values (case folding is well-defined for ASCII;
/// non-ASCII is left to the spec's tokeniser to normalise), and joins
/// with `-`.
///
/// Returns the lowercased input as a fallback when the registry has
/// no spec for `path_hint` (e.g. running outside a project that ships
/// the story spec). This keeps tests and one-off invocations honest
/// rather than silently producing empty ids.
pub fn derive_id(
  text : String,
  path_hint : String,
  registry : @kgf_registry.KGFRegistry,
) -> String {
  if text.length() == 0 {
    return ""
  }
  let kinds = identifier_kinds_for(registry, path_hint)
  let raw = @kgf_tokenize.tokenize_file(text, path_hint, registry)
  let parts : Array[String] = []
  for feat in raw {
    if !@kgf_tokenize.feature_has_value(feat) {
      continue
    }
    let kind = @kgf_tokenize.feature_kind(feat)
    if kinds.is_empty() || kinds.contains(kind) {
      let value = @kgf_tokenize.feature_value(feat)
      if value.length() == 0 {
        continue
      }
      parts.push(lower_ascii(value))
    }
  }
  if parts.is_empty() {
    return lower_ascii(text)
  }
  let buf = StringBuilder()
  for i, part in parts {
    if i > 0 {
      buf.write_char('-')
    }
    buf.write_string(part)
  }
  buf.to_string()
}

///|
/// Build the display form of a piece of text. We currently keep the
/// input verbatim — the deriver's job is to expose the text as the
/// writer wrote it, not to mangle it. Callers that need a sanitized
/// display string can post-process.
pub fn derive_display(text : String) -> String {
  text
}

///|
/// Build a `Name` from text. Convenience wrapper that calls
/// `derive_id` and `derive_display`.
pub fn derive_name(
  text : String,
  path_hint : String,
  registry : @kgf_registry.KGFRegistry,
) -> Name {
  Name::new(
    id=derive_id(text, path_hint, registry),
    display=derive_display(text),
  )
}

///|
/// Read the spec relevant to `path_hint` and return its
/// `identifier_kinds` declaration as a lowercase set. Lowercasing
/// matches what `@kgf_tokenize.feature_kind` returns. When the path
/// has no matching spec, returns an empty set; callers treat that
/// as "no filter" and keep every token.
pub fn identifier_kinds_for(
  registry : @kgf_registry.KGFRegistry,
  path_hint : String,
) -> Map[String, Bool] {
  let kinds : Map[String, Bool] = Map([])
  let lang = match registry.detect_from_path(path_hint) {
    Some(l) => l
    None => return kinds
  }
  let spec = match registry.get_spec(lang) {
    Some(s) => s
    None => return kinds
  }
  match spec.get_feature(@kgf_types.FEATURE_IDENTIFIER_KINDS) {
    Some(values) =>
      for v in values {
        kinds[lower_ascii(v)] = true
      }
    None => ()
  }
  kinds
}

///|
/// Lowercase ASCII letters; leave every other Unicode codepoint as-is.
/// Relies on the Unicode invariant that A..Z and a..z occupy fixed
/// ranges 0x41..0x5A and 0x61..0x7A — not a story-specific heuristic.
/// CJK, hangul, accented Latin etc. fall outside ASCII and are
/// returned untouched, which is correct: case folding outside ASCII
/// is locale-dependent and we have no SoT for that.
pub fn lower_ascii(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      buf.write_char(Int::unsafe_to_char(c.to_int() + 32))
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}
