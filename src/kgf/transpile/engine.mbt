///|
/// # Transpile engine: lift + lower
///
/// The engine is split into two halves so that an N×M language matrix
/// reduces to N+M specs:
///
///   source_kgf_events --(LiftSpec, source.lift)--> canonical_ir_events
///   canonical_ir_events --(LowerSpec, target.lower)--> target_code
///
/// The engine itself contains zero language-pair logic. All language- and
/// pair-specific data lives in `kgf-transpile/<lang>.json` files.

///|
/// True for label keys we treat as type-bearing text.
/// Keys: `_text`, `*_text` (e.g. `id_text`, `body_text`).
fn is_text_label(key : String) -> Bool {
  key == "_text" || key.has_suffix("_text")
}

///|
/// A token (identifier) consists of ASCII letters, digits, and `_`.
/// Anything else is a boundary. Mirrors the lexical class used by most
/// C-family and ML-family languages and keeps the engine language-agnostic.
fn is_token_boundary(c : Char) -> Bool {
  !is_identifier_char(c)
}

///|
fn is_identifier_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// Replace whole-token occurrences via the `scalars` table. Tokens are
/// alphanumeric+underscore runs; everything else is a boundary.
fn apply_scalar_subs(text : String, scalars : Map[String, String]) -> String {
  if scalars.is_empty() {
    return text
  }
  let chars = text.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    if is_token_boundary(chars[i]) {
      buf.write_char(chars[i])
      i = i + 1
      continue
    }
    let start = i
    while i < chars.length() && !is_token_boundary(chars[i]) {
      i = i + 1
    }
    let token = text[start:i].to_owned()
    match scalars.get(token) {
      Some(replacement) => buf.write_string(replacement)
      None => buf.write_string(token)
    }
  }
  buf.to_string()
}

///|
/// Apply suffix-style type wraps until none fire. Each pass examines every
/// wrap rule; recursion is implicit through repeated passes.
fn apply_type_wraps(text : String, wraps : Array[TypeWrap]) -> String {
  let mut current = text
  let mut changed = true
  let max_iters = 8
  let mut iter = 0
  while changed && iter < max_iters {
    changed = false
    for wrap in wraps {
      let rewritten = apply_one_wrap(current, wrap)
      if rewritten != current {
        current = rewritten
        changed = true
      }
    }
    iter = iter + 1
  }
  current
}

///|
/// Apply a single suffix-wrap rule. `target_template` uses `%s` as the
/// inner-type placeholder.
fn apply_one_wrap(text : String, wrap : TypeWrap) -> String {
  if !text.has_suffix(wrap.source_suffix) {
    return text
  }
  let inner_len = text.length() - wrap.source_suffix.length()
  if inner_len <= 0 {
    return text
  }
  let inner = text[:inner_len].to_owned()
  let placeholder_pos = find_substring(wrap.target_template, "%s")
  match placeholder_pos {
    Some(p) =>
      wrap.target_template[:p].to_owned() +
      inner +
      wrap.target_template[p + 2:wrap.target_template.length()].to_owned()
    None => wrap.target_template
  }
}

///|
/// Apply lift's wraps then scalars to a type-bearing fragment. Used by
/// `apply_extract_text` where we KNOW the text is a pure type expression.
/// Do NOT use during the broad lift_event pass — that pass sees composite
/// `_text` labels (e.g. `argv:string[]` for a Param) where applying a
/// suffix wrap would treat the whole composite as one type.
pub fn lift_type_text(text : String, lift : LiftSpec) -> String {
  let wrapped = apply_type_wraps(text, lift.type_wraps)
  apply_scalar_subs(wrapped, lift.scalars)
}

///|
/// Scalars-only rewrite for the broad lift_event pass. Whole-token scalar
/// substitution is safe even on composite `_text` like `id:number;` — it
/// only replaces standalone `number` → `Float`, never substring matches.
fn lift_scalars_only(text : String, lift : LiftSpec) -> String {
  apply_scalar_subs(text, lift.scalars)
}

///|
/// Apply lower's wraps then scalars to a canonical IR type-bearing fragment.
fn lower_type_text(text : String, lower : LowerSpec) -> String {
  let wrapped = apply_type_wraps(text, lower.type_wraps)
  apply_scalar_subs(wrapped, lower.scalars)
}

