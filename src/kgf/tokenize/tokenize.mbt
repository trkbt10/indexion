///|
/// Feature string construction from KGF tokens.
///
/// Sits between the KGF lexer (which splits text into typed tokens) and
/// the TF-IDF engine (which computes vector distances). This package
/// defines the "Kind:value" / "vocab:word" feature string format and
/// provides both construction and decomposition functions.
///
/// Layers:
///   KGF lexer  →  [this package]  →  TF-IDF / stats
///   (structure)   (feature strings)   (vector math)

// ── Feature string format ───────────────────────────────────────────
// Identifier tokens → "Kind:value" (e.g. "Ident:config", "StringLit:hello")
// Syntax tokens     → "Kind"       (e.g. "KW_fn", "LBRACE")
// Vocabulary words  → "vocab:word" (e.g. "vocab:template")

///|
/// Convert a KGF token to a feature string.
///
/// Identifier tokens (as defined by the spec's identifier_kinds) produce
/// "Kind:text"; all others produce "Kind" only.
pub fn tok_to_feature(tok : @types.Tok, id_set~ : Map[String, Bool]) -> String {
  @features.kgf_tok_to_tfidf_token(tok, id_set~)
}

///|
/// Check whether a feature string carries a value (contains `:` separator).
pub fn feature_has_value(feature : String) -> Bool {
  for i = 0; i < feature.length(); i = i + 1 {
    if feature[i] == ':' {
      return true
    }
  }
  false
}

///|
/// Extract the value part from a feature string.
/// "Ident:config" → "config"; "KW_fn" → "KW_fn"
pub fn feature_value(feature : String) -> String {
  for i = 0; i < feature.length(); i = i + 1 {
    if feature[i] == ':' && i < feature.length() - 1 {
      return feature[i + 1:].to_owned()
    }
  }
  feature
}

///|
/// Extract the kind part from a feature string.
/// "Ident:config" → "Ident"; "KW_fn" → "KW_fn"
pub fn feature_kind(feature : String) -> String {
  for i = 0; i < feature.length(); i = i + 1 {
    if feature[i] == ':' {
      return feature[:i].to_owned()
    }
  }
  feature
}

// ── Vocabulary sub-tokenization ─────────────────────────────────────

///|
/// ASCII-only sub-tokenizer.
///
/// Splits text into lowercase words on `[a-zA-Z0-9_]` boundaries and emits
/// `vocab:` feature strings for runs of length ≥ 3. Has no notion of script
/// or part of speech. Used by callers without a `@registry.KGFRegistry`,
/// and as the fallback inside `sub_tokenize_vocab_via_kgfs` when no spec
/// in the registry declares `content_token_kinds`.
pub fn sub_tokenize_vocab(text : String, output : Array[String]) -> Unit {
  let buf = StringBuilder::new()
  for ch in text {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' {
      buf.write_char(ch)
    } else {
      emit_ascii_vocab_word(buf.to_string(), output)
      buf.reset()
    }
  }
  emit_ascii_vocab_word(buf.to_string(), output)
}

///|
fn emit_ascii_vocab_word(raw : String, output : Array[String]) -> Unit {
  let word = raw.to_lower()
  if word.length() < 3 {
    return
  }
  output.push("vocab:" + word)
}

///|
/// Pairs a prepared `LanguageToolkit` with the token kinds the spec declared
/// in `content_token_kinds`.
pub(all) struct NaturalLanguageBinding {
  toolkit : @toolkit.LanguageToolkit
  content_kinds : Map[String, Bool]
}

///|
/// Collect every spec in the registry that declares `content_token_kinds`
/// and prepare a `LanguageToolkit` for each, ready for
/// `sub_tokenize_vocab_via_kgfs`.
pub fn build_natural_language_toolkits(
  registry : @registry.KGFRegistry,
) -> Array[NaturalLanguageBinding] {
  let result : Array[NaturalLanguageBinding] = []
  for lang in registry.get_languages() {
    match registry.get_spec(lang) {
      Some(spec) =>
        match spec.get_feature("content_token_kinds") {
          Some(kinds) => {
            let set : Map[String, Bool] = {}
            for k in kinds {
              set[k] = true
            }
            result.push({
              toolkit: @toolkit.LanguageToolkit::from_spec(spec),
              content_kinds: set,
            })
          }
          None => ()
        }
      None => ()
    }
  }
  result
}

///|
/// Sub-tokenize prose text into `vocab:` features by running each binding's
/// `LanguageToolkit` over the text and keeping tokens whose kind is in that
/// binding's `content_kinds`. Words shorter than 3 characters and duplicates
/// across bindings are dropped.
///
/// When `natural_kgfs` is empty, falls back to `sub_tokenize_vocab`.
pub fn sub_tokenize_vocab_via_kgfs(
  text : String,
  output : Array[String],
  natural_kgfs : Array[NaturalLanguageBinding],
) -> Unit {
  if natural_kgfs.length() == 0 {
    sub_tokenize_vocab(text, output)
    return
  }
  let seen : Map[String, Bool] = {}
  for binding in natural_kgfs {
    for tok in binding.toolkit.tokenize(text) {
      if !binding.content_kinds.contains(tok.get_kind()) {
        continue
      }
      let word = tok.get_text().to_lower()
      if word.length() < 3 {
        continue
      }
      if seen.contains(word) {
        continue
      }
      seen[word] = true
      output.push("vocab:" + word)
    }
  }
}

// ── File tokenization pipeline ──────────────────────────────────────

