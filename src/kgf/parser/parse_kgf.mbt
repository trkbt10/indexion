///|
/// # KGF File Structure
///
/// KGF (Knowledge Graph Format) is a domain-specific language for defining
/// language specifications. Each KGF file describes how to tokenize, parse,
/// and extract semantic information from source code.
///
/// ## File Structure
///
/// ```ebnf
/// KGFFile      ::= Header Section*
/// Header       ::= "kgf" Version NL HeaderField* NL
/// Version      ::= FLOAT                          (* e.g., "0.6" *)
/// HeaderField  ::= "language:" LanguageName NL
///                | "sources:" SourceList NL
/// SourceList   ::= Source ( "," Source )*
/// Section      ::= "===" SectionName NL SectionBody
/// SectionName  ::= "lex" | "grammar" | "attrs" | "features"
///                | "semantics" | "resolver" | "preprocess"
///                | "preprocess_fst" | "ignore" | "classify"
/// ```
///
/// ## Header Fields
///
/// | Field | Required | Description |
/// |-------|----------|-------------|
/// | `language` | Yes | Language name for this spec |
/// | `sources` | Yes | Source file extensions (`.ts`, `.mbt`) |
///
/// ## Sections Overview
///
/// | Section | Purpose | Format |
/// |---------|---------|--------|
/// | `lex` | Token definitions | `SKIP` / `TOKEN` rules |
/// | `grammar` | PEG grammar rules | `Name -> expression` |
/// | `attrs` | Attribute actions | `on Rule: action; ...` |
/// | `features` | Consumer-facing metadata | `name: value1, value2` |
/// | `semantics` | Graph construction | `on Rule { statements }` |
/// | `resolver` | Module resolution | YAML-like config |
/// | `preprocess` | Preprocessor names | Line-based list |
/// | `preprocess_fst` | FST definitions | JSON format |
/// | `ignore` | Ignore patterns | One pattern per line |
/// | `classify` | Classification lexicons | `category: word=weight, ...` |
///
/// ## Example
///
/// ```kgf
/// kgf 0.6
/// language: typescript
/// sources: .ts, .tsx, .d.ts
///
/// === lex
/// SKIP /\s+/
/// TOKEN Ident /[a-zA-Z_][a-zA-Z0-9_]*/
///
/// === grammar
/// Module -> Item*
/// Item -> FnDecl | VarDecl
///
/// === attrs
/// on FnDecl: def id kind=Function
///
/// === features
/// reference_token_kinds: INLINE_CODE
///
/// === semantics
/// on FnDecl {
///   edge declares from $file to $id
/// }
///
/// === resolver
/// module_path_style: slash
/// ```

///|
/// Extracts a section body by heading marker `=== name`.
/// Uses line-start matching to avoid false positives from `===` inside patterns.
fn section(text : String, name : String) -> String {
  let marker = "=== " + name
  let idx = find_line_start_substring(text, marker)
  guard idx >= 0 else { return "" }
  let body = substr_from(text, idx + marker.length())
  let split_idx = find_line_start_substring(body, "===")
  if split_idx >= 0 {
    substr(body, 0, split_idx)
  } else {
    body
  }
}

///|
/// Extracts the header section (everything before the first `===`).
/// Uses line-start matching to avoid false positives from `===` inside patterns.
fn extract_header(text : String) -> String {
  let idx = find_line_start_substring(text, "===")
  if idx >= 0 {
    substr(text, 0, idx)
  } else {
    text
  }
}

///|
/// Extracts language name from the header.
fn extract_language(text : String) -> String {
  let header = extract_header(text)
  let lines = split_lines(header)
  for line in lines {
    let trimmed = trim_str(line)
    if starts_with(trimmed, "language:") {
      return trim_str(substr_from(trimmed, 9))
    }
  }
  "generic"
}

///|
/// Extracts sources from the header.
/// Returns array of source patterns (e.g., [".mbt", ".ts"]).
fn extract_sources(text : String) -> Array[String] {
  let header = extract_header(text)
  let lines = split_lines(header)
  for line in lines {
    let trimmed = trim_str(line)
    if starts_with(trimmed, "sources:") {
      let value = trim_str(substr_from(trimmed, 8))
      return parse_comma_list(value)
    }
  }
  []
}

