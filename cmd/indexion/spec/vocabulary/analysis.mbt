///|
priv struct FileVocabulary {
  path : String
  language : String
  required : Array[VocabularyTerm]
  allowed : Array[VocabularyTerm]
  observed : Array[VocabularyTerm]
}

///|
priv struct VocabularyGroup {
  required : Map[String, VocabularyTerm]
  allowed : Map[String, VocabularyTerm]
  observed : Map[String, VocabularyTerm]
  files : Array[VocabularyFileSummary]
}

///|
fn VocabularyGroup::new() -> VocabularyGroup {
  { required: {}, allowed: {}, observed: {}, files: [] }
}

///|
fn build_report(config : VocabularyConfig) -> VocabularyReport? {
  let all_paths = combined_paths(config.source_paths, config.target_paths)
  let registry = match config.specs_dir {
    Some(dir) =>
      @kgf_features.load_registry_or_empty(specs_dir=dir, target_dirs=all_paths)
    None => @kgf_features.load_registry_or_empty(target_dirs=all_paths)
  }
  build_report_with_registry(config, registry)
}

///|
fn build_report_with_registry(
  config : VocabularyConfig,
  registry : @kgf_registry.KGFRegistry,
) -> VocabularyReport? {
  if registry.get_languages().length() == 0 {
    println(
      "Error: no KGF specs were loaded. Run from a directory whose ancestry " +
      "contains a `kgfs/` directory, or pass --specs-dir.",
    )
    return None
  }
  let source_group = match
    collect_group_vocabulary(config.source_paths, registry, role_source) {
    Some(group) => group
    None => return None
  }
  let target_group = match
    collect_group_vocabulary(config.target_paths, registry, role_target) {
    Some(group) => group
    None => return None
  }
  let direction = normalize_direction(config.direction)
  let source_required_terms = sorted_terms(source_group.required)
  let source_allowed_terms = sorted_terms(source_group.allowed)
  let target_terms = sorted_terms(target_group.observed)
  let missing = sorted_term_difference(
    source_group.required,
    target_group.observed,
  )
  let drift = sorted_term_difference(
    target_group.observed,
    source_group.allowed,
  )
  let missing_assessments = assess_issue_terms(missing, target_group.observed)
  let drift_assessments = assess_issue_terms(drift, source_group.allowed)
  let report_precision_candidate_count = count_checked_assessments(
    direction, missing_assessments, drift_assessments, issue_classification_report_precision,
  )
  let output_noise_candidate_count = count_checked_assessments(
    direction, missing_assessments, drift_assessments, issue_classification_output_noise,
  )
  let unresolved_issue_count = count_checked_assessments(
    direction, missing_assessments, drift_assessments, issue_classification_unresolved,
  )
  let passed = direction_passes(direction, missing.length(), drift.length())
  Some({
    version: vocabulary_report_version,
    direction,
    source_paths: config.source_paths,
    target_paths: config.target_paths,
    source_file_count: source_group.files.length(),
    target_file_count: target_group.files.length(),
    source_required_count: source_required_terms.length(),
    source_allowed_count: source_allowed_terms.length(),
    target_observed_count: target_terms.length(),
    source_files: source_group.files,
    target_files: target_group.files,
    source_required_terms,
    source_allowed_terms,
    target_terms,
    missing_source_terms: missing,
    target_drift_terms: drift,
    missing_source_assessments: missing_assessments,
    target_drift_assessments: drift_assessments,
    report_precision_candidate_count,
    output_noise_candidate_count,
    unresolved_issue_count,
    passed,
  })
}

///|
fn collect_group_vocabulary(
  paths : Array[String],
  registry : @kgf_registry.KGFRegistry,
  role : String,
) -> VocabularyGroup? {
  let group = VocabularyGroup::new()
  for path in paths {
    match collect_file_vocabulary(path, registry, role) {
      Some(file) => merge_file_vocabulary(group, file)
      None => return None
    }
  }
  Some(group)
}

