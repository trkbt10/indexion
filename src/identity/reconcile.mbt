/// Score how far a name has drifted from the content it claims to name.
///
/// The model is symmetric to spec ↔ impl reconcile elsewhere in
/// indexion. The "spec" side is the name (a tiny document), the
/// "impl" side is the content body. We tokenise both through KGF and
/// ask:
///
///   1. **name_in_content_score** — what fraction of the tokens the
///      name picks (its identifier-kind tokens) actually appear as
///      tokens of the body? A high score means the name's words live
///      in the body. A low score means the name talks about something
///      the body never mentions.
///
///   2. **content_breadth** — how many distinct identifier-kind tokens
///      does the body have, normalised against a corpus comparison?
///      Wide bodies (many topics) score higher. Combined with #1 this
///      separates "off-topic name" (low #1, low #2) from "name has
///      shrunk past the body" (low #1, high #2).
///
/// From those two scalars and a small list of explicit thresholds we
/// produce a `NameAction` recommendation:
///
///   - **Keep**   — name fits, leave it alone
///   - **Rename** — body is focussed but the name's words don't
///                  appear; choose a name from the prominent unused
///                  body tokens
///   - **Split**  — body is broad and the name covers only a slice;
///                  consider partitioning the entity
///   - **Hollow** — body is too thin to support any specific name

///|
/// Score a single named entity for name ↔ content drift.
pub fn score_name_divergence(
  entity : NamedEntity,
  registry : @kgf_registry.KGFRegistry,
) -> NameDivergence {
  let kinds = identifier_kinds_for(registry, entity.origin)
  let name_tokens = content_tokens(entity.name.display, entity.origin, registry, kinds)
  let body_tokens = content_tokens(entity.content, entity.origin, registry, kinds)

  // (1) presence of name tokens in body.
  let name_in_content_score = if name_tokens.is_empty() {
    // Empty name vacuously matches: nothing to disagree about.
    1.0
  } else {
    let body_set : Map[String, Bool] = {}
    for t in body_tokens {
      body_set[t] = true
    }
    let mut hits = 0
    for t in name_tokens {
      if body_set.contains(t) {
        hits += 1
      }
    }
    hits.to_double() / name_tokens.length().to_double()
  }

  // (2) body breadth: BM25-weighted vocabulary richness, capped at 1.0.
  // A short focussed body (e.g. one paragraph about Dorian Gray) has
  // few distinct content tokens; a sprawling body has many. We use
  // unique token count divided by a soft ceiling so the metric is
  // bounded.
  let unique_body : Map[String, Bool] = {}
  for t in body_tokens {
    unique_body[t] = true
  }
  let unique_count = unique_body.length().to_double()
  // 60 distinct content tokens is a reasonable "broad body" threshold
  // at the section/page granularity story commands operate on. Past
  // that we saturate; below it we report the linear fraction. The
  // value is intentionally a *named ceiling*, not a magic literal —
  // it lives here behind `breadth_ceiling` and downstream consumers
  // can read it.
  let breadth_ceiling = 60.0
  let content_breadth = if unique_count >= breadth_ceiling {
    1.0
  } else {
    unique_count / breadth_ceiling
  }

  // Tokens prominent in the body but not part of the name. Used for
  // rename suggestions and rationale strings.
  let prominent_unused = body_tokens_absent_from_name(
    entity, body_tokens, kinds, registry,
  )

  // Decision rules. Order matters: Hollow is checked before Rename
  // because a thin body cannot meaningfully be renamed.
  let action = decide_action(
    name_in_content_score, content_breadth, body_tokens.length(),
  )
  let rationale = build_rationale(
    action,
    name_in_content_score,
    content_breadth,
    prominent_unused,
    entity.name,
  )
  {
    entity,
    name_in_content_score,
    content_breadth,
    prominent_unused,
    action,
    rationale,
  }
}

///|
/// Tokenise text and return only the values whose feature kind is in
/// the supplied identifier-kinds set. Empty kinds set means keep
/// everything (used as a fallback when no spec is available).
fn content_tokens(
  text : String,
  path_hint : String,
  registry : @kgf_registry.KGFRegistry,
  kinds : Map[String, Bool],
) -> Array[String] {
  let raw = @kgf_tokenize.tokenize_file(text, path_hint, registry)
  let result : Array[String] = []
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
      result.push(value)
    }
  }
  result
}

