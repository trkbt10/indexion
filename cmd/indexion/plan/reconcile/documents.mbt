///|
fn document_path_scope(config : ReconcileConfig) -> @scope.PathScope {
  if not(config.documents.path_scope.is_empty()) ||
    config.documents.doc_paths.is_empty() {
    config.documents.path_scope
  } else {
    @config_paths.resolve_reconcile_document_scope(
      config.documents.scope_name,
      doc_paths=config.documents.doc_paths,
      doc_specs=config.documents.doc_specs,
    ).path_scope
  }
}

///|
fn is_document_path(
  path : String,
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> Bool {
  let rel = @config_paths.relative_to(config.target_dir, path)
  let subject = @scope.PathSubject::new(rel, additional_paths=[path])
  if not(document_path_scope(config).matches(subject)) {
    return false
  }
  select_document_spec(path, config, registry) is Some(_)
}

///|
fn select_document_spec(
  path : String,
  config : ReconcileConfig,
  registry : @registry.KGFRegistry,
) -> String? {
  fn prefer_spec(registry : @registry.KGFRegistry, name : String) -> String? {
    if registry.get_spec(name) is Some(_) {
      Some(name)
    } else {
      None
    }
  }

  let ext = @config_paths.extension(path)
  let basename_ = @config_paths.basename(path)
  let detected = registry.detect_from_path(path)
  let selected = match ext {
    ".md" | ".markdown" | ".mdx" =>
      match prefer_spec(registry, "markdown") {
        Some(spec) => Some(spec)
        None => detected
      }
    ".txt" | ".text" | ".rst" | ".adoc" =>
      match prefer_spec(registry, "plaintext") {
        Some(spec) => Some(spec)
        None =>
          match prefer_spec(registry, "english") {
            Some(spec) => Some(spec)
            None => detected
          }
      }
    ".toml" =>
      match detected {
        Some(spec) =>
          if spec.contains("toml") {
            Some(spec)
          } else {
            prefer_spec(registry, "toml")
          }
        None => prefer_spec(registry, "toml")
      }
    _ =>
      if basename_ == "README" || basename_.has_prefix("README.") {
        match prefer_spec(registry, "markdown") {
          Some(spec) => Some(spec)
          None => detected
        }
      } else {
        detected
      }
  }
  match selected {
    Some(spec) =>
      if config.documents.doc_specs.length() == 0 ||
        contains_string(config.documents.doc_specs, spec) {
        Some(spec)
      } else {
        None
      }
    None => None
  }
}

///|
fn extract_document_fragments(
  path : String,
  spec : String,
  content : String,
) -> Array[DocFragment] {
  match spec {
    "markdown" => extract_markdown_fragments(path, spec, content)
    "toml" | "pyproject-toml" | "cargo-toml" =>
      extract_toml_fragments(path, spec, content)
    _ => extract_plaintext_fragments(path, spec, content)
  }
}

///|
fn make_fragment(
  path : String,
  spec : String,
  kind : String,
  title : String,
  content : String,
) -> DocFragment {
  let normalized_title = if title.length() > 0 {
    title
  } else {
    @config_paths.basename(path)
  }
  let normalized_content = normalize_spaces(content)
  let fragment_hash = make_hash([
    path, spec, kind, normalized_title, normalized_content,
  ])
  let fragment_id = "doc:" + fragment_hash
  {
    id: fragment_id,
    path,
    spec,
    kind,
    title: normalized_title,
    content: normalized_content,
    preview: preview_text(normalized_content),
    fragment_hash,
  }
}

///|
fn markdown_heading_text(line : String) -> String {
  let chars = line.to_array()
  let mut idx = 0
  while idx < chars.length() && chars[idx] == '#' {
    idx += 1
  }
  while idx < chars.length() && chars[idx] == ' ' {
    idx += 1
  }
  trim_string(substring(line, idx, line.length()))
}

///|
fn extract_markdown_fragments(
  path : String,
  spec : String,
  content : String,
) -> Array[DocFragment] {
  let fragments : Array[DocFragment] = []
  let lines = split_lines(content)
  let paragraph : Array[String] = []
  let mut heading = @config_paths.basename(path)
  fn flush_markdown_paragraph(
    fragments : Array[DocFragment],
    path : String,
    spec : String,
    heading : String,
    paragraph : Array[String],
  ) -> Unit {
    if paragraph.length() == 0 {
      return
    }
    let text = trim_string(join_lines(paragraph))
    paragraph.clear()
    if text.length() == 0 {
      return
    }
    fragments.push(make_fragment(path, spec, "paragraph", heading, text))
  }
  for line in lines {
    let trimmed = trim_string(line)
    if trimmed.has_prefix("#") {
      flush_markdown_paragraph(fragments, path, spec, heading, paragraph)
      let heading_text = markdown_heading_text(trimmed)
      if heading_text.length() > 0 {
        heading = heading_text
        fragments.push(
          make_fragment(path, spec, "heading", heading_text, heading_text),
        )
      }
      continue
    }
    if is_blank_line(trimmed) {
      flush_markdown_paragraph(fragments, path, spec, heading, paragraph)
      continue
    }
    paragraph.push(trimmed)
  }
  flush_markdown_paragraph(fragments, path, spec, heading, paragraph)
  fragments
}

///|
fn extract_plaintext_fragments(
  path : String,
  spec : String,
  content : String,
) -> Array[DocFragment] {
  let fragments : Array[DocFragment] = []
  let lines = split_lines(content)
  let paragraph : Array[String] = []
  let mut title = @config_paths.basename(path)
  fn flush_plaintext_paragraph(
    fragments : Array[DocFragment],
    path : String,
    spec : String,
    title : String,
    paragraph : Array[String],
  ) -> Unit {
    if paragraph.length() == 0 {
      return
    }
    let text = trim_string(join_lines(paragraph))
    paragraph.clear()
    if text.length() == 0 {
      return
    }
    fragments.push(make_fragment(path, spec, "paragraph", title, text))
  }
  for line in lines {
    let trimmed = trim_string(line)
    if is_blank_line(trimmed) {
      flush_plaintext_paragraph(fragments, path, spec, title, paragraph)
      continue
    }
    if paragraph.length() == 0 &&
      title == @config_paths.basename(path) &&
      trimmed.length() <= 120 {
      title = trimmed
    }
    paragraph.push(trimmed)
  }
  flush_plaintext_paragraph(fragments, path, spec, title, paragraph)
  fragments
}

///|
fn extract_toml_fragments(
  path : String,
  spec : String,
  content : String,
) -> Array[DocFragment] {
  let fragments : Array[DocFragment] = []
  let mut section = ""
  for raw_line in split_lines(content) {
    let line = @config_paths.trim_toml_comment(raw_line)
    if line.length() == 0 {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      section = trim_string(substring(line, 1, line.length() - 1))
      fragments.push(
        make_fragment(path, spec, "section", section, "[" + section + "]"),
      )
      continue
    }
    let eq_idx = last_index_of(line, '=')
    if eq_idx <= 0 {
      fragments.push(
        make_fragment(
          path,
          spec,
          "line",
          if section.length() > 0 {
            section
          } else {
            @config_paths.basename(path)
          },
          line,
        ),
      )
      continue
    }
    let key = trim_string(substring(line, 0, eq_idx))
    let value = trim_string(substring(line, eq_idx + 1, line.length()))
    let title = if section.length() > 0 { section + "." + key } else { key }
    fragments.push(
      make_fragment(path, spec, "entry", title, key + " = " + value),
    )
  }
  fragments
}