///|
fn merge_file_vocabulary(
  group : VocabularyGroup,
  file : FileVocabulary,
) -> Unit {
  merge_terms(group.required, file.required)
  merge_terms(group.allowed, file.allowed)
  merge_terms(group.observed, file.observed)
  group.files.push(file.summary())
}

///|
fn collect_file_vocabulary(
  path : String,
  registry : @kgf_registry.KGFRegistry,
  role : String,
) -> FileVocabulary? {
  let language = match registry.detect_from_path(path) {
    Some(lang) => lang
    None => {
      println("Error: no KGF spec matched file: " + path)
      return None
    }
  }
  let spec = match registry.get_spec(language) {
    Some(s) => s
    None => {
      println(
        "Error: KGF spec is missing after language detection: " + language,
      )
      return None
    }
  }
  let archive_entries = @vfs.try_extract_archive_entries(path, spec) catch {
    _ => {
      println("Error: cannot expand archive vocabulary file: " + path)
      return None
    }
  }
  match archive_entries {
    Some(entries) =>
      return collect_archive_vocabulary(path, language, entries, registry, role)
    None => ()
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => {
      println("Error: cannot read vocabulary file: " + path)
      return None
    }
  }
  collect_content_vocabulary(path, content, registry, role)
}

///|
fn collect_archive_vocabulary(
  path : String,
  language : String,
  entries : Array[(String, String)],
  registry : @kgf_registry.KGFRegistry,
  role : String,
) -> FileVocabulary? {
  let required : Map[String, VocabularyTerm] = {}
  let allowed : Map[String, VocabularyTerm] = {}
  let observed : Map[String, VocabularyTerm] = {}
  for item in entries {
    match collect_content_vocabulary(item.0, item.1, registry, role) {
      Some(file) => {
        merge_terms(required, file.required)
        merge_terms(allowed, file.allowed)
        merge_terms(observed, file.observed)
      }
      None => ()
    }
  }
  Some({
    path,
    language,
    required: sorted_terms(required),
    allowed: sorted_terms(allowed),
    observed: sorted_terms(observed),
  })
}

///|
fn collect_content_vocabulary(
  path : String,
  content : String,
  registry : @kgf_registry.KGFRegistry,
  role : String,
) -> FileVocabulary? {
  let language = match registry.detect_from_path(path) {
    Some(lang) => lang
    None => {
      println("Error: no KGF spec matched file: " + path)
      return None
    }
  }
  let spec = match registry.get_spec(language) {
    Some(s) => s
    None => {
      println(
        "Error: KGF spec is missing after language detection: " + language,
      )
      return None
    }
  }
  let tokens = match
    @kgf_features.tokenize_source(content, path, Some(registry)) {
    Some(toks) => toks
    None => {
      println("Error: KGF tokenization failed for file: " + path)
      return None
    }
  }
  if role == role_source {
    Some(collect_source_terms(path, language, spec, tokens))
  } else {
    Some(collect_target_terms(path, language, spec, tokens))
  }
}

///|
fn collect_source_terms(
  path : String,
  language : String,
  spec : @kgf_types.KGFSpec,
  tokens : Array[@kgf_types.Tok],
) -> FileVocabulary {
  let required : Map[String, VocabularyTerm] = {}
  let allowed : Map[String, VocabularyTerm] = {}
  if language == "webidl" {
    add_webidl_source_terms(tokens, path, required, allowed)
  } else if language == "ebnf" {
    add_ebnf_terms(tokens, path, required)
    merge_terms(allowed, sorted_terms(required))
  } else {
    add_generic_terms(tokens, spec, path, required)
    merge_terms(allowed, sorted_terms(required))
  }
  {
    path,
    language,
    required: sorted_terms(required),
    allowed: sorted_terms(allowed),
    observed: [],
  }
}

