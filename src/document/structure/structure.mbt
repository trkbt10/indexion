///|
pub(all) struct Heading {
  marker : String
  text : String
  line : Int
  level : Int?
}

///|
pub struct DocumentSection {
  marker : String
  title : String
  line : Int
  end_line : Int
  content : String
  level : Int?
}

///|
pub struct DocumentFact {
  kind : String
  payload : Map[String, Json]
}

///|
pub struct DocumentTablePair {
  label : String
  literal : String
} derive(Eq, Debug, ToJson, @json.FromJson)

///|
pub impl Show for DocumentTablePair with output(self, logger) {
  to_repr(self).output(logger)
}

///|
pub struct InterpretedDocument {
  facts : Array[DocumentFact]
}

///|
pub fn json_int_field(payload : Map[String, Json], key : String) -> Int {
  match payload.get(key) {
    Some(Number(value, ..)) => value.to_int()
    Some(String(value)) => @text_parse.parse_int_or_zero(value)
    _ => 0
  }
}

///|
pub fn json_string_array_field(
  payload : Map[String, Json],
  key : String,
) -> Array[String] {
  match payload.get(key) {
    Some(Array(values)) => {
      let result : Array[String] = []
      for value in values {
        match value {
          String(text) => if !result.contains(text) { result.push(text) }
          Number(n, ..) => {
            let text = n.to_int().to_string()
            if !result.contains(text) {
              result.push(text)
            }
          }
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn json_pair_array_field(
  payload : Map[String, Json],
  key : String,
) -> Array[DocumentTablePair] {
  match payload.get(key) {
    Some(Array(values)) => {
      let result : Array[DocumentTablePair] = []
      for value in values {
        match value {
          Object(obj) => {
            let label = match obj.get("label") {
              Some(String(text)) => text
              Some(Number(n, ..)) => n.to_int().to_string()
              _ => ""
            }
            let literal = match obj.get("literal") {
              Some(String(text)) => text
              Some(Number(n, ..)) => n.to_int().to_string()
              _ => ""
            }
            if label.length() == 0 || literal.length() == 0 {
              continue
            }
            let pair = { label, literal }
            if !result.contains(pair) {
              result.push(pair)
            }
          }
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn merge_unique_pairs(
  target : Array[DocumentTablePair],
  values : Array[DocumentTablePair],
) -> Unit {
  for value in values {
    if !target.contains(value) {
      target.push(value)
    }
  }
}

///|
pub fn section_refs_for_line(
  interpreted : InterpretedDocument,
  line : Int,
) -> Array[String] {
  let result : Array[String] = []
  for fact in interpreted.facts {
    if fact.kind != "document_section_refs" ||
      json_int_field(fact.payload, "line") != line {
      continue
    }
    @text_ops.merge_unique_strings(
      result,
      json_string_array_field(fact.payload, "refs"),
    )
  }
  result
}

///|
pub fn literals_for_line(
  interpreted : InterpretedDocument,
  line : Int,
) -> Array[String] {
  let result : Array[String] = []
  for fact in interpreted.facts {
    if fact.kind != "document_literals" ||
      json_int_field(fact.payload, "line") != line {
      continue
    }
    @text_ops.merge_unique_strings(
      result,
      json_string_array_field(fact.payload, "values"),
    )
  }
  result
}

///|
pub fn table_pairs_for_line(
  interpreted : InterpretedDocument,
  line : Int,
) -> Array[DocumentTablePair] {
  let result : Array[DocumentTablePair] = []
  for fact in interpreted.facts {
    if fact.kind != "document_table_pairs" ||
      json_int_field(fact.payload, "line") != line {
      continue
    }
    merge_unique_pairs(result, json_pair_array_field(fact.payload, "pairs"))
  }
  result
}

///|
pub fn load_document_sections(
  content : String,
  path : String,
  registry : @kgf_registry.KGFRegistry?,
) -> Array[DocumentSection] {
  let reg = match registry {
    Some(value) => value
    None => return []
  }
  let toolkit_reg = @kgf_toolkit.ToolkitRegistry::new(reg)
  let toolkit = match toolkit_reg.for_path(path) {
    Some(value) => value
    None => return []
  }
  let prepared = toolkit.preprocess(content)
  let tokens = toolkit.get_lexer().tokenize(prepared)
  extract_document_sections(
    tokens,
    prepared,
    spec=Some(toolkit.get_spec()),
    path~,
  )
}

///|
pub fn extract_headings(
  tokens : Array[@kgf_types.Tok],
  spec? : @kgf_types.KGFSpec? = None,
  source? : String = "",
  path? : String = "",
) -> Array[Heading] {
  let headings : Array[Heading] = []
  let the_spec = match spec {
    Some(value) => value
    None => return headings
  }
  let section_token = match the_spec.get_feature("section_token") {
    Some(values) =>
      if values.length() > 0 {
        values[0]
      } else {
        return headings
      }
    None => return headings
  }
  let text_token_set : Map[String, Bool] = {}
  match the_spec.get_feature("heading_text_tokens") {
    Some(kinds) =>
      for kind in kinds {
        text_token_set[kind] = true
      }
    None => ()
  }
  let section_is_text = text_token_set.contains(section_token)
  let source_chars = source.to_array()
  let has_source = source_chars.length() > 0
  let mut line = 1
  let mut i = 0
  while i < tokens.length() {
    let tok = tokens[i]
    let kind = tok.get_kind()
    if kind == "NL" {
      line += 1
      i += 1
      continue
    }
    if kind != section_token {
      i += 1
      continue
    }
    let heading_line = if has_source {
      line_from_position(tok.get_pos(), source_chars)
    } else {
      line
    }
    let buf = StringBuilder::new()
    if section_is_text {
      buf.write_string(tok.get_text())
    }
    i += 1
    if !section_is_text {
      while i < tokens.length() {
        let current_kind = tokens[i].get_kind()
        if current_kind == "SKIP" || current_kind == "WS" {
          i += 1
        } else {
          break
        }
      }
      let heading_pos = tok.get_pos()
      let mut first = true
      while i < tokens.length() {
        let current_kind = tokens[i].get_kind()
        if current_kind == "NL" || current_kind == section_token {
          break
        }
        if has_source &&
          crossed_newline(heading_pos, tokens[i].get_pos(), source_chars) {
          break
        }
        if text_token_set.contains(current_kind) {
          if !first {
            buf.write_string(" ")
          }
          buf.write_string(tokens[i].get_text())
          first = false
        }
        i += 1
      }
    }
    let text = buf.to_string()
    if text.length() > 0 {
      headings.push({
        marker: tok.get_text(),
        text,
        line: heading_line,
        level: None,
      })
    }
  }
  merge_heading_levels(headings, source, path, the_spec)
}

///|
fn line_from_position(pos : Int, source_chars : Array[Char]) -> Int {
  let mut line = 1
  for i = 0; i < pos && i < source_chars.length(); i = i + 1 {
    if source_chars[i] == '\n' {
      line += 1
    }
  }
  line
}

///|
fn crossed_newline(start : Int, end : Int, source_chars : Array[Char]) -> Bool {
  for i = start; i < end && i < source_chars.length(); i = i + 1 {
    if source_chars[i] == '\n' {
      return true
    }
  }
  false
}

///|
pub fn extract_document_sections(
  tokens : Array[@kgf_types.Tok],
  content : String,
  spec? : @kgf_types.KGFSpec? = None,
  path? : String = "",
) -> Array[DocumentSection] {
  guard spec is Some(_) else { return [] }
  let headings = extract_headings(tokens, spec~, source=content, path~)
  let lines = @text_ops.split_by_newline(content)
  let sections : Array[DocumentSection] = []
  for idx, heading in headings {
    let end_line = if idx + 1 < headings.length() {
      headings[idx + 1].line - 1
    } else {
      lines.length()
    }
    let buf = StringBuilder::new()
    for j = heading.line; j < end_line && j < lines.length(); j = j + 1 {
      buf.write_string(lines[j])
      buf.write_string("\n")
    }
    let section_content = buf.to_string()
    if section_content.length() > 0 {
      sections.push({
        marker: heading.marker,
        title: heading.text,
        line: heading.line,
        end_line,
        content: section_content,
        level: heading.level,
      })
    }
  }
  sections
}

///|
pub fn interpret_document(
  content : String,
  path : String,
  spec : @kgf_types.KGFSpec,
) -> InterpretedDocument {
  let toolkit = @kgf_toolkit.LanguageToolkit::from_spec(spec)
  let prepared = toolkit.preprocess(content)
  let tokens = toolkit.get_lexer().tokenize(prepared)
  let sections = extract_document_sections(
    tokens,
    prepared,
    spec=Some(spec),
    path~,
  )
  { facts: eval_document_facts(sections, path, spec) }
}

///|
fn merge_heading_levels(
  headings : Array[Heading],
  content : String,
  path : String,
  spec : @kgf_types.KGFSpec,
) -> Array[Heading] {
  if headings.length() == 0 || path.length() == 0 {
    return headings
  }
  let total_lines = @text_ops.split_by_newline(content).length()
  let sections : Array[DocumentSection] = []
  for idx, heading in headings {
    let end_line = if idx + 1 < headings.length() {
      headings[idx + 1].line - 1
    } else {
      total_lines
    }
    sections.push({
      marker: heading.marker,
      title: heading.text,
      line: heading.line,
      end_line,
      content: "",
      level: None,
    })
  }
  let levels = heading_levels_by_line(eval_document_facts(sections, path, spec))
  let result : Array[Heading] = []
  for heading in headings {
    let level = match levels.get(heading.line) {
      Some(value) => Some(value)
      None => heading.level
    }
    result.push({ ..heading, level, })
  }
  result
}

///|
fn heading_levels_by_line(facts : Array[DocumentFact]) -> Map[Int, Int] {
  let result : Map[Int, Int] = {}
  for fact in facts {
    if fact.kind != "document_heading" {
      continue
    }
    let line = json_int_or_zero(fact.payload.get("line"))
    let level = json_int_or_zero(fact.payload.get("level"))
    if line > 0 && level > 0 {
      result.set(line, level)
    }
  }
  result
}

///|
fn json_int_or_zero(value : Json?) -> Int {
  match value {
    Some(Number(n, ..)) => n.to_int()
    Some(String(text)) => @text_parse.parse_int_or_zero(text)
    _ => 0
  }
}

///|
fn eval_document_facts(
  sections : Array[DocumentSection],
  path : String,
  spec : @kgf_types.KGFSpec,
) -> Array[DocumentFact] {
  if sections.length() == 0 {
    return []
  }
  let graph = @graph.CodeGraph::new()
  let _ = graph.get_or_add_module(path, file=Some(path))
  let ctx = @kgf_semantics.SemEvalCtx::new(
    spec,
    graph,
    path,
    "",
    spec.get_language(),
    fn(_) { false },
  )
  for section in sections {
    let labels : Map[String, Json] = {}
    labels.set("title", section.title.to_json())
    labels.set("title_text", section.title.to_json())
    labels.set("body", section.content.to_json())
    labels.set("body_text", section.content.to_json())
    labels.set("content", section.content.to_json())
    labels.set("content_text", section.content.to_json())
    labels.set("marker", section.marker.to_json())
    labels.set("line", section.line.to_json())
    labels.set("end_line", section.end_line.to_json())
    match section.level {
      Some(level) => labels.set("level", level.to_json())
      None => ()
    }
    @kgf_semantics.eval_rule_semantics("DocumentSection", labels, ctx)
  }
  let facts : Array[DocumentFact] = []
  for event in ctx.get_events() {
    if event.0 != "Note" {
      continue
    }
    match event.1.get("type") {
      Some(String(kind)) =>
        match event.1.get("payload") {
          Some(Object(payload)) => facts.push({ kind, payload })
          _ => ()
        }
      _ => ()
    }
  }
  facts
}