///|
/// Lift one event: apply rule rename and (scalars-only) rewrite text-bearing
/// labels. Type wraps are NOT applied here because labels can be composite
/// (`argv:string[]`); wraps are applied only via `extract_text` rules where
/// we know the fragment is a pure type expression.
///
/// Each `*_text` label is preserved verbatim as `*_text_raw` BEFORE
/// scalar substitution, so `extract_text` rules can isolate fragments
/// from the original source — important for suffix wraps (`T | null`) that
/// would not match a post-scalarized form (`T | Unit`).
///
/// After scalar subs, the lift's `regex_replace` rules are applied to
/// every non-internal string label. This is where source-language-only
/// body syntax (TS `===`, `;`, `\`...\``) is stripped/canonicalized.
/// Target specs MUST NOT carry source-specific patterns — those belong
/// here.
fn lift_event(
  event : (String, Map[String, Json]),
  lift : LiftSpec,
) -> (String, Map[String, Json]) {
  let (rule, labels) = event
  let new_rule = match lift.rule_lifts.get(rule) {
    Some(r) => r
    None => rule
  }
  let new_labels : Map[String, Json] = {}
  for entry in labels {
    let key = entry.0
    let value = entry.1
    if is_text_label(key) {
      match value {
        String(s) => {
          // Preserve raw source text under <key>_raw for downstream
          // extract_text rules; emit lifted text under the original key.
          new_labels.set(key + "_raw", Json::string(s))
          new_labels.set(key, Json::string(lift_scalars_only(s, lift)))
        }
        _ => new_labels.set(key, value)
      }
    } else {
      new_labels.set(key, value)
    }
  }
  if new_rule != rule {
    new_labels.set("_origin_rule", Json::string(rule))
  }
  // Source-side body normalization. Skip internal `_*` keys (token ranges,
  // origin rule). Skip `*_text_raw` so extract_text rules still see the
  // original source for suffix-wrap matching (e.g. `| null`).
  let lift_regex = lift.regex_replace()
  if lift_regex.length() > 0 {
    for entry in new_labels {
      let key = entry.0
      if key.has_prefix("_") {
        continue
      }
      if key.has_suffix("_raw") {
        continue
      }
      match entry.1 {
        String(s) =>
          new_labels.set(
            key,
            Json::string(apply_regex_replace_all(s, lift_regex)),
          )
        _ => ()
      }
    }
  }
  (new_rule, new_labels)
}

///|
/// Lift a full event stream from KGF source-language events to canonical IR.
pub fn lift_events(
  events : Array[(String, Map[String, Json])],
  lift : LiftSpec,
) -> Array[(String, Map[String, Json])] {
  events.iter().map(fn(e) { lift_event(e, lift) }).collect()
}