///|
fn collect_target_terms(
  path : String,
  language : String,
  spec : @kgf_types.KGFSpec,
  tokens : Array[@kgf_types.Tok],
) -> FileVocabulary {
  let observed : Map[String, VocabularyTerm] = {}
  if language == "webidl" {
    add_webidl_observed_terms(tokens, path, observed)
  } else if language == "ebnf" {
    add_ebnf_terms(tokens, path, observed)
  } else if language == "moonbit" {
    let conformance_count = add_moonbit_conformance_terms(
      tokens, path, observed,
    )
    if conformance_count == 0 {
      add_generic_terms(tokens, spec, path, observed)
    }
  } else {
    add_generic_terms(tokens, spec, path, observed)
  }
  {
    path,
    language,
    required: [],
    allowed: [],
    observed: sorted_terms(observed),
  }
}

///|
fn FileVocabulary::summary(self : FileVocabulary) -> VocabularyFileSummary {
  {
    path: self.path,
    language: self.language,
    required_count: self.required.length(),
    allowed_count: self.allowed.length(),
    observed_count: self.observed.length(),
  }
}

///|
fn add_webidl_source_terms(
  tokens : Array[@kgf_types.Tok],
  origin : String,
  required : Map[String, VocabularyTerm],
  allowed : Map[String, VocabularyTerm],
) -> Unit {
  for name in extract_webidl_interfaces(tokens) {
    add_term(required, term_kind_interface, name, origin)
    add_term(allowed, term_kind_interface, name, origin)
  }
  for name in extract_webidl_members(tokens) {
    add_term(allowed, term_kind_member, name, origin)
  }
}

///|
fn add_webidl_observed_terms(
  tokens : Array[@kgf_types.Tok],
  origin : String,
  observed : Map[String, VocabularyTerm],
) -> Unit {
  for name in extract_webidl_interfaces(tokens) {
    add_term(observed, term_kind_interface, name, origin)
  }
  for name in extract_webidl_members(tokens) {
    add_term(observed, term_kind_member, name, origin)
  }
}

///|
fn add_ebnf_terms(
  tokens : Array[@kgf_types.Tok],
  origin : String,
  terms : Map[String, VocabularyTerm],
) -> Unit {
  let mut i = 0
  while i < tokens.length() {
    let kind = tokens[i].get_kind()
    if kind == "RuleNumber" {
      let name_idx = next_non_noise(tokens, i + 1)
      if name_idx < tokens.length() && tokens[name_idx].get_kind() == "Ident" {
        add_term(terms, term_kind_symbol, tokens[name_idx].get_text(), origin)
        i = name_idx
      }
    } else if kind == "Literal" {
      add_term(terms, term_kind_literal, tokens[i].get_text(), origin)
    }
    i += 1
  }
}

///|
fn add_generic_terms(
  tokens : Array[@kgf_types.Tok],
  spec : @kgf_types.KGFSpec,
  origin : String,
  terms : Map[String, VocabularyTerm],
) -> Unit {
  let coverage_set = @kgf_features.build_coverage_token_set(spec~)
  let vocabulary_set = @kgf_features.build_vocabulary_token_set(spec~)
  for tok in tokens {
    let kind = tok.get_kind()
    if coverage_set.contains(kind) {
      add_term(terms, term_kind_symbol, tok.get_value(), origin)
    }
    if is_string_like_kind(kind) {
      add_term(terms, term_kind_literal, tok.get_text(), origin)
    }
    if vocabulary_set.contains(kind) {
      add_vocab_words(terms, tok.get_text(), origin)
    }
  }
}

