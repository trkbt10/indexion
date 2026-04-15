///|
/// Tokenize text into lowercase words for classification scoring.
fn tokenize_for_scoring(text : String) -> Array[String] {
  let words : Array[String] = []
  let mut buf = StringBuilder::new()
  for c in text {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') {
      let lower_c : Char = if c >= 'A' && c <= 'Z' {
        Char::from_int(c.to_int() + 32)
      } else {
        c
      }
      buf.write_char(lower_c)
    } else {
      if buf.to_string().length() >= 2 {
        words.push(buf.to_string())
      }
      buf = StringBuilder::new()
    }
  }
  if buf.to_string().length() >= 2 {
    words.push(buf.to_string())
  }
  words
}

///|
/// Classify the normative strength of a section body.
/// Returns "SHALL", "MUST", "SHOULD", or None.
/// This detects explicit normative keywords in the body text,
/// independent of any trained classification model.
fn classify_normative_strength(body : String) -> String? {
  let upper = body.to_upper()
  if upper.contains("SHALL") {
    return Some("SHALL")
  }
  if upper.contains("MUST") {
    return Some("MUST")
  }
  if upper.contains("SHOULD") {
    return Some("SHOULD")
  }
  None
}

///|
/// Extract section roles from interpreted document facts.
/// Returns a map from line number to role string.
fn section_roles_from_facts(
  interpreted : @doc_structure.InterpretedDocument,
) -> Map[Int, String] {
  let roles : Map[Int, String] = {}
  for fact in interpreted.facts {
    if fact.kind != "document_section_role" {
      continue
    }
    let line = json_int_field(fact.payload, "line")
    let role = json_string_field(fact.payload, "role").unwrap_or("")
    if line > 0 && role.length() > 0 {
      roles.set(line, role)
    }
  }
  roles
}

///|
/// Determine whether a section should be included as a requirement candidate.
///
/// Uses a three-tier classification strategy:
///
/// 1. **KGF document_section_role** (from semantics): If the spec emits
///    explicit role annotations, use them. Roles "meta", "reference",
///    "example", "appendix_code", "index" are excluded.
///
/// 2. **KGF classify model** (from `=== classify` section): If the spec
///    has a trained classification model, use it to predict the section class.
///    The predicted class determines inclusion/exclusion.
///
/// 3. **No classification data**: If neither role nor model is available,
///    include the section (no filtering).
fn should_include_section(
  role : String,
  body : String,
  model : @kgf_types.ClassifyModel?,
) -> Bool {
  // Tier 1: Explicit role from KGF semantics
  if role.length() > 0 {
    return should_include_role(role)
  }
  // Tier 2: Trained classify model
  match model {
    Some(m) => {
      if !m.is_empty() {
        let tokens = tokenize_for_scoring(body)
        match m.predict(tokens) {
          Some(predicted_class) => return should_include_role(predicted_class)
          None => ()
        }
      }
    }
    None => ()
  }
  // Tier 3: No classification data — include by default
  true
}

///|
/// Determines whether a given role/class label indicates a requirement
/// section that should be included.
///
/// This is a blacklist: known non-requirement roles are excluded.
/// Unknown roles and empty strings are included.
/// This logic is shared between document_section_role (from semantics)
/// and classify model predictions (from `=== classify`), unifying the
/// two classification paths under the same inclusion semantics.
fn should_include_role(role : String) -> Bool {
  match role {
    "meta" | "reference" | "example" | "appendix_code" | "index" => false
    _ => true
  }
}

///|
fn supports_document_interpretation(spec : @kgf_types.KGFSpec) -> Bool {
  spec.get_semantic("DocumentSection") is Some(_)
}

///|
fn is_overlay_document_spec(spec : @kgf_types.KGFSpec) -> Bool {
  match spec.get_feature("detection_scope") {
    Some(values) => values.length() > 0 && values[0] == "overlay"
    None => false
  }
}