///|
/// Render a template by substituting `{{name}}` placeholders. Missing
/// labels emit `<unresolved_marker><name>`. Single `{` and `}` are literal
/// — needed because target languages (MoonBit, Rust, C-family, Swift) all
/// use `{ ... }` for blocks/struct literals in their actual syntax.
fn render_template(
  template : String,
  labels : Map[String, Json],
  unresolved_marker : String,
) -> String {
  let buf = StringBuilder::new()
  let chars = template.to_array()
  let mut i = 0
  while i < chars.length() {
    // Look for `{{` (placeholder opener).
    if chars[i] == '{' && i + 1 < chars.length() && chars[i + 1] == '{' {
      // Find matching `}}`.
      let key_start = i + 2
      let mut j = key_start
      while j + 1 < chars.length() &&
            !(chars[j] == '}' && chars[j + 1] == '}') {
        j = j + 1
      }
      if j + 1 >= chars.length() {
        // Unterminated; emit verbatim and bail.
        buf.write_char('{')
        i = i + 1
        continue
      }
      let key = template[key_start:j].to_owned()
      let value = label_to_string(labels.get(key))
      match value {
        Some(s) => buf.write_string(s)
        None => {
          buf.write_string(unresolved_marker)
          buf.write_string(key)
        }
      }
      i = j + 2
    } else {
      buf.write_char(chars[i])
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Coerce a Json label to a printable string. Missing → None.
fn label_to_string(value : Json?) -> String? {
  match value {
    Some(String(s)) => Some(s)
    Some(Number(n, ..)) => Some(n.to_string())
    Some(True) => Some("true")
    Some(False) => Some("false")
    Some(Null) => Some("null")
    Some(other) => Some(other.stringify())
    None => None
  }
}

///|
/// Build the preamble label set: `comment_prefix`, `source_lang`,
/// `target_lang`, `unresolved_marker`. Used to render `preamble_template`.
fn make_preamble_labels(
  source_lang : String,
  target_lang : String,
  unresolved_marker : String,
  comment_prefix : String,
) -> Map[String, Json] {
  let m : Map[String, Json] = {}
  m.set("comment_prefix", Json::string(comment_prefix))
  m.set("source_lang", Json::string(source_lang))
  m.set("target_lang", Json::string(target_lang))
  m.set("unresolved_marker", Json::string(unresolved_marker))
  m
}

///|
/// Lower canonical IR events into target-language code.
///
/// Drives:
/// 1. The preamble (rendered from `lower.preamble_template`).
/// 2. Per-event structural enrichment via `apply_structural_rules` —
///    needs both the SOURCE lift spec (to know which structural rules to
///    apply for each `_origin_rule`) and the full original event stream
///    (for sibling/inner lookups by token range).
/// 3. Per-event template rendering, with `default_body` injection for
///    IRFn events lacking a body label.
///
/// The engine itself contains zero per-language logic. All language- and
/// pair-specific data flows in via `lift` and `lower`.
pub fn lower_to_code(
  ir_events : Array[(String, Map[String, Json])],
  raw_events : Array[(String, Map[String, Json])],
  source_lang : String,
  target_lang : String,
  unresolved_marker : String,
  lift : LiftSpec,
  lower : LowerSpec,
) -> String {
  let buf = StringBuilder::new()
  let preamble_labels = make_preamble_labels(
    source_lang,
    target_lang,
    unresolved_marker,
    lower.comment_prefix,
  )
  buf.write_string(
    render_template(lower.preamble_template, preamble_labels, unresolved_marker),
  )
  let order_set : Map[String, Bool] = {}
  for r in lower.emit_order {
    order_set.set(r, true)
  }
  for event in ir_events {
    let rule = event.0
    let labels = event.1
    if !order_set.contains(rule) {
      continue
    }
    // Copy labels through unchanged. Do NOT apply lower_type_text to
    // `*_text` labels here: extract_text would then read an
    // already-lower-rewritten fragment and re-apply lower, producing
    // duplicates like `std::std::string`. Structurally-derived labels
    // (rhs, type, fields, params, return) get their own lift+lower
    // inside `apply_extract_text` and `apply_collect_inner_as`.
    let lowered_labels : Map[String, Json] = {}
    for entry in labels {
      lowered_labels.set(entry.0, entry.1)
    }
    // Apply structural rules. May return a different IR rule when a
    // conditional_lift fires (e.g. TS string-literal-union TypeDecl
    // becomes IREnum instead of IRTypeAlias).
    let effective_rule = apply_structural_rules(
      rule, lowered_labels, raw_events, lift, lower, unresolved_marker,
    )
    // The conditional lift may have moved the event into a rule that is
    // outside the original `emit_order` membership — re-check.
    if !order_set.contains(effective_rule) {
      continue
    }
    // Translate library imports semantically (node:fs → fs → @fs etc.).
    apply_module_alias(lowered_labels, lift, lower)
    // IRFn body fallback: if `body` is missing or unparseable, substitute
    // the lower's `default_body` so the emitted code still compiles as
    // a stub. This is the difference between "marker" and "compilable".
    inject_default_body(effective_rule, lowered_labels, lower)
    // Source-intent comment, if the source rule declared one. Renders
    // the `source_intent_comment` template before the main template so
    // the original source text stays visible alongside the lowered code.
    emit_source_intent_comment(
      buf, lift, lower, lowered_labels, unresolved_marker,
    )
    match lower.emit_templates.get(effective_rule) {
      Some(template) => {
        // Apply text_replace per-label (so `->` in the template literal
        // is NOT munged by `> → ]`, only canonical-IR-shaped label values).
        let post_labels = apply_text_replace_to_labels(
          lowered_labels,
          lower.scalars,
          lower.text_replace(),
          lower.text_replace_pairs(),
          lower.regex_replace(),
        )
        let rendered = render_template(template, post_labels, unresolved_marker)
        buf.write_string(rendered)
        if !rendered.has_suffix("\n") {
          buf.write_string("\n")
        }
      }
      None => {
        let fallback_labels : Map[String, Json] = {}
        fallback_labels.set(
          "comment_prefix",
          Json::string(lower.comment_prefix),
        )
        fallback_labels.set(
          "unresolved_marker",
          Json::string(unresolved_marker),
        )
        fallback_labels.set("rule", Json::string(effective_rule))
        buf.write_string(
          render_template(
            lower.no_template_template,
            fallback_labels,
            unresolved_marker,
          ),
        )
      }
    }
  }
  buf.to_string()
}

///|
/// If the source's structural_rules entry declares a `source_intent_comment`,
/// render and emit it BEFORE the main template. The same labels are
/// available, plus `comment_prefix`. Used to preserve source text alongside
/// a structurally-translated declaration so a later agent can refine the
/// transpile (e.g. emit `// SOURCE: type X = "a" | "b"` above a lifted
/// IREnum so the original literal mapping is recoverable).
fn emit_source_intent_comment(
  buf : StringBuilder,
  lift : LiftSpec,
  lower : LowerSpec,
  labels : Map[String, Json],
  unresolved_marker : String,
) -> Unit {
  let origin = match labels.get("_origin_rule") {
    Some(String(s)) => s
    _ => return
  }
  let rule = match lift.structural_rules().get(origin) {
    Some(r) => r
    None => return
  }
  match rule.source_intent_comment {
    Some(template) => {
      let with_prefix : Map[String, Json] = {}
      for entry in labels {
        with_prefix.set(entry.0, entry.1)
      }
      with_prefix.set("comment_prefix", Json::string(lower.comment_prefix))
      let rendered = render_template(template, with_prefix, unresolved_marker)
      buf.write_string(rendered)
      if !rendered.has_suffix("\n") {
        buf.write_string("\n")
      }
    }
    None => ()
  }
  ignore(lift)
}

///|
/// Apply the source lift's structural rules to enrich an event's labels
/// before template rendering. Looks up rules by the event's `_origin_rule`
/// label (set during lift) — that gives us the source-language rule name.
///
/// Returns the (possibly conditional-lift overridden) IR rule name.
fn apply_structural_rules(
  current_rule : String,
  labels : Map[String, Json],
  raw_events : Array[(String, Map[String, Json])],
  lift : LiftSpec,
  lower : LowerSpec,
  unresolved_marker : String,
) -> String {
  let origin = match labels.get("_origin_rule") {
    Some(String(s)) => s
    _ => return current_rule
  }
  let rules = lift.structural_rules()
  let rule = match rules.get(origin) {
    Some(r) => r
    None => return current_rule
  }
  let start_tok = label_int(labels, "_start_tok")
  let end_tok = label_int(labels, "_end_tok")
  // 1) id_from — needs to run before conditional_lifts so id_text is set.
  match rule.id_from {
    Some(spec) => apply_id_from(labels, spec, raw_events, start_tok, end_tok)
    None => ()
  }
  // 2) extract_text — also before conditional_lifts; the predicate may
  // inspect labels populated here (e.g. `rhs`).
  match rule.extract_text {
    Some(rules) =>
      for r in rules {
        apply_extract_text(labels, r, lift, lower)
      }
    None => ()
  }
  // 3) Conditional lifts — may override the IR rule.
  let mut effective_rule = current_rule
  match rule.conditional_lifts {
    Some(conds) =>
      for c in conds {
        if predicate_matches(c.predicate, labels) {
          effective_rule = c.lift_to
          // Repopulate the rule label for downstream observers.
          labels.set("_lifted_rule", Json::string(c.lift_to))
          // Optional: split a text label into a list, casing per the
          // lower's `variant_case_style` (pascal/lower/screaming),
          // joined by the lower's per-label separator (consistent with
          // the indentation the emit_template expects).
          match c.split_label_capitalized {
            Some(label_name) =>
              populate_variant_split(
                labels,
                label_name,
                lower.collect_separators().get(label_name).unwrap_or("\n  "),
                lower.variant_case_style(),
              )
            None => ()
          }
          break
        }
      }
    None => ()
  }
  // 4) collect_inner_as — uses raw events, doesn't depend on rule rename.
  match rule.collect_inner_as {
    Some(rules) =>
      for r in rules {
        apply_collect_inner_as(
          labels, r, raw_events, start_tok, end_tok, lift, lower, unresolved_marker,
        )
      }
    None => ()
  }
  effective_rule
}

///|
/// Evaluate a `ConditionalLift.predicate` against the current labels.
/// Currently the only supported predicate is `string_literal_union`,
/// which inspects the `rhs` label.
fn predicate_matches(name : String, labels : Map[String, Json]) -> Bool {
  match name {
    "string_literal_union" => {
      let rhs = match labels.get("rhs") {
        Some(String(s)) => s
        _ => return false
      }
      is_string_literal_union(rhs)
    }
    _ => false
  }
}

///|
/// True when every `|`-separated token in `text` is an identifier-only
/// quoted-or-unquoted string (e.g. `"a" | "b" | "c"` or `a|b|c`).
fn is_string_literal_union(text : String) -> Bool {
  let parts = split_on(text, "|")
  if parts.length() < 2 {
    return false
  }
  for raw in parts {
    let trimmed = trim_ascii(raw)
    let stripped = strip_quotes(trimmed)
    if stripped.length() == 0 {
      return false
    }
    let chars = stripped.to_array()
    for c in chars {
      if !is_identifier_char(c) {
        return false
      }
    }
  }
  true
}

///|
/// Populate `<label_name>` with capitalized variant names extracted from
/// the parent's `rhs` label. Used by the `string_literal_union` lift to
/// produce an `IREnum`'s `variants` value.
fn populate_variant_split(
  labels : Map[String, Json],
  label_name : String,
  separator : String,
  case_style : String,
) -> Unit {
  let rhs = match labels.get("rhs") {
    Some(String(s)) => s
    _ => return
  }
  let parts = split_on(rhs, "|")
  let variants : Array[String] = []
  for raw in parts {
    let trimmed = trim_ascii(raw)
    let stripped = strip_quotes(trimmed)
    if stripped.length() == 0 {
      continue
    }
    variants.push(apply_case_style(stripped, case_style))
  }
  let joined = variants.iter().map(fn(s) { s }).collect().join(separator)
  labels.set(label_name, Json::string(joined))
}

///|
fn apply_case_style(s : String, style : String) -> String {
  match style {
    "lower" => to_ascii_lower(s)
    "screaming" => to_ascii_upper(s)
    _ => capitalize_first(s)
  }
}

///|
fn to_ascii_lower(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      buf.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn to_ascii_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c >= 'a' && c <= 'z' {
      buf.write_char((c.to_int() - 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn split_on(text : String, sep : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let mut i = 0
  while i + sep.length() <= text.length() {
    if text[i:i + sep.length()].to_owned() == sep {
      result.push(text[start:i].to_owned())
      i = i + sep.length()
      start = i
    } else {
      i = i + 1
    }
  }
  result.push(text[start:text.length()].to_owned())
  result
}

///|
fn strip_quotes(s : String) -> String {
  if s.length() < 2 {
    return s
  }
  let first = s.to_array()[0]
  let last = s.to_array()[s.length() - 1]
  if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
fn capitalize_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let chars = s.to_array()
  let first = chars[0]
  let upper = if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char()
  } else {
    first
  }
  let buf = StringBuilder::new()
  buf.write_char(upper)
  buf.write_string(s[1:s.length()].to_owned())
  buf.to_string()
}

///|
/// `id_from` syntax: `<SiblingRule>.<label>`. Find an event whose rule is
/// `<SiblingRule>` and whose token range falls inside `[start_tok, end_tok]`,
/// copy its `<label>` into the parent's same-named label.
fn apply_id_from(
  labels : Map[String, Json],
  spec : String,
  raw_events : Array[(String, Map[String, Json])],
  start_tok : Int,
  end_tok : Int,
) -> Unit {
  let dot = find_substring(spec, ".")
  let dot_pos = match dot {
    Some(p) => p
    None => return
  }
  let sibling_rule = spec[:dot_pos].to_owned()
  let label_key = spec[dot_pos + 1:spec.length()].to_owned()
  for ev in raw_events {
    if ev.0 != sibling_rule {
      continue
    }
    let s = label_int(ev.1, "_start_tok")
    let e = label_int(ev.1, "_end_tok")
    if s >= start_tok && e <= end_tok {
      match ev.1.get(label_key) {
        Some(value) => {
          labels.set(label_key, value)
          return
        }
        None => ()
      }
    }
  }
}

///|
/// `extract_text`: operate on the parent's `_text` label, isolate a fragment
/// using simple "after / before" delimiters, optionally trim. The extracted
/// fragment is then passed through both lift's and lower's text rewriting
/// (wraps + scalars) so canonical IR ends up in target syntax.
fn apply_extract_text(
  labels : Map[String, Json],
  rule : ExtractText,
  lift : LiftSpec,
  lower : LowerSpec,
) -> Unit {
  // Read from `_text_raw` (the pre-lift original) when available, so
  // suffix wraps targeting source-language tokens (e.g. `| null`) can
  // still match. Fall back to `_text` for events without a raw twin.
  let text = match labels.get("_text_raw") {
    Some(String(s)) => s
    _ =>
      match labels.get("_text") {
        Some(String(s)) => s
        _ => return
      }
  }
  let after_pos = if rule.after.length() == 0 {
    0
  } else {
    match find_substring(text, rule.after) {
      Some(p) => p + rule.after.length()
      None => return
    }
  }
  let before_pos = if rule.before.length() == 0 {
    text.length()
  } else {
    let tail = text[after_pos:text.length()].to_owned()
    match find_substring(tail, rule.before) {
      Some(p) => after_pos + p
      None => text.length()
    }
  }
  let raw = text[after_pos:before_pos].to_owned()
  let trimmed = if rule.trim { trim_ascii(raw) } else { raw }
  // Source-side rewrite: TS `T[]` → canonical `Array<T>`; `number` → `Float`.
  let lifted = lift_type_text(trimmed, lift)
  // Target-side rewrite: canonical `Float` → moonbit `Double`.
  let lowered = lower_type_text(lifted, lower)
  // Optional union simplification — handles mixed-type unions
  // (`TodoStatus | "all"`) by keeping only the first alternative.
  let simplify = match rule.simplify_unions {
    Some(b) => b
    None => false
  }
  let final_value = if simplify && contains_char(lowered, '|') {
    let parts = split_on(lowered, "|")
    if parts.length() > 0 {
      trim_ascii(parts[0])
    } else {
      lowered
    }
  } else {
    lowered
  }
  labels.set(rule.label, Json::string(final_value))
}

///|
fn contains_char(text : String, c : Char) -> Bool {
  for ch in text {
    if ch == c {
      return true
    }
  }
  false
}

///|
fn trim_ascii(s : String) -> String {
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() && is_space(chars[i]) {
    i = i + 1
  }
  let mut j = chars.length()
  while j > i && is_space(chars[j - 1]) {
    j = j - 1
  }
  s[i:j].to_owned()
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// `collect_inner_as`: find inner events of `rule.rule` whose token range
/// falls inside this event, lift each via the same lift pipeline, render
/// each via the target's template for the lifted IR rule, join with
/// `rule.join_with`, store in this event's `rule.label` label.
fn apply_collect_inner_as(
  labels : Map[String, Json],
  rule : CollectInnerAs,
  raw_events : Array[(String, Map[String, Json])],
  start_tok : Int,
  end_tok : Int,
  lift : LiftSpec,
  lower : LowerSpec,
  unresolved_marker : String,
) -> Unit {
  let rendered_children : Array[String] = []
  // Filter: inner events with the requested KGF rule, token range inside
  // the parent (and not equal to the parent itself). When the same rule
  // can appear nested (e.g. TS `Param` inside a closure type that's
  // itself a parent Param's type annotation), keep only DIRECT children
  // — events whose range isn't strictly enclosed by another matching
  // event of the same rule that itself sits inside the parent.
  for ev in raw_events {
    if ev.0 != rule.rule {
      continue
    }
    let s = label_int(ev.1, "_start_tok")
    let e = label_int(ev.1, "_end_tok")
    if s < start_tok || e > end_tok {
      continue
    }
    if s == start_tok && e == end_tok {
      continue
    }
    // Direct-child check: skip if there's another event of the same
    // rule that strictly encloses this one and is itself inside the
    // parent. That intermediate event is the closer parent — `ev` is
    // its descendant, not a direct child of OUR parent.
    let mut nested = false
    for other in raw_events {
      if other.0 != rule.rule {
        continue
      }
      let os = label_int(other.1, "_start_tok")
      let oe = label_int(other.1, "_end_tok")
      // `other` strictly contains `ev` and `other` is inside the parent.
      let other_inside_parent = os >= start_tok &&
        oe <= end_tok &&
        !(os == start_tok && oe == end_tok)
      let other_strictly_contains_ev = os <= s &&
        oe >= e &&
        !(os == s && oe == e)
      if other_inside_parent && other_strictly_contains_ev {
        nested = true
        break
      }
    }
    if nested {
      continue
    }
    // Lift this child event into IR.
    let lifted = lift_event(ev, lift)
    // Pass labels through unchanged — see lower_to_code for rationale.
    let child_labels : Map[String, Json] = {}
    for entry in lifted.1 {
      child_labels.set(entry.0, entry.1)
    }
    // Apply the child's own structural rules so e.g. PropertySig.type and
    // Param.type get populated before the child template is rendered.
    // The returned effective rule may differ from `lifted.0` if a
    // conditional_lift fires; templates are looked up by that rule.
    let child_effective_rule = apply_structural_rules(
      lifted.0,
      child_labels,
      raw_events,
      lift,
      lower,
      unresolved_marker,
    )
    // Render via the target's template for the child's IR rule.
    match lower.emit_templates.get(child_effective_rule) {
      Some(child_template) => {
        let post_labels = apply_text_replace_to_labels(
          child_labels,
          lower.scalars,
          lower.text_replace(),
          lower.text_replace_pairs(),
          lower.regex_replace(),
        )
        let rendered = render_template(
          child_template, post_labels, unresolved_marker,
        )
        rendered_children.push(rendered)
      }
      None => ()
    }
  }
  // Deduplicate: KGF often emits multiple PropertySig events per field
  // (one per parse-event level). Same source token range = same field.
  // Deduplicate by exact rendered string.
  let unique : Array[String] = []
  for r in rendered_children {
    if !unique.contains(r) {
      unique.push(r)
    }
  }
  let separator = lower.collect_separators().get(rule.label).unwrap_or("")
  let joined = unique.iter().map(fn(s) { s }).collect().join(separator)
  labels.set(rule.label, Json::string(joined))
}

///|
/// Inject `default_body` into an IRFn event's `body` label when the source
/// didn't extract one. Without this, IRFn templates would render with
/// `@@UNRESOLVED@@body`, which never compiles. With it, the function
/// becomes a runnable stub.
fn inject_default_body(
  rule : String,
  labels : Map[String, Json],
  lower : LowerSpec,
) -> Unit {
  if rule != "IRFn" {
    return
  }
  let has_body = match labels.get("body") {
    Some(String(s)) => s.length() > 1
    _ => false
  }
  if has_body {
    return
  }
  match lower.default_body {
    Some(body) => labels.set("body", Json::string(body))
    None => ()
  }
}

///|
/// Apply `lower.scalars` + `lower.text_replace` substitutions to all
/// non-internal text-bearing labels, then `regex_replace` last. This
/// keeps canonical IR scalar names (`Float`, `String`, `Bool`, `Int`,
/// `Unit`) — which live in body labels after lift's scalar pass — out
/// of the final output: the lower's scalar table maps them to target
/// syntax (`Float` → `f64` for Rust, `float` for Python, `double` for
/// C / C++) automatically. Targets never need a per-source-language
/// regex like `:\s*number\b` for this; the canonical name is what the
/// scalar table is keyed on.
///
/// Internal `_*` labels and `*_raw` preserved-original twins are left
/// untouched (extract_text reads `_raw` to match suffix wraps that
/// scalar substitution would have erased).
fn apply_text_replace_to_labels(
  labels : Map[String, Json],
  scalars : Map[String, String],
  rules : Array[TextReplace],
  pair_rules : Array[TextReplacePair],
  regex_rules : Array[RegexReplace],
) -> Map[String, Json] {
  let has_scalars = !scalars.is_empty()
  if !has_scalars &&
    rules.length() == 0 &&
    pair_rules.length() == 0 &&
    regex_rules.length() == 0 {
    return labels
  }
  let out : Map[String, Json] = {}
  for entry in labels {
    let key = entry.0
    let value = entry.1
    let rewritten = if !key.has_prefix("_") && !key.has_suffix("_raw") {
      match value {
        String(s) => {
          let after_scalars = if has_scalars {
            apply_scalar_subs(s, scalars)
          } else {
            s
          }
          let after_pairs = apply_text_replace_pairs(after_scalars, pair_rules)
          let after_flat = apply_text_replace(after_pairs, rules)
          Json::string(apply_regex_replace_all(after_flat, regex_rules))
        }
        _ => value
      }
    } else {
      value
    }
    out.set(key, rewritten)
  }
  out
}

///|
/// Apply a list of `(pattern, replacement)` regex rules in order, each
/// performing a global replace across the input. Used for body-level
/// translation: stripping TS-only syntax (`: Type` annotations, `as`
/// casts) when emitting plain JavaScript / other targets.
fn apply_regex_replace_all(
  text : String,
  rules : Array[RegexReplace],
) -> String {
  let mut current = text
  for r in rules {
    current = regex_replace_one(current, r.pattern, r.replacement)
  }
  current
}

///|
/// Replace ALL non-overlapping matches of `pattern` in `text` with
/// `replacement`. The replacement may reference capture groups via
/// `$1`..`$9` (single-digit only — sufficient for spec-level body
/// translation rules). `$$` emits a literal `$`. Out-of-range groups
/// expand to empty.
fn regex_replace_one(
  text : String,
  pattern : String,
  replacement : String,
) -> String {
  let matches = @regexp.find_pattern_captures(pattern, text)
  if matches.length() == 0 {
    return text
  }
  // Splice out matches in source order.
  let buf = StringBuilder::new()
  let mut cursor = 0
  for m in matches {
    if m.start_pos < cursor {
      continue
    }
    buf.write_string(text[cursor:m.start_pos].to_owned())
    buf.write_string(expand_replacement(replacement, m.captures))
    cursor = m.end_pos
  }
  buf.write_string(text[cursor:text.length()].to_owned())
  buf.to_string()
}

///|
/// Expand `$N` (N=1..9) and `$$` references in a replacement template.
/// Anything else is emitted verbatim. Out-of-range group references
/// (e.g. `$3` when only one group was captured) emit empty.
fn expand_replacement(template : String, captures : Array[String]) -> String {
  let chars = template.to_array()
  let buf = StringBuilder::new()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '$' && i + 1 < chars.length() {
      let next = chars[i + 1]
      if next == '$' {
        buf.write_char('$')
        i = i + 2
        continue
      }
      if next >= '0' && next <= '9' {
        let group_idx = next.to_int() - '0'.to_int()
        if group_idx >= 1 && group_idx <= captures.length() {
          buf.write_string(captures[group_idx - 1])
        }
        i = i + 2
        continue
      }
    }
    buf.write_char(c)
    i = i + 1
  }
  buf.to_string()
}

///|
fn apply_text_replace(text : String, rules : Array[TextReplace]) -> String {
  let mut current = text
  for r in rules {
    current = replace_all(current, r.from, r.to)
  }
  current
}

///|
/// Pair-wise rewrite for paired delimiters. Searches for `open ... close`
/// (innermost match) and substitutes via the template.
///
/// Applied iteratively until no rule fires, so nested constructs like
/// `Array<Optional<T>>` reduce inside-out: first `Optional<T>` → `T?`,
/// then `Array<T?>` → `Array[T?]`.
fn apply_text_replace_pairs(
  text : String,
  rules : Array[TextReplacePair],
) -> String {
  if rules.length() == 0 {
    return text
  }
  let mut current = text
  let mut changed = true
  let max_iters = 16
  let mut iter = 0
  while changed && iter < max_iters {
    changed = false
    for r in rules {
      let rewritten = apply_one_pair(current, r)
      if rewritten != current {
        current = rewritten
        changed = true
      }
    }
    iter = iter + 1
  }
  current
}

///|
/// Apply one pair rule. Finds the LAST `open` that has a matching `close`
/// without another `open` in between (i.e. innermost). This makes nested
/// rewrites stable.
fn apply_one_pair(text : String, rule : TextReplacePair) -> String {
  let open_pos = find_innermost_open(text, rule.open, rule.close)
  match open_pos {
    Some(pos) => {
      let inner_start = pos + rule.open.length()
      let close_rel = find_substring(
        text[inner_start:text.length()].to_owned(),
        rule.close,
      )
      match close_rel {
        Some(rel) => {
          let inner_end = inner_start + rel
          let inner = text[inner_start:inner_end].to_owned()
          let placeholder = find_substring(rule.template, "%s")
          let replacement = match placeholder {
            Some(p) =>
              rule.template[:p].to_owned() +
              inner +
              rule.template[p + 2:rule.template.length()].to_owned()
            None => rule.template
          }
          text[:pos].to_owned() +
          replacement +
          text[inner_end + rule.close.length():text.length()].to_owned()
        }
        None => text
      }
    }
    None => text
  }
}

///|
/// Find the LAST occurrence of `open` such that the next `close` to its
/// right does not have another `open` in between. That's the innermost
/// `open ... close` pair.
fn find_innermost_open(text : String, open : String, close : String) -> Int? {
  if open.length() == 0 {
    return None
  }
  let mut best : Int? = None
  let mut i = 0
  while i + open.length() <= text.length() {
    if text[i:i + open.length()].to_owned() == open {
      // Is there a close BEFORE the next open in the remainder?
      let after = i + open.length()
      let next_open = find_substring(
        text[after:text.length()].to_owned(),
        open,
      )
      let next_close = find_substring(
        text[after:text.length()].to_owned(),
        close,
      )
      let close_first = match (next_open, next_close) {
        (Some(o), Some(c)) => c < o
        (None, Some(_)) => true
        _ => false
      }
      if close_first {
        best = Some(i)
      }
      i = i + open.length()
    } else {
      i = i + 1
    }
  }
  best
}

///|
fn replace_all(text : String, from : String, to : String) -> String {
  if from.length() == 0 {
    return text
  }
  let buf = StringBuilder::new()
  let mut i = 0
  while i < text.length() {
    if i + from.length() <= text.length() &&
      text[i:i + from.length()].to_owned() == from {
      buf.write_string(to)
      i = i + from.length()
    } else {
      buf.write_char(text.to_array()[i])
      i = i + 1
    }
  }
  buf.to_string()
}

///|
/// Two-step library-import translation:
///
/// 1. Source path (e.g. `node:fs`) lifted to a canonical category (`fs`)
///    via `lift.module_aliases`. Stored on the event as `module_canonical`.
/// 2. Canonical category lowered to a target import path (`@fs` for
///    moonbit, `std::fs` for rust) via `lower.module_aliases`. Stored
///    as `module_target`.
///
/// Templates render `{{module_target}}` to get a fully-translated import.
/// Source paths absent from `lift.module_aliases` (e.g. user's relative
/// imports like `./types.ts`) get an unresolved marker so the user can
/// see where to extend the spec.
fn apply_module_alias(
  labels : Map[String, Json],
  lift : LiftSpec,
  lower : LowerSpec,
) -> Unit {
  // The KGF emits ImportNamed events with a `from_text` label = source
  // module path. We work off that label, regardless of the lifted IR rule
  // name, so the engine doesn't have to know which IR rule corresponds
  // to imports for each language.
  let from_text = match labels.get("from_text") {
    Some(String(s)) => s
    _ => return
  }
  let lift_aliases = lift.module_aliases()
  match lift_aliases.get(from_text) {
    Some(canonical) => {
      labels.set("module_canonical", Json::string(canonical))
      let lower_aliases = lower.module_aliases()
      match lower_aliases.get(canonical) {
        Some(target) => labels.set("module_target", Json::string(target))
        // No target alias — fall back to canonical category as a comment.
        None => labels.set("module_target", Json::string(canonical))
      }
    }
    // No lift alias either — preserve the original source path so a
    // human or later pass can complete the translation. This keeps the
    // emitted code free of `@@UNRESOLVED@@` markers for routine relative
    // imports (`./types.ts`) that have no canonical category but do
    // have meaningful intent (the path itself).
    None => labels.set("module_target", Json::string(from_text))
  }
}

///|
fn label_int(labels : Map[String, Json], key : String) -> Int {
  match labels.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// Naive substring search. Returns the start index of the first occurrence
/// of `needle` in `haystack`, or `None`.
fn find_substring(haystack : String, needle : String) -> Int? {
  if needle.length() == 0 {
    return Some(0)
  }
  if needle.length() > haystack.length() {
    return None
  }
  let limit = haystack.length() - needle.length()
  let mut i = 0
  while i <= limit {
    let slice = haystack[i:i + needle.length()].to_owned()
    if slice == needle {
      return Some(i)
    }
    i = i + 1
  }
  None
}