///|
fn add_moonbit_conformance_terms(
  tokens : Array[@kgf_types.Tok],
  origin : String,
  observed : Map[String, VocabularyTerm],
) -> Int {
  let mut count = 0
  let mut i = 0
  while i < tokens.length() {
    if is_ident_text(tokens[i], term_kind_interface) {
      let colon = next_non_noise(tokens, i + 1)
      let str_idx = next_non_noise(tokens, colon + 1)
      if colon < tokens.length() &&
        tokens[colon].get_kind() == "COLON" &&
        is_string_token_at(tokens, str_idx) {
        add_term(
          observed,
          term_kind_interface,
          tokens[str_idx].get_value(),
          origin,
        )
        count += 1
      }
    }
    if is_ident_text(tokens[i], "all_missing") ||
      is_ident_text(tokens[i], "all_implemented") {
      let lparen = next_non_noise(tokens, i + 1)
      let str_idx = next_non_noise(tokens, lparen + 1)
      if lparen < tokens.length() &&
        tokens[lparen].get_kind() == "LPAREN" &&
        is_string_token_at(tokens, str_idx) {
        add_term(
          observed,
          term_kind_interface,
          tokens[str_idx].get_value(),
          origin,
        )
        count += 1
      }
    }
    if is_ident_text(tokens[i], "idl_member") {
      let lparen = next_non_noise(tokens, i + 1)
      let str_idx = next_non_noise(tokens, lparen + 1)
      if lparen < tokens.length() &&
        tokens[lparen].get_kind() == "LPAREN" &&
        is_string_token_at(tokens, str_idx) {
        let value = strip_wrapping_quotes(tokens[str_idx].get_value())
        if normalize_value(value) != "constructor" {
          add_term(observed, term_kind_member, value, origin)
          count += 1
        }
      }
    }
    i += 1
  }
  count
}

///|
fn extract_webidl_interfaces(tokens : Array[@kgf_types.Tok]) -> Array[String] {
  let names : Map[String, Bool] = {}
  let mut i = 0
  while i < tokens.length() {
    if tokens[i].get_kind() == "KW_interface" {
      let mut j = next_non_noise(tokens, i + 1)
      if j < tokens.length() && tokens[j].get_kind() == "KW_mixin" {
        j = next_non_noise(tokens, j + 1)
      }
      if j < tokens.length() && tokens[j].get_kind() == "Ident" {
        names[tokens[j].get_text()] = true
        i = j
      }
    }
    i += 1
  }
  sorted_keys(names)
}

///|
fn extract_webidl_members(tokens : Array[@kgf_types.Tok]) -> Array[String] {
  let members : Map[String, Bool] = {}
  let mut i = 0
  while i < tokens.length() {
    if tokens[i].get_kind() != "KW_interface" {
      i += 1
      continue
    }
    let body_start = find_next_kind(tokens, i + 1, "LBRACE")
    match body_start {
      Some(start) =>
        match find_matching_rbrace(tokens, start) {
          Some(end_) => {
            scan_webidl_interface_body(tokens, start + 1, end_, members)
            i = end_
          }
          None => i = start
        }
      None => ()
    }
    i += 1
  }
  sorted_keys(members)
}

///|
fn scan_webidl_interface_body(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  end_ : Int,
  members : Map[String, Bool],
) -> Unit {
  let stmt : Array[@kgf_types.Tok] = []
  let mut brace_depth = 0
  let mut i = start
  while i < end_ {
    let tok = tokens[i]
    let kind = tok.get_kind()
    if kind == "LBRACE" {
      brace_depth += 1
      stmt.push(tok)
    } else if kind == "RBRACE" {
      if brace_depth > 0 {
        brace_depth -= 1
        stmt.push(tok)
      }
    } else if kind == "SEMI" && brace_depth == 0 {
      add_webidl_member_from_statement(stmt, members)
      stmt.clear()
    } else if !is_noise_kind(kind) {
      stmt.push(tok)
    }
    i += 1
  }
}

