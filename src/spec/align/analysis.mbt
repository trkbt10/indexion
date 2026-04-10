///|
fn current_epoch_seconds() -> Int {
  (@env.now() / 1000UL).to_int()
}

///|
fn trim(text : String) -> String {
  @common.trim_ascii_spaces(text)
}

///|
fn lower_ascii(text : String) -> String {
  @kgf_features.to_lower_str(text)
}

///|
fn config_hash(config : SpecAlignConfig) -> String {
  let joined = [
    config.spec_path,
    config.impl_path,
    config.spec_format,
    config.algorithm,
    config.threshold.to_string(),
  ].join("\u0001")
  @cas_hash.compute_hash(joined).to_string()
}

///|
let project_root_markers : Array[String] = [
  ".git", ".indexion", ".indexion.toml", ".indexion.json",
]

///|
fn file_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
fn path_is_dir(path : String) -> Bool {
  @fs.is_dir(path) catch {
    err => {
      println(
        "Error: failed to inspect path `" + path + "`: " + err.to_string(),
      )
      false
    }
  }
}

///|
fn discover_spec_files(
  spec_path : String,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  if spec_path.length() == 0 || !file_exists(spec_path) {
    return []
  }
  let result : Array[String] = []
  if !path_is_dir(spec_path) {
    for file in @pipeline.load_supported_file_info([spec_path], registry) {
      if file.content_type == Some("document") {
        result.push(file.path)
      }
    }
    result.sort()
    return result
  }
  let discovered = @pipeline.collect_supported_file_info(
    [spec_path],
    @pipeline.DiscoverOptions::new(),
    registry,
  )
  for file in discovered {
    if file.content_type == Some("document") {
      result.push(file.path)
    }
  }
  result.sort()
  result
}

///|
fn discover_impl_files(
  impl_path : String,
  registry : @registry.KGFRegistry,
) -> Array[String] {
  if impl_path.length() == 0 || !file_exists(impl_path) {
    return []
  }
  let result : Array[String] = []
  if !path_is_dir(impl_path) {
    for file in @pipeline.load_supported_file_info([impl_path], registry) {
      if file.content_type is None {
        result.push(file.path)
      }
    }
    result.sort()
    return result
  }
  let kgf_ignore = registry.collect_ignore_patterns()
  let discovered = @pipeline.collect_supported_file_info(
    [impl_path],
    @pipeline.DiscoverOptions::new(kgf_ignore~),
    registry,
  )
  for file in discovered {
    if file.content_type is None {
      result.push(file.path)
    }
  }
  result.sort()
  result
}

///|
fn tracking_root(config : SpecAlignConfig) -> String {
  let anchor = if config.impl_path.length() > 0 {
    config.impl_path
  } else {
    config.spec_path
  }
  let start = if path_is_dir(anchor) { anchor } else { @config.dirname(anchor) }
  match @config.find_project_root(start, project_root_markers) {
    Some(root) => root
    None => start
  }
}

///|
fn requirement_excerpt(requirement : RequirementNode) -> String {
  if requirement.description.length() > 0 {
    requirement.description
  } else if requirement.criteria.length() > 0 {
    requirement.criteria[0]
  } else {
    requirement.title
  }
}

///|
fn implementation_excerpt(implementation : ImplementationNode) -> String {
  if implementation.declaration_text.length() > 0 {
    implementation.declaration_text
  } else if implementation.signature.length() > 0 {
    implementation.signature
  } else {
    implementation.name
  }
}

///|
async fn collect_spec_data(
  config : SpecAlignConfig,
  registry : @registry.KGFRegistry,
) -> (
  Array[RequirementNode],
  Array[ScenarioNode],
  Array[String],
  Map[String, String],
  Array[@reconcile_tracking.FileState],
) {
  let requirements : Array[RequirementNode] = []
  let scenarios : Array[ScenarioNode] = []
  let used_specs : Array[String] = []
  let file_hashes : Map[String, String] = {}
  let file_states : Array[@reconcile_tracking.FileState] = []
  let spec_files = discover_spec_files(config.spec_path, registry)
  let root = tracking_root(config)
  let tracking_config = @reconcile_tracking.FileTrackingConfig::new(true, true)
  for path in spec_files {
    let content = @fs.read_file_to_string(path) catch {
      err => {
        println(
          "Error: failed to read spec file `" + path + "`: " + err.to_string(),
        )
        return ([], [], [], {}, [])
      }
    }
    let (reqs, scns, used_spec) = load_spec_nodes(
      path,
      content,
      config.spec_format,
      registry,
    )
    for requirement in reqs {
      requirements.push(requirement)
    }
    for scenario in scns {
      scenarios.push(scenario)
    }
    if used_spec != "unsupported" && !used_specs.contains(used_spec) {
      used_specs.push(used_spec)
    }
    let content_hash = @cas_hash.compute_hash(content).to_string()
    file_hashes.set(path, content_hash)
    let ts = @reconcile_tracking.timestamp_for_path(root, path, tracking_config)
    file_states.push(
      @reconcile_tracking.FileState::new(
        path,
        "spec",
        used_spec,
        content_hash,
        ts.epoch_seconds,
        @git.file_mtime_seconds(path),
        ts.is_dirty,
      ),
    )
  }
  (requirements, scenarios, used_specs, file_hashes, file_states)
}

///|
fn safe_line(content : String, line_no : Int) -> String {
  let lines = @common.split_lines(content)
  if line_no <= 0 || line_no > lines.length() {
    return ""
  }
  trim(lines[line_no - 1])
}

///|
fn append_implementation_node(
  implementations : Array[ImplementationNode],
  content : String,
  path : String,
  kind : String,
  name : String,
  line : Int,
  start_pos : Int,
  source_end_pos : Int,
  end_line : Int,
  doc_map : Map[Int, String],
) -> Unit {
  if trim(name).length() == 0 {
    return
  }
  let declaration_line = line
  let signature = safe_line(content, declaration_line)
  let span_text = if start_pos >= 0 &&
    source_end_pos > start_pos &&
    source_end_pos <= content.length() {
    trim(content[start_pos:source_end_pos].to_string())
  } else {
    ""
  }
  let declaration_text = if span_text.length() > 0 {
    span_text
  } else {
    signature
  }
  let doc_comment = match doc_map.get(declaration_line) {
    Some(value) => Some(value)
    None => doc_map.get(line)
  }
  implementations.push({
    id: path + "::" + name,
    name,
    kind,
    file: path,
    start_line: declaration_line,
    end_line: if end_line >= declaration_line {
      end_line
    } else {
      declaration_line
    },
    signature,
    declaration_text,
    doc_comment,
  })
}