///|
/// Tokenize a file into feature strings using KGF.
///
/// Produces two layers:
/// 1. KGF tokens → "Kind:value" (identifiers) or "Kind" (syntax)
/// 2. vocabulary_token_kinds → "vocab:word" sub-tokens
///
/// For document specs with `embedded_code_fence` / `embedded_content_token`
/// features, embedded code blocks are re-tokenized with the detected
/// language's KGF spec, producing the same feature strings as standalone
/// files. Reference tokens (e.g., INLINE_CODE) emit their captured value
/// as identifier feature strings.
///
/// Feature strings are lowercased; those shorter than 2 characters are discarded.
pub fn tokenize_file(
  content : String,
  path : String,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  let result : Array[String] = []
  let lang = match registry.detect_from_path(path) {
    Some(l) => l
    None => return result
  }
  let spec = match registry.get_spec(lang) {
    Some(s) => s
    None => return result
  }
  let toolkit = @toolkit.LanguageToolkit::from_spec(spec)
  let id_set = toolkit.get_identifier_set()
  let vocab_set = toolkit.get_vocabulary_set()
  let ref_set = build_feature_set(spec, @types.FEATURE_REFERENCE_TOKEN_KINDS)
  let natural_kgfs = build_natural_language_toolkits(registry)
  // Embedded code fence handling (declared in KGF features section).
  // If the spec declares embedded_code_fence, we track open/close state
  // and re-tokenize content tokens with the detected language's spec.
  let fence_token = get_single_feature(spec, @types.FEATURE_EMBEDDED_CODE_FENCE)
  let content_token = get_single_feature(
    spec,
    @types.FEATURE_EMBEDDED_CONTENT_TOKEN,
  )
  let tokens = toolkit.tokenize(content)
  let mut in_fence = false
  let mut fence_spec : @types.KGFSpec? = None
  for tok in tokens {
    let kind = tok.get_kind()
    // Embedded code fence tracking (driven by KGF features, not hardcoded)
    match fence_token {
      Some(ft) =>
        if kind == ft {
          if !in_fence {
            in_fence = true
            fence_spec = resolve_embedded_spec(tok, registry)
          } else {
            in_fence = false
            fence_spec = None
          }
          continue
        }
      None => ()
    }
    // Standard feature string from the file's own KGF
    let feature = tok_to_feature(tok, id_set~)
    let lowered = feature.to_lower()
    if lowered.length() >= 2 {
      result.push(lowered)
    }
    // Re-tokenize embedded content with the fence language's spec
    match (fence_spec, content_token) {
      (Some(fspec), Some(ct)) =>
        if in_fence && kind == ct {
          tokenize_with_spec(tok.get_text(), fspec, result, natural_kgfs~)
          continue
        }
      _ => ()
    }
    // Reference tokens emit their captured value as an identifier
    if ref_set.contains(kind) {
      let value = tok.get_value()
      if value.length() >= 2 {
        result.push("Ident:" + value.to_lower())
      }
    }
    // Vocabulary sub-tokens for natural language content
    if vocab_set.contains(kind) {
      sub_tokenize_vocab_via_kgfs(tok.get_text(), result, natural_kgfs)
    }
  }
  result
}

///|
/// Tokenize content using a specific KGF spec, appending feature strings
/// to the output array. Used both for top-level file tokenization and
/// for re-tokenizing embedded code blocks with their own spec.
///
/// `natural_kgfs` is forwarded to `sub_tokenize_vocab_via_kgfs` for vocab
/// sub-tokenization; omitting it routes vocab tokens through the ASCII
/// fallback `sub_tokenize_vocab`.
pub fn tokenize_with_spec(
  content : String,
  spec : @types.KGFSpec,
  output : Array[String],
  natural_kgfs? : Array[NaturalLanguageBinding] = [],
) -> Unit {
  let toolkit = @toolkit.LanguageToolkit::from_spec(spec)
  let id_set = toolkit.get_identifier_set()
  let vocab_set = toolkit.get_vocabulary_set()
  let tokens = toolkit.tokenize(content)
  for tok in tokens {
    let feature = tok_to_feature(tok, id_set~)
    let lowered = feature.to_lower()
    if lowered.length() >= 2 {
      output.push(lowered)
    }
    if vocab_set.contains(tok.get_kind()) {
      sub_tokenize_vocab_via_kgfs(tok.get_text(), output, natural_kgfs)
    }
  }
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Resolve the KGF spec for an embedded code block's language.
/// Uses the token's captured value (e.g., "json" from ` ```json `)
/// to look up the registry. Returns None if unrecognized or no identifiers.
fn resolve_embedded_spec(
  tok : @types.Tok,
  registry : @registry.KGFRegistry,
) -> @types.KGFSpec? {
  let lang_hint = tok.get_value().to_lower()
  if lang_hint.length() == 0 {
    return None
  }
  let spec = match registry.get_spec(lang_hint) {
    Some(s) => Some(s)
    None =>
      match registry.detect_from_path("_." + lang_hint) {
        Some(detected_lang) => registry.get_spec(detected_lang)
        None => None
      }
  }
  match spec {
    Some(s) => {
      let id_kinds = @features.build_identifier_set(spec=s)
      if id_kinds.is_empty() {
        None
      } else {
        Some(s)
      }
    }
    None => None
  }
}

///|
/// Build a set from a KGF spec feature.
fn build_feature_set(
  spec : @types.KGFSpec,
  feature_name : String,
) -> Map[String, Bool] {
  let set : Map[String, Bool] = {}
  match spec.get_feature(feature_name) {
    Some(kinds) =>
      for kind in kinds {
        set[kind] = true
      }
    None => ()
  }
  set
}

///|
/// Get a single-valued feature from a KGF spec.
fn get_single_feature(spec : @types.KGFSpec, name : String) -> String? {
  match spec.get_feature(name) {
    Some(values) => if values.length() > 0 { Some(values[0]) } else { None }
    None => None
  }
}