///|
fn add_webidl_member_from_statement(
  stmt : Array[@kgf_types.Tok],
  members : Map[String, Bool],
) -> Unit {
  if stmt.length() == 0 {
    return
  }
  if contains_kind(stmt, "KW_constructor") {
    return
  }
  if contains_kind(stmt, "KW_const") {
    match last_ident_before_kind(stmt, "EQ") {
      Some(name) => members[name] = true
      None => ()
    }
    return
  }
  if contains_kind(stmt, "KW_attribute") {
    match last_ident(stmt) {
      Some(name) => members[name] = true
      None => ()
    }
    return
  }
  match method_name_from_statement(stmt) {
    Some(name) => members[name] = true
    None => ()
  }
}

///|
fn method_name_from_statement(stmt : Array[@kgf_types.Tok]) -> String? {
  let mut bracket_depth = 0
  for i, tok in stmt {
    let kind = tok.get_kind()
    if kind == "LBRACKET" {
      bracket_depth += 1
    } else if kind == "RBRACKET" {
      if bracket_depth > 0 {
        bracket_depth -= 1
      }
    } else if kind == "LPAREN" && bracket_depth == 0 && i > 0 {
      let prev = previous_non_noise_in_stmt(stmt, i - 1)
      if prev >= 0 && stmt[prev].get_kind() == "Ident" {
        return Some(stmt[prev].get_text())
      }
    }
  }
  None
}

///|
fn last_ident(stmt : Array[@kgf_types.Tok]) -> String? {
  let mut i = stmt.length() - 1
  while i >= 0 {
    if stmt[i].get_kind() == "Ident" {
      return Some(stmt[i].get_text())
    }
    i -= 1
  }
  None
}

///|
fn last_ident_before_kind(
  stmt : Array[@kgf_types.Tok],
  stop_kind : String,
) -> String? {
  let mut end_ = stmt.length()
  for i, tok in stmt {
    if tok.get_kind() == stop_kind {
      end_ = i
      break
    }
  }
  if end_ == 0 {
    return None
  }
  let mut i = end_ - 1
  while i >= 0 {
    if stmt[i].get_kind() == "Ident" {
      return Some(stmt[i].get_text())
    }
    i -= 1
  }
  None
}

///|
fn add_term(
  terms : Map[String, VocabularyTerm],
  kind : String,
  raw_value : String,
  origin : String,
) -> Unit {
  let value = strip_wrapping_quotes(raw_value)
  let normalized = normalize_value(value)
  if normalized.length() == 0 {
    return
  }
  let key = kind + ":" + normalized
  if !terms.contains(key) {
    terms[key] = { key, kind, value, origin }
  }
}

///|
fn add_vocab_words(
  terms : Map[String, VocabularyTerm],
  text : String,
  origin : String,
) -> Unit {
  let features : Array[String] = []
  @kgf_tokenize.sub_tokenize_vocab(text, features)
  for feature in features {
    add_term(
      terms,
      term_kind_word,
      @kgf_tokenize.feature_value(feature),
      origin,
    )
  }
}

///|
fn merge_terms(
  target : Map[String, VocabularyTerm],
  source : Array[VocabularyTerm],
) -> Unit {
  for term in source {
    if !target.contains(term.key) {
      target[term.key] = term
    }
  }
}

///|
fn assess_issue_terms(
  terms : Array[VocabularyTerm],
  evidence_pool : Map[String, VocabularyTerm],
) -> Array[VocabularyIssueAssessment] {
  let assessments : Array[VocabularyIssueAssessment] = []
  for term in terms {
    let same_value = find_same_value_evidence(term, evidence_pool)
    if same_value.length() > 0 {
      assessments.push(
        issue_assessment(
          term, issue_classification_report_precision, issue_reason_same_value_different_kind,
          same_value,
        ),
      )
      continue
    }
    let alias_evidence = find_alias_evidence(term, evidence_pool)
    if alias_evidence.length() > 0 {
      assessments.push(
        issue_assessment(
          term, issue_classification_report_precision, issue_reason_probable_name_alias,
          alias_evidence,
        ),
      )
      continue
    }
    if is_short_grammar_literal(term) {
      assessments.push(
        issue_assessment(
          term,
          issue_classification_output_noise,
          issue_reason_short_grammar_literal,
          [],
        ),
      )
      continue
    }
    assessments.push(
      issue_assessment(
        term,
        issue_classification_unresolved,
        issue_reason_no_target_evidence,
        [],
      ),
    )
  }
  assessments
}