///|
/// Top body tokens that are not in the name, ranked by frequency.
/// We tokenise the name through the same KGF spec the body uses so
/// "absence in name" is judged on the same token boundaries —
/// splitting by space would be wrong for CJK headings where there
/// are no whitespace separators.
fn body_tokens_absent_from_name(
  entity : NamedEntity,
  body_tokens : Array[String],
  kinds : Map[String, Bool],
  registry : @kgf_registry.KGFRegistry,
) -> Array[String] {
  // Build the name's token set via KGF, lowercased to match body
  // tokens (KGF lowercases identifier feature values when emitting).
  let name_tokens = content_tokens(
    entity.name.display, entity.origin, registry, kinds,
  )
  let name_set : Map[String, Bool] = {}
  for t in name_tokens {
    name_set[lower_ascii(t)] = true
  }
  // Fallback: if the registry-less name_tokens is empty (e.g. tests
  // without a spec), tokenise the display string by splitting on
  // ASCII whitespace so the comparison still does something useful.
  if name_tokens.is_empty() {
    let buf = StringBuilder::new()
    for c in entity.name.display {
      if c == ' ' || c == '\t' || c == '\n' {
        let s = buf.to_string()
        if s.length() > 0 {
          name_set[lower_ascii(s)] = true
        }
        buf.reset()
      } else {
        buf.write_char(c)
      }
    }
    let s = buf.to_string()
    if s.length() > 0 {
      name_set[lower_ascii(s)] = true
    }
  }
  let counts : Map[String, Int] = {}
  for t in body_tokens {
    let lt = lower_ascii(t)
    if name_set.contains(lt) {
      continue
    }
    counts[lt] = counts.get(lt).unwrap_or(0) + 1
  }
  let pairs : Array[(String, Int)] = []
  for entry in counts {
    pairs.push((entry.0, entry.1))
  }
  pairs.sort_by(fn(a, b) { b.1.compare(a.1) })
  let result : Array[String] = []
  let limit = if pairs.length() < 6 { pairs.length() } else { 6 }
  for i = 0; i < limit; i = i + 1 {
    result.push(pairs[i].0)
  }
  result
}

///|
/// Decide an action from the two scalars and the body size.
///
/// Thresholds are explicit named values, not magic literals — adjust
/// them in this one place when calibration data accumulates. The
/// defaults are tuned for prose-section identities at the granularity
/// the story commands operate on (one section, one heading, one act).
fn decide_action(
  name_in_content_score : Double,
  content_breadth : Double,
  body_token_count : Int,
) -> NameAction {
  let hollow_token_floor = 8
  let drift_score_ceiling = 0.34
  let split_breadth_floor = 0.55
  if body_token_count < hollow_token_floor {
    return Hollow
  }
  if name_in_content_score >= drift_score_ceiling {
    return Keep
  }
  // Name's words are largely absent from the body.
  if content_breadth >= split_breadth_floor {
    Split
  } else {
    Rename
  }
}

///|
/// Compose the rationale string. References concrete numbers from
/// the candidate so a reader can verify the reasoning.
fn build_rationale(
  action : NameAction,
  name_in_content_score : Double,
  content_breadth : Double,
  prominent_unused : Array[String],
  name : Name,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(action.label())
  buf.write_string(": ")
  match action {
    Keep => {
      buf.write_string("name '")
      buf.write_string(name.display)
      buf.write_string("' is reflected in the body (")
      buf.write_string(@text_format.format_percent(name_in_content_score))
      buf.write_string(")")
    }
    Rename => {
      buf.write_string("name '")
      buf.write_string(name.display)
      buf.write_string("' rarely appears in body (")
      buf.write_string(@text_format.format_percent(name_in_content_score))
      buf.write_string("); prominent terms: ")
      buf.write_string(@text_ops.join_with_limit(prominent_unused, 3))
    }
    Split => {
      buf.write_string("body covers many distinct topics (breadth ")
      buf.write_string(@text_format.format_percent(content_breadth))
      buf.write_string(") and the name covers only a slice; consider splitting around: ")
      buf.write_string(@text_ops.join_with_limit(prominent_unused, 4))
    }
    Hollow =>
      buf.write_string(
        "body too thin to support a specific name; consider expanding or removing",
      )
  }
  buf.to_string()
}