///|
async fn collect_impl_data(
  config : SpecAlignConfig,
  registry : @registry.KGFRegistry,
) -> (
  Array[ImplementationNode],
  Array[String],
  Map[String, String],
  Map[String, String],
  Array[@reconcile_tracking.FileState],
) {
  let implementations : Array[ImplementationNode] = []
  let used_specs : Array[String] = []
  let file_hashes : Map[String, String] = {}
  let file_contents : Map[String, String] = {}
  let file_states : Array[@reconcile_tracking.FileState] = []
  let impl_files = discover_impl_files(config.impl_path, registry)
  let root = tracking_root(config)
  let tracking_config = @reconcile_tracking.FileTrackingConfig::new(true, true)
  for path in impl_files {
    let content = @fs.read_file_to_string(path) catch {
      err => {
        println(
          "Error: failed to read implementation file `" +
          path +
          "`: " +
          err.to_string(),
        )
        return ([], [], {}, {}, [])
      }
    }
    file_contents.set(path, content)
    let content_hash = @cas_hash.compute_hash(content).to_string()
    file_hashes.set(path, content_hash)
    let detected_spec = match registry.detect_from_path(path) {
      Some(name) => {
        if !used_specs.contains(name) {
          used_specs.push(name)
        }
        name
      }
      None => "code"
    }
    let ts = @reconcile_tracking.timestamp_for_path(root, path, tracking_config)
    file_states.push(
      @reconcile_tracking.FileState::new(
        path,
        "impl",
        detected_spec,
        content_hash,
        ts.epoch_seconds,
        @git.file_mtime_seconds(path),
        ts.is_dirty,
      ),
    )
    let (kgf_declarations, doc_map) = @kgf_declarations.extract_pub_declarations_and_doc_map(
      content,
      path,
      Some(registry),
    )
    let seen : Map[String, Bool] = {}
    for declaration in kgf_declarations {
      let key = declaration.name + "@" + declaration.line.to_string()
      if seen.contains(key) {
        continue
      }
      seen.set(key, true)
      append_implementation_node(
        implementations,
        content,
        path,
        declaration.kind,
        declaration.name,
        declaration.line,
        declaration.start_pos,
        declaration.end_pos,
        declaration.end_line,
        doc_map,
      )
    }
  }
  // Note: file-level implementation nodes were considered but removed.
  // Their broad vocabulary caused false matches in the primary scoring pass.
  // Instead, spec verify's gap terms drive codex to justify each missing concept.
  (implementations, used_specs, file_hashes, file_contents, file_states)
}

///|
fn requirement_text(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(requirement.title)
  buf.write_string("\n")
  buf.write_string(requirement.description)
  buf.write_string("\n")
  for criterion in requirement.criteria {
    buf.write_string(criterion)
    buf.write_string("\n")
  }
  for scenario in scenarios {
    if scenario.parent_req != requirement.id {
      continue
    }
    for item in scenario.given {
      buf.write_string(item)
      buf.write_string("\n")
    }
    for item in scenario.when_ {
      buf.write_string(item)
      buf.write_string("\n")
    }
    for item in scenario.then_ {
      buf.write_string(item)
      buf.write_string("\n")
    }
  }
  buf.to_string()
}

///|
fn merge_unique_strings(target : Array[String], values : Array[String]) -> Unit {
  for value in values {
    if value.length() > 0 && !target.contains(value) {
      target.push(value)
    }
  }
}

///|
fn requirement_section_refs(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
) -> Array[String] {
  let refs = requirement.section_refs.copy()
  for scenario in scenarios {
    if scenario.parent_req != requirement.id {
      continue
    }
    merge_unique_strings(refs, scenario.section_refs)
  }
  refs
}

///|
fn requirement_literals(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
) -> Array[String] {
  let values = requirement.literals.copy()
  for scenario in scenarios {
    if scenario.parent_req != requirement.id {
      continue
    }
    merge_unique_strings(values, scenario.literals)
  }
  values
}

///|
fn requirement_table_pairs(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
) -> Array[String] {
  let pairs = requirement.table_pairs.copy()
  for scenario in scenarios {
    if scenario.parent_req != requirement.id {
      continue
    }
    merge_unique_strings(pairs, scenario.table_pairs)
  }
  pairs
}

///|
fn is_section_ref_char(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') || ch == '.'
}

///|
fn normalize_section_ref(token : String) -> String {
  let chars = token.to_array()
  if chars.length() == 0 {
    return ""
  }
  let end_ = if chars[chars.length() - 1] == '.' {
    chars.length() - 1
  } else {
    chars.length()
  }
  if end_ <= 0 {
    return ""
  }
  String::from_array(chars[:end_])
}

///|
fn is_section_ref_token(token : String) -> Bool {
  let normalized = normalize_section_ref(token)
  let chars = normalized.to_array()
  if chars.length() == 0 {
    return false
  }
  let mut has_digit = false
  for ch in chars {
    if ch >= '0' && ch <= '9' {
      has_digit = true
      continue
    }
    if ch != '.' {
      return false
    }
  }
  has_digit
}

///|
fn tokenize_section_words(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let current : Array[Char] = []

  fn flush(tokens : Array[String], current : Array[Char]) -> Unit {
    if current.length() == 0 {
      return
    }
    tokens.push(String::from_array(current))
    current.clear()
  }

  for ch in text.to_array() {
    if is_section_ref_char(ch) ||
      (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') {
      current.push(ch)
    } else {
      flush(tokens, current)
    }
  }
  flush(tokens, current)
  tokens
}

///|
fn collect_section_refs(text : String) -> Array[String] {
  let refs : Array[String] = []
  let tokens = tokenize_section_words(lower_ascii(text))
  let mut capture = false
  for token in tokens {
    if token == "section" || token == "sections" {
      capture = true
      continue
    }
    if !capture {
      continue
    }
    let normalized = normalize_section_ref(token)
    if is_section_ref_token(normalized) {
      if !refs.contains(normalized) {
        refs.push(normalized)
      }
      continue
    }
    if token == "and" || token == "or" {
      continue
    }
    capture = false
  }
  refs
}

///|
fn is_parent_section_ref(parent : String, child : String) -> Bool {
  child.length() > parent.length() &&
  child.has_prefix(parent) &&
  child.to_array()[parent.length()] == '.'
}

///|
fn section_reference_score(
  required_refs : Array[String],
  candidate_text : String,
) -> Double {
  let candidate_refs = collect_section_refs(candidate_text)
  if required_refs.length() == 0 || candidate_refs.length() == 0 {
    return 0.0
  }
  let mut has_exact = false
  let mut has_related = false
  for req_ref in required_refs {
    for candidate_ref in candidate_refs {
      if req_ref == candidate_ref {
        has_exact = true
      } else if is_parent_section_ref(req_ref, candidate_ref) ||
        is_parent_section_ref(candidate_ref, req_ref) {
        has_related = true
      }
    }
  }
  if has_exact {
    0.45
  } else if has_related {
    0.24
  } else {
    0.0
  }
}

///|
fn decimal_to_hex(value : String) -> String? {
  let n = @common.parse_int(value)
  if n < 0 {
    return None
  }
  if n == 0 {
    return Some("0x0")
  }
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let chars : Array[Char] = []
  let mut current = n
  while current > 0 {
    chars.push(digits[current % 16])
    current = current / 16
  }
  let buf = StringBuilder::new()
  for i = chars.length() - 1; i >= 0; i = i - 1 {
    buf.write_char(chars[i])
  }
  Some("0x" + buf.to_string())
}

///|
fn literals_from_text(text : String) -> Array[String] {
  let values : Array[String] = []
  let numeric : Array[Char] = []
  let quoted : Array[Char] = []
  let mut in_backtick = false

  fn flush_numeric(values : Array[String], numeric : Array[Char]) -> Unit {
    if numeric.length() >= 2 {
      let value = String::from_array(numeric)
      if !values.contains(value) {
        values.push(value)
      }
    }
    numeric.clear()
  }

  fn flush_quoted(values : Array[String], quoted : Array[Char]) -> Unit {
    if quoted.length() > 0 {
      let value = String::from_array(quoted)
      if !values.contains(value) {
        values.push(value)
      }
    }
    quoted.clear()
  }

  for ch in text.to_array() {
    if ch == '`' {
      if in_backtick {
        flush_quoted(values, quoted)
      }
      in_backtick = !in_backtick
      flush_numeric(values, numeric)
      continue
    }
    if in_backtick {
      quoted.push(ch)
      continue
    }
    if ch >= '0' && ch <= '9' {
      numeric.push(ch)
    } else {
      flush_numeric(values, numeric)
    }
  }
  flush_numeric(values, numeric)
  flush_quoted(values, quoted)
  values
}