///|
fn issue_assessment(
  term : VocabularyTerm,
  classification : String,
  reason : String,
  evidence_terms : Array[VocabularyTerm],
) -> VocabularyIssueAssessment {
  { term, classification, reason, evidence_terms }
}

///|
fn find_same_value_evidence(
  term : VocabularyTerm,
  evidence_pool : Map[String, VocabularyTerm],
) -> Array[VocabularyTerm] {
  let result : Array[VocabularyTerm] = []
  let wanted = canonical_name(term.value)
  if wanted.length() == 0 {
    return result
  }
  for entry in evidence_pool {
    let candidate = entry.1
    if candidate.key == term.key {
      continue
    }
    if canonical_name(candidate.value) == wanted {
      result.push(candidate)
      if result.length() >= 5 {
        break
      }
    }
  }
  sort_terms(result)
  result
}

///|
fn find_alias_evidence(
  term : VocabularyTerm,
  evidence_pool : Map[String, VocabularyTerm],
) -> Array[VocabularyTerm] {
  let result : Array[VocabularyTerm] = []
  let wanted = canonical_name(term.value)
  let base = canonical_base_name(term.value)
  if wanted.length() < 4 && base.length() < 4 {
    return result
  }
  for entry in evidence_pool {
    let candidate = entry.1
    if candidate.kind != term.kind {
      continue
    }
    let cand = canonical_name(candidate.value)
    if cand.length() == 0 {
      continue
    }
    if cand.contains(wanted) ||
      wanted.contains(cand) ||
      (base.length() >= 4 && cand.contains(base)) {
      result.push(candidate)
      if result.length() >= 5 {
        break
      }
    }
  }
  sort_terms(result)
  result
}

///|
fn count_assessments(
  assessments : Array[VocabularyIssueAssessment],
  classification : String,
) -> Int {
  let mut count = 0
  for item in assessments {
    if item.classification == classification {
      count += 1
    }
  }
  count
}

///|
fn count_checked_assessments(
  direction : String,
  missing_assessments : Array[VocabularyIssueAssessment],
  drift_assessments : Array[VocabularyIssueAssessment],
  classification : String,
) -> Int {
  if !direction_checks_drift(direction) {
    return count_assessments(missing_assessments, classification)
  }
  if !direction_checks_missing(direction) {
    return count_assessments(drift_assessments, classification)
  }
  count_assessments(missing_assessments, classification) +
  count_assessments(drift_assessments, classification)
}

///|
fn is_short_grammar_literal(term : VocabularyTerm) -> Bool {
  if term.kind != term_kind_literal {
    return false
  }
  let value = strip_wrapping_quotes(term.value)
  if value.length() == 0 || value.length() > 2 {
    return false
  }
  for ch in value {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') {
      return false
    }
  }
  true
}

///|
fn canonical_base_name(value : String) -> String {
  let name = canonical_name(value)
  let suffixes = [
    "expression", "expr", "locationpath", "path", "specifier", "operator", "token",
    "reference", "call",
  ]
  for suffix in suffixes {
    if name.length() > suffix.length() + 1 && name.has_suffix(suffix) {
      return name[:name.length() - suffix.length()].to_owned()
    }
  }
  name
}

