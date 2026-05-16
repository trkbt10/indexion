///|
/// File-level transpile entry: parse `file_path` with the source KGF spec,
/// auto-detect the source language, load `<source>.json` for lift and
/// `<target>.json` for lower, then run lift_events + lower_to_code.
///
/// Returns `None` when the source can't be detected, either spec is missing,
/// or the parse fails. Returns a JSON envelope with `source_lang`,
/// `target_lang`, `ir_events`, and `code`.
pub fn transpile_file_json(
  file_path : String,
  target_lang : String,
  kgf_dir : String,
) -> String? {
  let registry = load_registry(kgf_dir)
  let source_lang = match registry.detect_from_path(file_path) {
    Some(s) => s
    None => return None
  }
  // Source spec must declare a lift section.
  let source_spec = match find_spec(source_lang) {
    Some(s) => s
    None => return None
  }
  let lift = match source_spec.lift {
    Some(l) => l
    None => return None
  }
  // Target spec must declare a lower section.
  let target_spec = match find_spec(target_lang) {
    Some(s) => s
    None => return None
  }
  let lower = match target_spec.lower {
    Some(l) => l
    None => return None
  }
  let kgf_spec = match registry.get_spec(source_lang) {
    Some(s) => s
    None => return None
  }
  let source_text = @fs.read_file_to_string(file_path) catch {
    _ => return None
  }
  let source = if source_text.has_suffix("\n") {
    source_text
  } else {
    source_text + "\n"
  }
  let lex = @lexer.Lexer::new(kgf_spec.get_tokens())
  let tokens = lex.tokenize(source)
  let peg = @peg.build_peg(kgf_spec) catch { _ => return None }
  let start_rule = kgf_spec.get_start_rule()
  match @peg.run_parse(peg, kgf_spec, start_rule, tokens) {
    Some(eval_result) => {
      let raw_events = eval_result.get_events()
      // KGF lexers SKIP whitespace, so the `body_text` label on
      // FunctionDecl events is whitespace-stripped (`const todo` →
      // `consttodo`). For verbatim body emission we must re-slice the
      // original source using the function's source-position labels.
      // Inject `body_text_raw` into each FunctionDecl-class event.
      // Body extraction is gated on the source spec declaring its body
      // delimiters. Without delimiters declared (Python and other
      // indent-based languages), the driver does not look at brace chars
      // at all — body content travels through the regular `body_text`
      // label produced by KGF.
      let body_delims = lift.body_delimiter_chars()
      let events : Array[(String, Map[String, Json])] = []
      for ev in raw_events {
        let mut new_labels = ev.1
        match body_delims {
          Some((open_ch, close_ch)) =>
            if has_body_pos(ev.0, ev.1) {
              let slice = extract_body_from_source(
                source,
                ev.1,
                open_ch,
                close_ch,
              )
              if slice.length() > 0 {
                new_labels = enrich_with_raw_body(
                  ev.1,
                  slice,
                  open_ch,
                  close_ch,
                )
              }
            }
          None => ()
        }
        events.push((ev.0, new_labels))
      }
      // Phase 1: lift KGF events to canonical IR events.
      let ir_events = lift_events(events, lift)
      // Phase 2: lower IR events to target code.
      // The lower pass also applies the lift's structural_rules using the
      // RAW events for sibling/inner lookups. Use the *source* spec's
      // unresolved marker if set; both default to @@UNRESOLVED@@.
      let unresolved_marker = source_spec.unresolved_marker()
      let code = lower_to_code(
        ir_events, events, source_lang, target_lang, unresolved_marker, lift, lower,
      )
      // Build response envelope.
      let ir_events_json : Array[Json] = ir_events
        .iter()
        .map(fn(ev) {
          let obj : Map[String, Json] = {}
          obj.set("rule", ev.0.to_json())
          obj.set("labels", Json::object(ev.1))
          Json::object(obj)
        })
        .collect()
      let root : Map[String, Json] = {}
      root.set("source_lang", source_lang.to_json())
      root.set("target_lang", target_lang.to_json())
      root.set("source_file", file_path.to_json())
      root.set("event_count", events.length().to_json())
      root.set("ir_events", Json::array(ir_events_json))
      root.set("code", code.to_json())
      Some(Json::object(root).stringify())
    }
    None => None
  }
}