///|
fn literal_present(text : String, literal : String) -> Bool {
  if text.contains(literal) {
    return true
  }
  let lowered = lower_ascii(text)
  if lowered.contains(lower_ascii(literal)) {
    return true
  }
  match decimal_to_hex(literal) {
    Some(hex) => lowered.contains(hex)
    None => false
  }
}

///|
fn literal_overlap_score(
  required_literals : Array[String],
  candidate_text : String,
) -> Double {
  if required_literals.length() == 0 {
    return 0.0
  }
  let mut matched = 0
  for literal in required_literals {
    if literal.length() > 0 && literal_present(candidate_text, literal) {
      matched += 1
    }
  }
  if matched < 2 {
    0.0
  } else {
    clamp_similarity(
      matched.to_double() / required_literals.length().to_double(),
    )
  }
}

///|
fn decode_table_pair(pair : String) -> (String, String) {
  match pair.split_once("\u0001") {
    Some((label, literal)) => (label.to_string(), literal.to_string())
    None => (pair, "")
  }
}

///|
fn identifier_tokens(text : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []

  fn flush(result : Array[String], current : Array[Char]) -> Unit {
    if current.length() == 0 {
      return
    }
    let token = String::from_array(current)
    if token.length() > 1 && !result.contains(token) {
      result.push(token)
    }
    current.clear()
  }

  for ch in text.to_array() {
    let is_head = (ch >= 'A' && ch <= 'Z') ||
      (ch >= 'a' && ch <= 'z') ||
      ch == '_'
    let is_tail = is_head || (ch >= '0' && ch <= '9')
    if current.length() == 0 {
      if is_head {
        current.push(ch)
      }
    } else if is_tail {
      current.push(ch)
    } else {
      flush(result, current)
    }
  }
  flush(result, current)
  result
}

///|
fn identifier_candidates_from_line(
  line : String,
  label : String,
) -> Array[String] {
  let candidates : Array[String] = []
  let upper_label = lower_ascii(label)
  for token in identifier_tokens(line) {
    let lowered = lower_ascii(token)
    if lowered == upper_label ||
      lowered.contains("_" + upper_label) ||
      lowered.has_suffix(upper_label) {
      candidates.push(token)
    }
  }
  candidates
}

///|
fn pair_present_in_text(
  evidence : String,
  label : String,
  literal : String,
) -> Bool {
  let lines = @common.split_lines(evidence)
  for line in lines {
    let trimmed = trim(line)
    if trimmed.contains(label) && literal_present(trimmed, literal) {
      return true
    }
  }
  let identifiers : Array[String] = []
  for line in lines {
    let trimmed = trim(line)
    if !trimmed.contains(label) {
      continue
    }
    for candidate in identifier_candidates_from_line(trimmed, label) {
      if !identifiers.contains(candidate) {
        identifiers.push(candidate)
      }
    }
  }
  for identifier in identifiers {
    for line in lines {
      let trimmed = trim(line)
      if trimmed.contains(identifier) && literal_present(trimmed, literal) {
        return true
      }
    }
  }
  false
}

///|
fn table_pair_overlap_score(
  required_pairs : Array[String],
  candidate_text : String,
) -> Double {
  if required_pairs.length() == 0 {
    return 0.0
  }
  let mut matched = 0
  for encoded in required_pairs {
    let (label, literal) = decode_table_pair(encoded)
    if label.length() > 0 &&
      literal.length() > 0 &&
      pair_present_in_text(candidate_text, label, literal) {
      matched += 1
    }
  }
  if matched == 0 {
    0.0
  } else {
    clamp_similarity(matched.to_double() / required_pairs.length().to_double())
  }
}

///|
fn implementation_evidence_text(implementation : ImplementationNode) -> String {
  let buf = StringBuilder::new()
  buf.write_string(implementation.name)
  buf.write_string("\n")
  buf.write_string(normalize_identifier_words(implementation.name))
  buf.write_string("\n")
  buf.write_string(implementation.signature)
  buf.write_string("\n")
  buf.write_string(implementation.declaration_text)
  buf.to_string()
}

///|
fn implementation_text(implementation : ImplementationNode) -> String {
  let buf = StringBuilder::new()
  buf.write_string(implementation_evidence_text(implementation))
  buf.write_string("\n")
  match implementation.doc_comment {
    Some(doc) => buf.write_string(doc)
    None => ()
  }
  buf.to_string()
}

///|
fn normalize_identifier_words(text : String) -> String {
  let buf = StringBuilder::new()
  let chars = text.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    let ch = chars[i]
    let prev = if i > 0 { Some(chars[i - 1]) } else { None }
    if ch == '_' || ch == '-' {
      buf.write_char(' ')
      continue
    }
    match prev {
      Some(p) =>
        if ch >= 'A' &&
          ch <= 'Z' &&
          ((p >= 'a' && p <= 'z') || (p >= '0' && p <= '9')) {
          buf.write_char(' ')
        }
      None => ()
    }
    buf.write_char(ch)
  }
  lower_ascii(buf.to_string())
}

///|
///|
/// Extract backtick-enclosed identifiers from criteria text.
/// E.g. "include a `detail` message" → ["detail"]
fn extract_inline_code_refs(criteria : Array[String]) -> Array[String] {
  let refs : Array[String] = []
  for criterion in criteria {
    let chars = criterion.to_array()
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '`' {
        let start = i + 1
        i += 1
        while i < chars.length() && chars[i] != '`' {
          i += 1
        }
        if i < chars.length() {
          let ref_text = @common.substring(criterion, start, i)
          let trimmed = trim(ref_text)
          if trimmed.length() > 0 && !refs.contains(trimmed) {
            refs.push(trimmed)
          }
        }
      }
      i += 1
    }
  }
  refs
}

///|
/// Score based on direct identifier matching between spec inline code refs
/// and implementation symbol name. Returns a high score (0.5) if the
/// implementation name contains any of the spec identifiers.
fn identifier_match_score(
  spec_identifiers : Array[String],
  impl_name : String,
) -> Double {
  if spec_identifiers.length() == 0 {
    return 0.0
  }
  let impl_lower = lower_ascii(impl_name)
  let impl_normalized = lower_ascii(normalize_identifier_words(impl_name))
  for ident in spec_identifiers {
    let ref_lower = lower_ascii(ident)
    if impl_lower.contains(ref_lower) || impl_normalized.contains(ref_lower) {
      return 0.5
    }
  }
  0.0
}