///|
fn canonical_name(value : String) -> String {
  let stripped = strip_wrapping_quotes(value).to_lower()
  let buf = StringBuilder::new()
  for ch in stripped {
    if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn sorted_term_difference(
  left : Map[String, VocabularyTerm],
  right : Map[String, VocabularyTerm],
) -> Array[VocabularyTerm] {
  let result : Array[VocabularyTerm] = []
  for entry in left {
    if !right.contains(entry.0) {
      result.push(entry.1)
    }
  }
  sort_terms(result)
  result
}

///|
fn sorted_terms(terms : Map[String, VocabularyTerm]) -> Array[VocabularyTerm] {
  let result : Array[VocabularyTerm] = []
  for entry in terms {
    result.push(entry.1)
  }
  sort_terms(result)
  result
}

///|
fn sort_terms(terms : Array[VocabularyTerm]) -> Unit {
  terms.sort_by(fn(a, b) { a.key.compare(b.key) })
}

///|
fn combined_paths(left : Array[String], right : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for path in left {
    result.push(path)
  }
  for path in right {
    result.push(path)
  }
  result
}

///|
fn normalize_value(value : String) -> String {
  strip_wrapping_quotes(value).to_lower()
}

///|
fn strip_wrapping_quotes(value : String) -> String {
  if value.length() >= 2 {
    let last = value.length() - 1
    if value[0] == '"' && value[last] == '"' {
      return value[1:last].to_owned()
    }
    if value[0] == '\'' && value[last] == '\'' {
      return value[1:last].to_owned()
    }
  }
  if value.length() >= 4 && value.has_prefix("#|") && value.has_suffix("|#") {
    return value[2:value.length() - 2].to_owned()
  }
  value
}

///|
fn is_string_like_kind(kind : String) -> Bool {
  kind == "String" ||
  kind == "StringLit" ||
  kind == "MultiString" ||
  kind == "Literal"
}

///|
fn contains_kind(tokens : Array[@kgf_types.Tok], kind : String) -> Bool {
  for tok in tokens {
    if tok.get_kind() == kind {
      return true
    }
  }
  false
}

///|
fn previous_non_noise_in_stmt(stmt : Array[@kgf_types.Tok], start : Int) -> Int {
  let mut i = start
  while i >= 0 {
    if !is_noise_kind(stmt[i].get_kind()) {
      return i
    }
    i -= 1
  }
  -1
}

///|
fn find_next_kind(
  tokens : Array[@kgf_types.Tok],
  start : Int,
  kind : String,
) -> Int? {
  for i = start; i < tokens.length(); i = i + 1 {
    if tokens[i].get_kind() == kind {
      return Some(i)
    }
  }
  None
}

///|
fn find_matching_rbrace(tokens : Array[@kgf_types.Tok], start : Int) -> Int? {
  let mut depth = 0
  for i = start; i < tokens.length(); i = i + 1 {
    let kind = tokens[i].get_kind()
    if kind == "LBRACE" {
      depth += 1
    } else if kind == "RBRACE" {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

///|
fn next_non_noise(tokens : Array[@kgf_types.Tok], start : Int) -> Int {
  let mut i = start
  while i < tokens.length() && is_noise_kind(tokens[i].get_kind()) {
    i += 1
  }
  i
}

///|
fn is_noise_kind(kind : String) -> Bool {
  kind == "NL" ||
  kind == "LineComment" ||
  kind == "BlockComment" ||
  kind == "DocComment" ||
  kind == "DocLine" ||
  kind == "DocSection" ||
  kind == "Comment"
}

///|
fn is_ident_text(tok : @kgf_types.Tok, text : String) -> Bool {
  tok.get_kind() == "Ident" && tok.get_text() == text
}

///|
fn is_string_token_at(tokens : Array[@kgf_types.Tok], idx : Int) -> Bool {
  idx < tokens.length() && is_string_like_kind(tokens[idx].get_kind())
}

///|
fn sorted_keys(set : Map[String, Bool]) -> Array[String] {
  let result : Array[String] = []
  for entry in set {
    result.push(entry.0)
  }
  result.sort()
  result
}