///|
/// Parses a comma-separated list of values.
fn parse_comma_list(text : String) -> Array[String] {
  let result : Array[String] = []
  let current : Array[Char] = []
  for c in text {
    if c == ',' {
      let item = trim_str(String::from_array(current))
      if item.length() > 0 {
        result.push(item)
      }
      current.clear()
    } else {
      current.push(c)
    }
  }
  let last = trim_str(String::from_array(current))
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
/// KGF header information for fast filtering.
pub struct KGFHeader {
  language : String
  sources : Array[String]
}

///|
pub fn KGFHeader::get_language(self : KGFHeader) -> String {
  self.language
}

///|
pub fn KGFHeader::get_sources(self : KGFHeader) -> Array[String] {
  self.sources
}

///|
/// Fast header-only parsing for filtering specs without full parse.
/// Only extracts language and sources from the header.
pub fn parse_kgf_header(text : String) -> KGFHeader {
  let language = extract_language(text)
  let sources = extract_sources(text)
  { language, sources }
}

///|
/// Parses a full KGF document text into a structured spec.
///
/// Only header, features, resolver, and ignore are parsed eagerly.
/// Heavy sections (lex, grammar, attrs, semantics, preprocess) are
/// stored as raw text and parsed lazily on first access.
pub fn parse_kgf(text : String) -> @types.KGFSpec? {
  let language = extract_language(text)
  let header_sources = extract_sources(text)
  // Phase 1 — eager: lightweight metadata needed for registry mapping
  let features = parse_features(section(text, "features"))
  let resolver = parse_resolver_with_sources(
    section(text, "resolver"),
    header_sources,
  )
  let ignore = parse_ignore(section(text, "ignore"))
  // Phase 2+ — deferred: raw section text stored for lazy parsing
  Some(
    @types.KGFSpec::new_lazy(
      language,
      resolver,
      features,
      ignore,
      section(text, "lex"),
      section(text, "grammar"),
      section(text, "attrs"),
      section(text, "semantics"),
      section(text, "preprocess"),
      section(text, "preprocess_fst"),
      section(text, "classify"),
    ),
  )
}

///|
/// Register lazy parsing callbacks so KGFSpec can defer heavy work.
/// Called at module init time.
fn init {
  @types.parse_lex_lazy.val = fn(source) {
    let result = parse_lex(source)
    (result.get_tokens(), result.get_keyword_kinds())
  }
  @types.parse_grammar_lazy.val = fn(source) { parse_rules(source) }
  @types.parse_attrs_lazy.val = fn(source) { parse_attrs(source) }
  @types.parse_semantics_lazy.val = fn(source) { parse_semantics(source) }
  @types.parse_preprocess_lazy.val = fn(source) { parse_preprocess(source) }
  @types.parse_preprocess_fst_lazy.val = fn(source) {
    parse_preprocess_fst(source)
  }
  @types.parse_classify_lazy.val = fn(source) { parse_classify(source) }
}

///|
/// Parses feature metadata section into name -> values map.
/// Each line is `name: value1, value2`.
fn parse_features(text : String) -> Map[String, Array[String]]? {
  let lines = split_lines(text)
  let result : Map[String, Array[String]] = {}
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() == 0 || starts_with(trimmed, "#") {
      continue
    }
    let separator = find_substring(trimmed, ":")
    if separator < 0 {
      continue
    }
    let name = trim_str(substr(trimmed, 0, separator))
    if name.length() == 0 {
      continue
    }
    let values = parse_comma_list(trim_str(substr_from(trimmed, separator + 1)))
    result.set(name, values)
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
/// Parses ignore section into list of patterns.
/// Each line is a pattern (like .gitignore syntax).
/// Lines starting with # are comments.
fn parse_ignore(text : String) -> Array[String]? {
  let lines = split_lines(text)
  let result : Array[String] = []
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() > 0 && !starts_with(trimmed, "#") {
      result.push(trimmed)
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
/// Parses preprocess section into list of transducer names.
fn parse_preprocess(text : String) -> Array[String]? {
  let lines = split_lines(text)
  let result : Array[String] = []
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() > 0 && !starts_with(trimmed, "#") {
      result.push(trimmed)
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}