///|
fn supported_document_specs(
  registry : @registry.KGFRegistry,
  explicit_format : String,
) -> Array[@kgf_types.KGFSpec] {
  if explicit_format != "auto" {
    match registry.get_spec(explicit_format) {
      Some(spec) => if supports_document_interpretation(spec) { return [spec] }
      None => ()
    }
    return []
  }
  let specs : Array[@kgf_types.KGFSpec] = []
  let languages = registry.get_languages()
  languages.sort()
  for language in languages {
    match registry.get_spec(language) {
      Some(spec) =>
        if supports_document_interpretation(spec) {
          specs.push(spec)
        }
      None => ()
    }
  }
  specs.sort_by(fn(a, b) {
    match (is_overlay_document_spec(a), is_overlay_document_spec(b)) {
      (true, false) => -1
      (false, true) => 1
      _ => a.get_language().compare(b.get_language())
    }
  })
  specs
}

///|
fn json_string_field(payload : Map[String, Json], key : String) -> String? {
  match payload.get(key) {
    Some(String(value)) => Some(value)
    Some(Number(value, ..)) => Some(value.to_int().to_string())
    _ => None
  }
}

///|
fn json_int_field(payload : Map[String, Json], key : String) -> Int {
  match payload.get(key) {
    Some(Number(value, ..)) => value.to_int()
    Some(String(value)) => parse_int_or_zero(value)
    _ => 0
  }
}

///|
fn parse_int_or_zero(text : String) -> Int {
  let mut value = 0
  let mut has_digit = false
  for ch in text {
    if ch >= '0' && ch <= '9' {
      value = value * 10 + (ch.to_int() - '0'.to_int())
      has_digit = true
    } else {
      return 0
    }
  }
  if has_digit {
    value
  } else {
    0
  }
}