///|
fn clamp_similarity(value : Double) -> Double {
  if value < 0.0 {
    0.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
fn tfidf_similarity(a : String, b : String) -> Double {
  let tokens_a = @tokenizer.tokenize_for_tfidf(a)
  let tokens_b = @tokenizer.tokenize_for_tfidf(b)
  if tokens_a.length() == 0 || tokens_b.length() == 0 {
    return 0.0
  }
  let distance = @tfidf.calculate_tfidf_distance_from_tokens(tokens_a, tokens_b)
  clamp_similarity(1.0 - distance)
}

///|
fn ncd_similarity(a : String, b : String) -> Double {
  clamp_similarity(1.0 - @ncd.NCDStrategy::new().distance(a, b))
}

///|
fn adaptive_match_threshold(
  scored : Array[(String, Double)],
  config : SpecAlignConfig,
) -> Double {
  if scored.length() == 0 {
    return config.threshold
  }
  let top1 = scored[0].1
  let top2 = if scored.length() > 1 { scored[1].1 } else { 0.0 }
  let gap = top1 - top2
  let lowered = if config.threshold * 0.5 > 0.08 {
    config.threshold * 0.5
  } else {
    0.08
  }
  if top1 >= config.threshold {
    config.threshold
  } else if top1 >= lowered && gap >= 0.05 {
    lowered
  } else {
    config.threshold
  }
}

///|
fn build_trace_edges(
  requirements : Array[RequirementNode],
  scenarios : Array[ScenarioNode],
  implementations : Array[ImplementationNode],
  config : SpecAlignConfig,
) -> Array[TraceEdge] {
  // Build BM25 batch from all texts: requirements, criteria, implementations.
  // Document indices:
  //   [0 .. R-1]                  = requirement full texts
  //   [R .. R+C-1]                = per-criterion texts (flattened)
  //   [R+C .. R+C+I-1]            = implementation texts
  let req_texts : Array[String] = []
  for requirement in requirements {
    req_texts.push(requirement_text(requirement, scenarios))
  }
  let criteria_flat : Array[String] = []
  let criteria_req_index : Array[Int] = [] // maps criterion → requirement index
  for ri, requirement in requirements {
    for criterion in requirement.criteria {
      criteria_flat.push(criterion)
      criteria_req_index.push(ri)
    }
  }
  let impl_texts : Array[String] = []
  for implementation in implementations {
    impl_texts.push(implementation_text(implementation))
  }
  let all_texts : Array[String] = []
  for t in req_texts { all_texts.push(t) }
  for t in criteria_flat { all_texts.push(t) }
  for t in impl_texts { all_texts.push(t) }
  let all_tokenized = all_texts.map(fn(t) { @tokenizer.tokenize_for_tfidf(t) })
  let bm25 = @tfidf.BM25Batch::from_tokens(all_tokenized)
  let r_count = requirements.length()
  let c_count = criteria_flat.length()
  let impl_offset = r_count + c_count
  let edges : Array[TraceEdge] = []
  for ri, requirement in requirements {
    let scored : Array[(String, Double)] = []
    let req_section_refs = requirement_section_refs(requirement, scenarios)
    let req_literals = requirement_literals(requirement, scenarios)
    let req_pairs = requirement_table_pairs(requirement, scenarios)
    let spec_identifiers = extract_inline_code_refs(requirement.criteria)
    for ii, implementation in implementations {
      // BM25 similarity: requirement full text vs implementation
      let bm25_score = clamp_similarity(
        bm25.similarity(ri, impl_offset + ii),
      )
      // NCD for hybrid algorithm
      let ncd_score = if config.algorithm == "tfidf" {
        0.0
      } else {
        ncd_similarity(req_texts[ri], impl_texts[ii])
      }
      let base_score = match config.algorithm {
        "tfidf" => bm25_score
        "ncd" => ncd_score
        _ => clamp_similarity((bm25_score + ncd_score) / 2.0)
      }
      // Per-implementation criteria boost via BM25
      let mut best_criterion_score = 0.0
      for ci = 0; ci < c_count; ci = ci + 1 {
        if criteria_req_index[ci] != ri {
          continue
        }
        let s = clamp_similarity(
          bm25.similarity(r_count + ci, impl_offset + ii),
        )
        if s > best_criterion_score {
          best_criterion_score = s
        }
      }
      // Direct identifier match
      let ident_boost = identifier_match_score(
        spec_identifiers, implementation.name,
      )
      let candidate_score = if best_criterion_score > base_score {
        best_criterion_score
      } else {
        base_score
      }
      let boosted_base = if ident_boost > candidate_score {
        ident_boost
      } else {
        candidate_score
      }
      let title_score = tfidf_similarity(
        requirement.title,
        normalize_identifier_words(implementation.name),
      )
      let section_score = section_reference_score(req_section_refs, impl_texts[ii])
      let literal_score = literal_overlap_score(
        req_literals,
        implementation_evidence_text(implementation),
      )
      let table_score = table_pair_overlap_score(
        req_pairs,
        implementation_evidence_text(implementation),
      )
      let score = if title_score > boosted_base &&
        title_score > section_score &&
        title_score > literal_score &&
        title_score > table_score {
        title_score
      } else if section_score > boosted_base &&
        section_score > literal_score &&
        section_score > table_score {
        section_score
      } else if literal_score > boosted_base && literal_score > table_score {
        literal_score
      } else if table_score > boosted_base {
        table_score
      } else {
        boosted_base
      }
      scored.push((implementation.id, score))
    }
    scored.sort_by(fn(a, b) { b.1.compare(a.1) })
    let effective_threshold = adaptive_match_threshold(scored, config)
    let minimum_limit = if scored.length() < 10 { scored.length() } else { 10 }
    for i = 0; i < scored.length(); i = i + 1 {
      let (implementation_id, score) = scored[i]
      if i >= minimum_limit && score < effective_threshold {
        continue
      }
      edges.push({
        requirement_id: requirement.id,
        implementation_id,
        confidence: score,
        algorithm: config.algorithm,
        status: if score >= effective_threshold {
          "matched"
        } else {
          "unmatched"
        },
        rank: i,
      })
    }
  }
  edges
}

///|
fn best_edge_for_requirement(
  edges : Array[TraceEdge],
  requirement_id : String,
) -> TraceEdge? {
  for edge in edges {
    if edge.requirement_id == requirement_id && edge.rank == 0 {
      return Some(edge)
    }
  }
  None
}

///|
fn candidate_edges_for_requirement(
  edges : Array[TraceEdge],
  requirement_id : String,
) -> Array[TraceEdge] {
  let result : Array[TraceEdge] = []
  for edge in edges {
    if edge.requirement_id == requirement_id {
      result.push(edge)
    }
  }
  result
}

///|
fn implementation_by_id(
  implementations : Array[ImplementationNode],
  implementation_id : String,
) -> ImplementationNode? {
  for implementation in implementations {
    if implementation.id == implementation_id {
      return Some(implementation)
    }
  }
  None
}

///|
fn matched_implementations_for_requirement(
  edges : Array[TraceEdge],
  implementations : Array[ImplementationNode],
  requirement_id : String,
) -> Array[ImplementationNode] {
  let result : Array[ImplementationNode] = []
  let seen : Map[String, Bool] = {}
  for edge in edges {
    if edge.requirement_id != requirement_id || edge.status != "matched" {
      continue
    }
    match implementation_by_id(implementations, edge.implementation_id) {
      Some(implementation) => {
        if seen.contains(implementation.id) {
          continue
        }
        seen.set(implementation.id, true)
        result.push(implementation)
      }
      None => ()
    }
  }
  result
}

///|
fn aggregate_requirement_evidence_text(
  requirement_id : String,
  edges : Array[TraceEdge],
  implementations : Array[ImplementationNode],
) -> String {
  let buf = StringBuilder::new()
  let matched = matched_implementations_for_requirement(
    edges, implementations, requirement_id,
  )
  for implementation in matched {
    if buf.to_string().length() > 0 {
      buf.write_string("\n")
    }
    buf.write_string(implementation_evidence_text(implementation))
  }
  buf.to_string()
}

///|
fn missing_literal_count(
  required_literals : Array[String],
  file_text : String,
) -> Int {
  let mut count = 0
  for literal in required_literals {
    if literal.length() > 0 && !literal_present(file_text, literal) {
      count += 1
    }
  }
  count
}

///|
fn missing_pair_count(
  required_pairs : Array[String],
  file_text : String,
) -> Int {
  let mut count = 0
  for encoded in required_pairs {
    let (label, literal) = decode_table_pair(encoded)
    if !pair_present_in_text(file_text, label, literal) {
      count += 1
    }
  }
  count
}

///|
fn preferred_requirement_match(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
  implementations : Array[ImplementationNode],
  edges : Array[TraceEdge],
) -> (TraceEdge?, ImplementationNode?) {
  let candidates = candidate_edges_for_requirement(edges, requirement.id)
  if candidates.length() == 0 {
    return (None, None)
  }
  let required_literals = requirement_literals(requirement, scenarios)
  let required_pairs = requirement_table_pairs(requirement, scenarios)
  let mut best_edge : TraceEdge? = None
  let mut best_implementation : ImplementationNode? = None
  let mut best_missing_pairs = 1 << 30
  let mut best_missing_literals = 1 << 30
  let mut best_confidence = -1.0
  let mut best_rank = 1 << 30
  for edge in candidates {
    let implementation = match
      implementation_by_id(implementations, edge.implementation_id) {
      Some(value) => value
      None => continue
    }
    let file_text = implementation_evidence_text(implementation)
    let missing_pairs = missing_pair_count(required_pairs, file_text)
    let missing_literals = missing_literal_count(required_literals, file_text)
    let better = missing_pairs < best_missing_pairs ||
      (
        missing_pairs == best_missing_pairs &&
        missing_literals < best_missing_literals
      ) ||
      (
        missing_pairs == best_missing_pairs &&
        missing_literals == best_missing_literals &&
        edge.confidence > best_confidence
      ) ||
      (
        missing_pairs == best_missing_pairs &&
        missing_literals == best_missing_literals &&
        edge.confidence == best_confidence &&
        edge.rank < best_rank
      )
    if better {
      best_edge = Some(edge)
      best_implementation = Some(implementation)
      best_missing_pairs = missing_pairs
      best_missing_literals = missing_literals
      best_confidence = edge.confidence
      best_rank = edge.rank
    }
  }
  match (best_edge, best_implementation) {
    (Some(edge), Some(implementation)) => (Some(edge), Some(implementation))
    _ => {
      let fallback_edge = best_edge_for_requirement(edges, requirement.id)
      let fallback_impl = match fallback_edge {
        Some(edge) =>
          implementation_by_id(implementations, edge.implementation_id)
        None => None
      }
      (fallback_edge, fallback_impl)
    }
  }
}

///|
fn find_previous_edge(
  previous : AlignSnapshot?,
  requirement_id : String,
) -> TraceEdge? {
  match previous {
    Some(snapshot) => {
      for edge in snapshot.trace_edges {
        if edge.requirement_id == requirement_id && edge.rank == 0 {
          return Some(edge)
        }
      }
      None
    }
    None => None
  }
}

///|
fn file_hash_changed(
  previous : AlignSnapshot?,
  path : String,
  current_hash : String,
) -> Bool {
  match previous {
    Some(snapshot) =>
      match snapshot.file_hashes.get(path) {
        Some(old_hash) => old_hash != current_hash
        None => true
      }
    None => false
  }
}

///|
fn diff_item_for_requirement(
  requirement : RequirementNode,
  scenarios : Array[ScenarioNode],
  best_edge : TraceEdge?,
  matched_implementation : ImplementationNode?,
  edges : Array[TraceEdge],
  implementations : Array[ImplementationNode],
  previous : AlignSnapshot?,
  file_hashes : Map[String, String],
) -> AlignDiffItem {
  match (best_edge, matched_implementation) {
    (Some(edge), Some(implementation_node)) => {
      let reasons : Array[String] = []
      let required_literals = requirement_literals(requirement, scenarios)
      let required_pairs = requirement_table_pairs(requirement, scenarios)
      let previous_edge = find_previous_edge(previous, requirement.id)
      let previous_confidence = match previous_edge {
        Some(value) => Some(value.confidence)
        None => None
      }
      let aggregate_text = aggregate_requirement_evidence_text(
        requirement.id,
        edges,
        implementations,
      )
      let file_text = if aggregate_text.length() > 0 {
        aggregate_text
      } else {
        implementation_evidence_text(implementation_node)
      }
      let missing_literals : Array[String] = []
      for literal in required_literals {
        if literal.length() > 0 && !literal_present(file_text, literal) {
          missing_literals.push(literal)
        }
      }
      let missing_pairs : Array[String] = []
      for encoded in required_pairs {
        let (label, literal) = decode_table_pair(encoded)
        if !pair_present_in_text(file_text, label, literal) {
          missing_pairs.push(label + "=" + literal)
        }
      }
      let score_drop = match previous_edge {
        Some(value) =>
          if value.implementation_id == implementation_node.id {
            value.confidence - edge.confidence
          } else {
            0.0
          }
        None => 0.0
      }
      let mut category = "MATCHED"
      if edge.status != "matched" {
        category = "SPEC_ONLY"
        reasons.push(
          "No implementation matched above the similarity threshold.",
        )
      } else if missing_literals.length() > 0 {
        category = "DRIFTED"
        reasons.push(
          "Required literals not found in implementation: `" +
          missing_literals.join("`, `") +
          "`.",
        )
      } else if missing_pairs.length() > 0 {
        category = "DRIFTED"
        reasons.push(
          "Required table entries not found in implementation: `" +
          missing_pairs.join("`, `") +
          "`.",
        )
      } else if score_drop >= 0.3 {
        category = "DRIFTED"
        reasons.push(
          "Similarity dropped materially from the previous snapshot.",
        )
      } else {
        reasons.push("Best implementation match remains above threshold.")
      }
      if category == "DRIFTED" &&
        file_hash_changed(
          previous,
          requirement.source_file,
          file_hashes.get(requirement.source_file).unwrap_or(""),
        ) &&
        file_hash_changed(
          previous,
          implementation_node.file,
          file_hashes.get(implementation_node.file).unwrap_or(""),
        ) {
        category = "CONFLICT"
        reasons.push(
          "Both spec and implementation changed since the last snapshot.",
        )
      }
      {
        category,
        requirement_id: Some(requirement.id),
        requirement_title: Some(requirement.title),
        implementation_id: Some(implementation_node.id),
        implementation_name: Some(implementation_node.name),
        confidence: edge.confidence,
        previous_confidence,
        reasons,
        spec_file: Some(requirement.source_file),
        spec_line: Some(requirement.source_start_line),
        impl_file: Some(implementation_node.file),
        impl_line: Some(implementation_node.start_line),
        spec_excerpt: Some(requirement_excerpt(requirement)),
        impl_excerpt: Some(implementation_excerpt(implementation_node)),
      }
    }
    _ =>
      {
        category: "SPEC_ONLY",
        requirement_id: Some(requirement.id),
        requirement_title: Some(requirement.title),
        implementation_id: None,
        implementation_name: None,
        confidence: 0.0,
        previous_confidence: None,
        reasons: [
          "No implementation candidate reached the similarity threshold.",
        ],
        spec_file: Some(requirement.source_file),
        spec_line: Some(requirement.source_start_line),
        impl_file: None,
        impl_line: None,
        spec_excerpt: Some(requirement_excerpt(requirement)),
        impl_excerpt: None,
      }
  }
}

///|
fn implementation_group_keys(
  implementations : Array[ImplementationNode],
) -> Map[String, String] {
  let groups : Map[String, String] = {}
  if implementations.length() == 0 {
    return groups
  }
  let mut current_file = ""
  let mut current_kind = ""
  let mut current_start = 0
  let mut current_end = 0
  let mut current_key = ""
  for implementation in implementations {
    let extends_current = current_key != "" &&
      implementation.file == current_file &&
      implementation.kind == current_kind &&
      implementation.start_line <= current_end + 1
    if !extends_current {
      current_file = implementation.file
      current_kind = implementation.kind
      current_start = implementation.start_line
      current_end = implementation.end_line
      current_key = implementation.file +
        "\u0001" +
        implementation.kind +
        "\u0001" +
        current_start.to_string()
    } else if implementation.end_line > current_end {
      current_end = implementation.end_line
    }
    groups.set(implementation.id, current_key)
  }
  groups
}

///|
fn build_diff_items(
  requirements : Array[RequirementNode],
  scenarios : Array[ScenarioNode],
  implementations : Array[ImplementationNode],
  edges : Array[TraceEdge],
  previous : AlignSnapshot?,
  file_hashes : Map[String, String],
) -> Array[AlignDiffItem] {
  let items : Array[AlignDiffItem] = []
  let referenced : Map[String, Bool] = {}
  let referenced_groups : Map[String, Bool] = {}
  let group_keys = implementation_group_keys(implementations)
  for edge in edges {
    if edge.status == "unmatched" || edge.status == "orphan" {
      continue
    }
    referenced.set(edge.implementation_id, true)
    match implementation_by_id(implementations, edge.implementation_id) {
      Some(implementation) =>
        match group_keys.get(implementation.id) {
          Some(key) => referenced_groups.set(key, true)
          None => ()
        }
      None => ()
    }
  }
  for requirement in requirements {
    let (best_edge, matched_implementation) = preferred_requirement_match(
      requirement, scenarios, implementations, edges,
    )
    let item = diff_item_for_requirement(
      requirement, scenarios, best_edge, matched_implementation, edges, implementations,
      previous, file_hashes,
    )
    items.push(item)
  }
  for implementation in implementations {
    if referenced.contains(implementation.id) {
      continue
    }
    match group_keys.get(implementation.id) {
      Some(key) => if referenced_groups.contains(key) { continue }
      None => ()
    }
    items.push({
      category: "IMPL_ONLY",
      requirement_id: None,
      requirement_title: None,
      implementation_id: Some(implementation.id),
      implementation_name: Some(implementation.name),
      confidence: 0.0,
      previous_confidence: None,
      reasons: ["Implementation has no requirement match above threshold."],
      spec_file: None,
      spec_line: None,
      impl_file: Some(implementation.file),
      impl_line: Some(implementation.start_line),
      spec_excerpt: None,
      impl_excerpt: Some(implementation_excerpt(implementation)),
    })
  }
  items
}

///|
fn build_summary(
  requirements : Array[RequirementNode],
  implementations : Array[ImplementationNode],
  edges : Array[TraceEdge],
  items : Array[AlignDiffItem],
) -> AlignSummary {
  let mut matched = 0
  let mut drifted = 0
  let mut spec_only = 0
  let mut impl_only = 0
  let mut conflict = 0
  for item in items {
    match item.category {
      "MATCHED" => matched += 1
      "DRIFTED" => drifted += 1
      "SPEC_ONLY" => spec_only += 1
      "IMPL_ONLY" => impl_only += 1
      "CONFLICT" => conflict += 1
      _ => ()
    }
  }
  {
    matched,
    drifted,
    spec_only,
    impl_only,
    conflict,
    total_requirements: requirements.length(),
    total_implementations: implementations.length(),
    total_edges: edges.length(),
  }
}

///|
async fn build_snapshot(
  config : SpecAlignConfig,
  previous : AlignSnapshot?,
) -> AlignSnapshot? {
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir=config.impl_path,
  )
  let (requirements, scenarios, used_spec_formats, spec_hashes, spec_file_states
  ) = collect_spec_data(config, registry)
  let (
    implementations,
    used_impl_specs,
    impl_hashes,
    _file_contents,
    impl_file_states,
  ) = collect_impl_data(config, registry)
  if requirements.length() == 0 && implementations.length() == 0 {
    return None
  }
  let file_hashes : Map[String, String] = {}
  for entry in spec_hashes {
    file_hashes.set(entry.0, entry.1)
  }
  for entry in impl_hashes {
    file_hashes.set(entry.0, entry.1)
  }
  let edges = build_trace_edges(
    requirements, scenarios, implementations, config,
  )
  let diff_items = build_diff_items(
    requirements, scenarios, implementations, edges, previous, file_hashes,
  )
  let summary = build_summary(requirements, implementations, edges, diff_items)
  let used_specs = used_spec_formats + used_impl_specs
  let file_states = spec_file_states + impl_file_states
  Some({
    version: "spec-align-v1",
    generated_at: current_epoch_seconds(),
    config,
    requirements,
    scenarios,
    implementations,
    trace_edges: edges,
    diff_items,
    summary,
    file_hashes,
    source_fingerprint: @reconcile_tracking.build_source_fingerprint(
      config_hash(config),
      file_states,
    ),
    used_specs,
    commit: None,
    history: match previous {
      Some(value) => value.history
      None => []
    },
    cache_hit: false,
  })
}

///|
fn build_diff_report(snapshot : AlignSnapshot) -> AlignDiffReport {
  {
    version: snapshot.version,
    generated_at: snapshot.generated_at,
    config: snapshot.config,
    summary: snapshot.summary,
    items: snapshot.diff_items,
    used_specs: snapshot.used_specs,
    source_fingerprint: snapshot.source_fingerprint,
    commit: snapshot.commit,
    cache_hit: snapshot.cache_hit,
  }
}

///|
fn build_trace_report(snapshot : AlignSnapshot) -> AlignTraceReport {
  {
    version: snapshot.version,
    generated_at: snapshot.generated_at,
    config: snapshot.config,
    summary: snapshot.summary,
    requirements: snapshot.requirements,
    implementations: snapshot.implementations,
    edges: snapshot.trace_edges,
    source_fingerprint: snapshot.source_fingerprint,
    commit: snapshot.commit,
    history: snapshot.history,
    cache_hit: snapshot.cache_hit,
  }
}

///|
fn single_numeric(text : String?) -> String? {
  match text {
    Some(value) => {
      let literals = literals_from_text(value)
      if literals.length() == 1 {
        Some(literals[0])
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn find_substring(text : String, needle : String) -> Int {
  if needle.length() == 0 {
    return 0
  }
  if needle.length() > text.length() {
    return -1
  }
  let limit = text.length() - needle.length()
  for i = 0; i <= limit; i = i + 1 {
    if @common.substring(text, i, i + needle.length()) == needle {
      return i
    }
  }
  -1
}

///|
fn replace_first(text : String, old : String, new_ : String) -> String {
  let idx = find_substring(text, old)
  if idx < 0 {
    return text
  }
  @common.substring(text, 0, idx) +
  new_ +
  @common.substring(text, idx + old.length(), text.length())
}

///|
fn make_numeric_patch(
  path : String,
  before_text : String,
  before_value : String,
  after_value : String,
) -> String {
  let after_text = replace_first(before_text, before_value, after_value)
  "```diff\n--- " +
  path +
  "\n+++ " +
  path +
  "\n@@\n-" +
  before_text +
  "\n+" +
  after_text +
  "\n```"
}

///|
fn build_suggestions(
  snapshot : AlignSnapshot,
  direction : String,
) -> Array[AlignSuggestion] {
  let suggestions : Array[AlignSuggestion] = []
  let emitted : Map[String, Bool] = {}
  for item in snapshot.diff_items {
    let mut current : AlignSuggestion? = None
    match item.category {
      "SPEC_ONLY" =>
        if direction != "impl-wins" {
          current = Some({
            category: item.category,
            direction: "spec-wins",
            title: "Implement " +
            item.requirement_title.unwrap_or("requirement"),
            summary: "Create implementation coverage for the unmatched requirement.",
            spec_file: item.spec_file,
            impl_file: None,
            patch: None,
            task: Some(
              "Implement `" +
              item.requirement_id.unwrap_or("requirement") +
              "` and verify its acceptance criteria.",
            ),
            reasons: item.reasons.copy(),
          })
        }
      "IMPL_ONLY" =>
        if direction != "spec-wins" {
          let implementation_name = item.implementation_name.unwrap_or(
            "implementation",
          )
          current = Some({
            category: item.category,
            direction: "impl-wins",
            title: "Document " + implementation_name,
            summary: "Add spec coverage for implementation that currently has no requirement match.",
            spec_file: None,
            impl_file: item.impl_file,
            patch: Some(
              "## ADDED Requirements\n\n### Requirement: " +
              implementation_name +
              "\nDescribe the expected behavior for `" +
              implementation_name +
              "`.\n",
            ),
            task: Some(
              "Add a requirement or scenario for `" + implementation_name + "`.",
            ),
            reasons: item.reasons.copy(),
          })
        }
      "DRIFTED" | "CONFLICT" => {
        let spec_patch = match
          (item.spec_file, item.spec_excerpt, item.impl_excerpt) {
          (Some(path), Some(spec_excerpt), Some(impl_excerpt)) =>
            match
              (
                single_numeric(Some(spec_excerpt)),
                single_numeric(Some(impl_excerpt)),
              ) {
              (Some(spec_value), Some(impl_value)) =>
                Some(
                  make_numeric_patch(path, spec_excerpt, spec_value, impl_value),
                )
              _ => None
            }
          _ => None
        }
        let impl_patch = match
          (item.impl_file, item.impl_excerpt, item.spec_excerpt) {
          (Some(path), Some(impl_excerpt), Some(spec_excerpt)) =>
            match
              (
                single_numeric(Some(impl_excerpt)),
                single_numeric(Some(spec_excerpt)),
              ) {
              (Some(impl_value), Some(spec_value)) =>
                Some(
                  make_numeric_patch(path, impl_excerpt, impl_value, spec_value),
                )
              _ => None
            }
          _ => None
        }
        if direction != "impl-wins" {
          current = Some({
            category: item.category,
            direction: "spec-wins",
            title: "Align implementation with " +
            item.requirement_id.unwrap_or("requirement"),
            summary: "Implementation appears to have drifted from the current spec.",
            spec_file: item.spec_file,
            impl_file: item.impl_file,
            patch: impl_patch,
            task: Some(
              "Update implementation to satisfy `" +
              item.requirement_id.unwrap_or("requirement") +
              "` and rerun `indexion spec align diff`.",
            ),
            reasons: item.reasons.copy(),
          })
        }
        if direction != "spec-wins" {
          let suggestion = {
            category: item.category,
            direction: "impl-wins",
            title: "Update spec for " +
            item.implementation_name.unwrap_or("implementation"),
            summary: "Specification appears outdated relative to the implementation.",
            spec_file: item.spec_file,
            impl_file: item.impl_file,
            patch: spec_patch,
            task: Some(
              "Revise the requirement or scenario text to reflect the implemented behavior.",
            ),
            reasons: item.reasons.copy(),
          }
          let key = suggestion_dedupe_key(suggestion)
          if !emitted.contains(key) {
            emitted.set(key, true)
            suggestions.push(suggestion)
          }
        }
      }
      _ => ()
    }
    match current {
      Some(suggestion) => {
        let key = suggestion_dedupe_key(suggestion)
        if !emitted.contains(key) {
          emitted.set(key, true)
          suggestions.push(suggestion)
        }
      }
      None => ()
    }
  }
  suggestions
}

///|
fn suggestion_dedupe_key(suggestion : AlignSuggestion) -> String {
  match suggestion.category {
    "IMPL_ONLY" | "SPEC_ONLY" =>
      [suggestion.category, suggestion.direction, suggestion.title].join(
        "\u0001",
      )
    _ =>
      [
        suggestion.category,
        suggestion.direction,
        suggestion.title,
        suggestion.spec_file.unwrap_or(""),
        suggestion.impl_file.unwrap_or(""),
      ].join("\u0001")
  }
}

///|
fn build_suggest_report(snapshot : AlignSnapshot) -> AlignSuggestReport {
  {
    version: snapshot.version,
    generated_at: snapshot.generated_at,
    config: snapshot.config,
    summary: snapshot.summary,
    suggestions: build_suggestions(snapshot, snapshot.config.direction),
    used_specs: snapshot.used_specs,
    source_fingerprint: snapshot.source_fingerprint,
    commit: snapshot.commit,
    cache_hit: snapshot.cache_hit,
  }
}

///|
fn should_fail(summary : AlignSummary, fail_on : String) -> Bool {
  match fail_on {
    "drifted" => summary.drifted > 0 || summary.conflict > 0
    "spec-only" => summary.spec_only > 0
    "any" =>
      summary.drifted > 0 ||
      summary.spec_only > 0 ||
      summary.impl_only > 0 ||
      summary.conflict > 0
    _ => false
  }
}

///|
fn build_status_report(snapshot : AlignSnapshot) -> AlignStatusReport {
  let should_fail_now = should_fail(snapshot.summary, snapshot.config.fail_on)
  {
    version: snapshot.version,
    generated_at: snapshot.generated_at,
    config: snapshot.config,
    summary: snapshot.summary,
    status: if should_fail_now {
      "fail"
    } else {
      "pass"
    },
    fail_on: snapshot.config.fail_on,
    should_fail: should_fail_now,
    used_specs: snapshot.used_specs,
    source_fingerprint: snapshot.source_fingerprint,
    commit: snapshot.commit,
    cache_hit: snapshot.cache_hit,
  }
}

///|
fn resolve_input_path(path : String) -> String {
  if @config.is_absolute_path(path) {
    @config.normalize_path(path)
  } else {
    match @env.current_dir() {
      Some(cwd) => @config.join_path(cwd, path)
      None => @config.normalize_path(path)
    }
  }
}

///|
fn path_within_dir(root : String, path : String) -> Bool {
  let normalized_root = @config.normalize_path(root)
  let normalized_path = @config.normalize_path(path)
  normalized_path == normalized_root ||
  normalized_path.has_prefix(normalized_root + "/")
}

///|
async fn git_repo_root(anchor : String) -> String? {
  let root_arg = if path_is_dir(anchor) {
    anchor
  } else {
    @config.dirname(anchor)
  }
  @git.repo_root(root_arg)
}

///|
async fn current_commit_info(config : SpecAlignConfig) -> AlignCommitInfo? {
  let anchor = if config.impl_path.length() > 0 {
    config.impl_path
  } else {
    config.spec_path
  }
  let repo_root = match git_repo_root(anchor) {
    Some(value) => value
    None => return None
  }
  let head = match @git.head_commit(repo_root) {
    Some(value) => value
    None => return None
  }
  let short_head = match @git.head_commit(repo_root, short=true) {
    Some(value) => value
    None => return None
  }
  let committed_at = @git.head_commit_seconds(repo_root)
  let dirty = @git.status_dirty(repo_root, ".")
  Some({ repo_root, head, short_head, committed_at, dirty })
}

///|
async fn git_changed_files(config : SpecAlignConfig) -> Array[String]? {
  let anchor = if config.impl_path.length() > 0 {
    config.impl_path
  } else {
    config.spec_path
  }
  let repo_root = match git_repo_root(anchor) {
    Some(value) => value
    None => {
      println("Error: incremental spec align requires a git repository.")
      return None
    }
  }
  let spec_abs = resolve_input_path(config.spec_path)
  let impl_abs = resolve_input_path(config.impl_path)
  if !path_within_dir(repo_root, spec_abs) ||
    !path_within_dir(repo_root, impl_abs) {
    println(
      "Error: incremental spec align paths must live inside the current git repository.",
    )
    return None
  }
  let changed_rel = match
    @git.changed_files(repo_root, config.git_base, [spec_abs, impl_abs]) {
    Some(value) => value
    None => {
      println(
        "Error: failed to collect incremental git diff from base `" +
        config.git_base +
        "`.",
      )
      return None
    }
  }
  let changed : Array[String] = []
  for rel in changed_rel {
    let trimmed = trim(rel)
    if trimmed.length() > 0 {
      changed.push(@config.join_path(repo_root, trimmed))
    }
  }
  changed.sort()
  Some(changed)
}

///|
fn file_is_changed(changed_files : Map[String, Bool], path : String?) -> Bool {
  match path {
    Some(value) => changed_files.contains(@config.normalize_path(value))
    None => false
  }
}

///|
fn filter_snapshot_for_incremental(
  snapshot : AlignSnapshot,
  changed_files : Array[String],
) -> AlignSnapshot {
  let changed : Map[String, Bool] = {}
  for path in changed_files {
    changed.set(@config.normalize_path(path), true)
  }
  let affected_requirements : Map[String, Bool] = {}
  let affected_implementations : Map[String, Bool] = {}
  let mut changed_any = false
  for item in snapshot.diff_items {
    let item_changed = file_is_changed(changed, item.spec_file) ||
      file_is_changed(changed, item.impl_file)
    if !item_changed {
      continue
    }
    changed_any = true
    match item.requirement_id {
      Some(requirement_id) => affected_requirements.set(requirement_id, true)
      None => ()
    }
    match item.implementation_id {
      Some(implementation_id) =>
        affected_implementations.set(implementation_id, true)
      None => ()
    }
  }
  let mut updated = true
  while updated {
    updated = false
    for edge in snapshot.trace_edges {
      if edge.status != "matched" {
        continue
      }
      let req_known = affected_requirements.contains(edge.requirement_id)
      let impl_known = affected_implementations.contains(edge.implementation_id)
      if req_known && !impl_known {
        affected_implementations.set(edge.implementation_id, true)
        updated = true
      }
      if impl_known && !req_known {
        affected_requirements.set(edge.requirement_id, true)
        updated = true
      }
    }
  }
  let requirements = snapshot.requirements.filter(fn(req) {
    affected_requirements.contains(req.id)
  })
  let implementations = snapshot.implementations.filter(fn(node) {
    affected_implementations.contains(node.id)
  })
  let edges = snapshot.trace_edges.filter(fn(edge) {
    affected_requirements.contains(edge.requirement_id) ||
    affected_implementations.contains(edge.implementation_id)
  })
  let items = snapshot.diff_items.filter(fn(item) {
    match (item.requirement_id, item.implementation_id) {
      (Some(requirement_id), Some(implementation_id)) =>
        affected_requirements.contains(requirement_id) ||
        affected_implementations.contains(implementation_id)
      (Some(requirement_id), None) =>
        affected_requirements.contains(requirement_id)
      (None, Some(implementation_id)) =>
        affected_implementations.contains(implementation_id)
      _ => false
    }
  })
  let summary = if changed_any {
    build_summary(requirements, implementations, edges, items)
  } else {
    {
      matched: 0,
      drifted: 0,
      spec_only: 0,
      impl_only: 0,
      conflict: 0,
      total_requirements: 0,
      total_implementations: 0,
      total_edges: 0,
    }
  }
  {
    ..snapshot,
    requirements,
    implementations,
    trace_edges: edges,
    diff_items: items,
    summary,
  }
}

///|
async fn snapshot_for_config_async(config : SpecAlignConfig) -> AlignSnapshot? {
  let cache_dir = match resolve_cache_dir(config) {
    Some(value) => value
    None => return None
  }
  let effective_config = { ..config, cache_dir, }
  let previous = match load_snapshot(cache_dir) {
    Some(value) => Some(value)
    None =>
      if has_cache_artifacts(cache_dir) {
        if !purge_corrupt_snapshot_cache(cache_dir) {
          return None
        }
        None
      } else {
        None
      }
  }
  let snapshot = match build_snapshot(effective_config, previous) {
    Some(value) => value
    None => return None
  }
  let snapshot = { ..snapshot, commit: current_commit_info(effective_config) }
  if !save_snapshot(cache_dir, snapshot) {
    return None
  }
  let snapshot = match load_snapshot(cache_dir) {
    Some(value) => value
    None => return None
  }
  if !config.incremental {
    return Some(snapshot)
  }
  let changed_files = match git_changed_files(config) {
    Some(value) => value
    None => return None
  }
  Some(filter_snapshot_for_incremental(snapshot, changed_files))
}

///|
pub async fn watch_probe_async(config : SpecAlignConfig) -> String? {
  let registry = @kgf_features.load_registry_or_empty(
    specs_dir=config.specs_dir,
    target_dir=config.impl_path,
  )
  let spec_files = discover_spec_files(config.spec_path, registry)
  let impl_files = discover_impl_files(config.impl_path, registry)
  if spec_files.length() == 0 && impl_files.length() == 0 {
    return None
  }
  let parts : Array[String] = []
  for path in spec_files {
    parts.push(path)
    match @git.file_mtime_seconds(path) {
      Some(value) => parts.push(value.to_string())
      None => parts.push("")
    }
  }
  for path in impl_files {
    parts.push(path)
    match @git.file_mtime_seconds(path) {
      Some(value) => parts.push(value.to_string())
      None => parts.push("")
    }
  }
  Some(@cas_hash.compute_hash(parts.join("\u0001")).to_string())
}

///|
pub async fn diff_report_async(config : SpecAlignConfig) -> AlignDiffReport? {
  match snapshot_for_config_async(config) {
    Some(snapshot) => Some(build_diff_report(snapshot))
    None => None
  }
}

///|
pub async fn trace_report_async(config : SpecAlignConfig) -> AlignTraceReport? {
  match snapshot_for_config_async(config) {
    Some(snapshot) => Some(build_trace_report(snapshot))
    None => None
  }
}

///|
pub async fn suggest_report_async(
  config : SpecAlignConfig,
) -> AlignSuggestReport? {
  match snapshot_for_config_async(config) {
    Some(snapshot) => Some(build_suggest_report(snapshot))
    None => None
  }
}

///|
pub async fn status_report_async(
  config : SpecAlignConfig,
) -> AlignStatusReport? {
  match snapshot_for_config_async(config) {
    Some(snapshot) => Some(build_status_report(snapshot))
    None => None
  }
}