///|
/// True for events that carry a `body_pos` label (KGF's per-language
/// convention puts the closing-delimiter position there). The set of
/// rules that have function bodies varies by language, so we look at
/// the label, not at the rule name.
fn has_body_pos(rule : String, labels : Map[String, Json]) -> Bool {
  ignore(rule)
  match labels.get("body_pos") {
    Some(Number(_, ..)) => true
    _ => false
  }
}

///|
/// Slice the original source between the opening delimiter (matched by
/// balanced search back from `body_pos`) and the closing delimiter at
/// `body_pos + body_len`. The delimiter pair (`open_ch`, `close_ch`)
/// comes from the source spec — the driver carries no language-specific
/// delimiter knowledge of its own.
///
/// Returns "" when balancing fails.
fn extract_body_from_source(
  source : String,
  labels : Map[String, Json],
  open_ch : Char,
  close_ch : Char,
) -> String {
  let body_close_pos = match labels.get("body_pos") {
    Some(Number(n, ..)) => n.to_int()
    _ => return ""
  }
  let body_close_len = match labels.get("body_len") {
    Some(Number(n, ..)) => n.to_int()
    _ => 1
  }
  // body_close_pos is the position of the closing-delimiter token. Walk
  // backwards counting delimiters so that nested pairs inside the body
  // don't fool us.
  let chars = source.to_array()
  let mut depth = 1
  let mut i = body_close_pos - 1
  while i >= 0 {
    let c = chars[i]
    if c == close_ch {
      depth = depth + 1
    } else if c == open_ch {
      depth = depth - 1
      if depth == 0 {
        return source[i:body_close_pos + body_close_len].to_owned()
      }
    }
    i = i - 1
  }
  ""
}

///|
/// Set `body_text` to the verbatim source slice (delimiters included)
/// and `body_inner_text` to the same slice with the outer delimiter pair
/// stripped. Both labels are simple slices — no language-specific
/// interpretation. The delimiter pair is provided by the caller, sourced
/// from `lift.body_delimiters`.
///
/// Both labels end in `_text`, so the standard lift pipeline picks them
/// up: scalar substitution runs (`number` → `Float` etc.), the original
/// is preserved as `*_text_raw`, and the lift's `regex_replace` rules
/// fire — letting the source spec strip its own syntax (TS `===`,
/// template-literal backticks, etc.) before any target sees the body.
fn enrich_with_raw_body(
  labels : Map[String, Json],
  raw : String,
  open_ch : Char,
  close_ch : Char,
) -> Map[String, Json] {
  let out : Map[String, Json] = {}
  for entry in labels {
    out.set(entry.0, entry.1)
  }
  out.set("body_text", Json::string(raw))
  let inner = if raw.length() >= 2 &&
    raw.to_array()[0] == open_ch &&
    raw.to_array()[raw.length() - 1] == close_ch {
    raw[1:raw.length() - 1].to_owned()
  } else {
    raw
  }
  out.set("body_inner_text", Json::string(inner))
  out
}

///|
/// Mirror `cmd/indexion/kgf/cli.mbt`'s registry-loader.
fn load_registry(kgf_dir : String) -> @registry.KGFRegistry {
  let explicit = if kgf_dir != "kgfs" { kgf_dir } else { "" }
  match @config.find_kgfs_dir(explicit_path=explicit) {
    Some(dir) => @registry.KGFRegistry::load_from_dir(dir)
    None => @registry.KGFRegistry::new()
  }
}