///|
fn json_string_array_field(
  payload : Map[String, Json],
  key : String,
) -> Array[String] {
  match payload.get(key) {
    Some(Array(values)) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(text) => result.push(text)
          Number(n, ..) => result.push(n.to_int().to_string())
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn encode_table_pair(pair : @doc_structure.DocumentTablePair) -> String {
  pair.label + "\u0001" + pair.literal
}

///|
fn note_strings_by_line(
  interpreted : @doc_structure.InterpretedDocument,
  kind : String,
  key : String,
) -> Map[Int, Array[String]] {
  let result : Map[Int, Array[String]] = {}
  for fact in interpreted.facts {
    if fact.kind != kind {
      continue
    }
    let line = json_int_field(fact.payload, "line")
    if line <= 0 {
      continue
    }
    let merged = match result.get(line) {
      Some(items) => items.copy()
      None => []
    }
    for item in json_string_array_field(fact.payload, key) {
      if !merged.contains(item) {
        merged.push(item)
      }
    }
    result.set(line, merged)
  }
  result
}

///|
fn note_pairs_by_line(
  interpreted : @doc_structure.InterpretedDocument,
) -> Map[Int, Array[String]] {
  let result : Map[Int, Array[String]] = {}
  let seen : Map[Int, Bool] = {}
  for fact in interpreted.facts {
    let line = json_int_field(fact.payload, "line")
    if fact.kind != "document_table_pairs" || line <= 0 || seen.contains(line) {
      continue
    }
    seen.set(line, true)
    let items : Array[String] = []
    for pair in @doc_structure.table_pairs_for_line(interpreted, line) {
      let encoded = encode_table_pair(pair)
      if !items.contains(encoded) {
        items.push(encoded)
      }
    }
    result.set(line, items)
  }
  result
}

///|
fn load_spec_nodes(
  path : String,
  content : String,
  explicit_format : String,
  registry : @registry.KGFRegistry,
) -> (Array[RequirementNode], Array[ScenarioNode], String) {
  let specs = supported_document_specs(registry, explicit_format)
  if specs.length() == 0 {
    return ([], [], "unsupported")
  }
  for spec in specs {
    let interpreted = @doc_structure.interpret_document(content, path, spec)
    if interpreted.facts.length() == 0 {
      continue
    }
    let refs_by_line = note_strings_by_line(
      interpreted, "document_section_refs", "refs",
    )
    let literals_by_line = note_strings_by_line(
      interpreted, "document_literals", "values",
    )
    let pairs_by_line = note_pairs_by_line(interpreted)
    let source_format = spec.get_language()
    let requirements : Array[RequirementNode] = []
    let scenarios : Array[ScenarioNode] = []
    let criteria_by_requirement : Map[String, Array[String]] = {}
    for fact in interpreted.facts {
      let ty = fact.kind
      let payload = fact.payload
      if ty == "document_requirement" {
        let id = json_string_field(payload, "id").unwrap_or("")
        let title = json_string_field(payload, "title").unwrap_or("")
        if id.length() == 0 || title.length() == 0 {
          continue
        }
        requirements.push({
          id,
          title,
          description: json_string_field(payload, "description").unwrap_or(""),
          normative: json_string_field(payload, "normative"),
          source_format,
          source_file: path,
          source_start_line: json_int_field(payload, "line"),
          source_end_line: json_int_field(payload, "end_line"),
          criteria: [],
          section_refs: refs_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
          literals: literals_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
          table_pairs: pairs_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
        })
      } else if ty == "document_scenario" {
        let parent_id = json_string_field(payload, "parent_id").unwrap_or("")
        if parent_id.length() == 0 {
          continue
        }
        scenarios.push({
          id: parent_id + "::SCN-" + (scenarios.length() + 1).to_string(),
          title: json_string_field(payload, "title").unwrap_or("Scenario"),
          given: json_string_array_field(payload, "given"),
          when_: json_string_array_field(payload, "when"),
          then_: json_string_array_field(payload, "then"),
          parent_req: parent_id,
          source_file: path,
          source_start_line: json_int_field(payload, "line"),
          source_end_line: json_int_field(payload, "end_line"),
          section_refs: refs_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
          literals: literals_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
          table_pairs: pairs_by_line
          .get(json_int_field(payload, "line"))
          .unwrap_or([]),
        })
      } else if ty == "document_requirement_criteria" {
        let parent_id = json_string_field(payload, "parent_id").unwrap_or("")
        if parent_id.length() == 0 {
          continue
        }
        let merged = match criteria_by_requirement.get(parent_id) {
          Some(existing) => existing.copy()
          None => []
        }
        for item in json_string_array_field(payload, "criteria") {
          merged.push(item)
        }
        criteria_by_requirement.set(parent_id, merged)
      }
    }
    if requirements.length() > 0 {
      let finalized : Array[RequirementNode] = []
      for requirement in requirements {
        let criteria = match criteria_by_requirement.get(requirement.id) {
          Some(items) => items.copy()
          None => []
        }
        finalized.push({ ..requirement, criteria, })
      }
      return (finalized, scenarios, source_format)
    }
    // Fallback: no document_requirement facts found, but DocumentSections
    // were parsed successfully. Classify sections using:
    //   1. document_section_role from KGF semantics
    //   2. trained classify model from KGF === classify section
    //   3. no filtering (include all sections)
    let sections = @doc_structure.load_document_sections(
      content,
      path,
      Some(registry),
    )
    if sections.length() > 0 {
      let roles = section_roles_from_facts(interpreted)
      let classify_model = spec.get_classify()
      let fallback : Array[RequirementNode] = []
      for section in sections {
        let title = section.title.trim().to_string()
        if title.length() == 0 {
          continue
        }
        let body = section.content
        let line = section.line
        let role = roles.get(line).unwrap_or("")
        if !should_include_section(role, body, classify_model) {
          continue
        }
        let normative = classify_normative_strength(body)
        let id = "SEC-" + line.to_string()
        fallback.push({
          id,
          title,
          description: body,
          normative,
          source_format: source_format,
          source_file: path,
          source_start_line: line,
          source_end_line: section.end_line,
          criteria: [],
          section_refs: refs_by_line.get(line).unwrap_or([]),
          literals: literals_by_line.get(line).unwrap_or([]),
          table_pairs: pairs_by_line.get(line).unwrap_or([]),
        })
      }
      if fallback.length() > 0 {
        return (fallback, scenarios, source_format)
      }
    }
  }
  ([], [], "unsupported")
}
