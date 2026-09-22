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
///                | "extends:" LanguageName NL
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
/// | `extends` | No | `language` of a base spec to inherit sections from |
///
/// ## Spec Inheritance (`extends:`)
///
/// `extends: <language>` names another spec — by its `language`, not by its
/// file path — whose sections this spec inherits. The base may live in any
/// subdirectory of the same spec set; inheritance is therefore resolved by
/// the registry after every spec of the directory has been loaded, not here.
///
/// Merging is **section-level override**: for each `=== name` section, the
/// derived spec's text wins whole if the derived spec declares that section
/// at all, and the base's text is used otherwise. There is no line-level or
/// rule-level merging — a derived `=== grammar` replaces the base grammar
/// entirely rather than adding rules to it. This keeps the result of a merge
/// readable straight off the two files.
///
/// `language:` and `sources:` are never inherited: they identify the derived
/// spec and decide which files it claims. A derived spec that declares no
/// `sources:` claims no extensions, exactly as a standalone spec would.
///
/// Chains are allowed (`A extends B`, `B extends C`), and a section is taken
/// from the nearest ancestor that declares it. A cycle, or an `extends:`
/// naming a spec that is not present, leaves the spec unresolved — the
/// registry keeps the spec's own sections and `kgf check` reports the error.
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
/// Extracts a section body by heading marker `=== name`, or `None` when the
/// spec does not declare that section at all.
///
/// The distinction matters for `extends:`: a declared-but-empty section (a
/// bare `=== semantics` with nothing under it) is a deliberate "this spec has
/// no semantics" and must override an inherited one, whereas an absent
/// section is what inheritance fills in.
///
/// Uses line-start matching to avoid false positives from `===` inside patterns.
fn section_opt(text : String, name : String) -> String? {
  let marker = "=== " + name
  let idx = find_line_start_substring(text, marker)
  guard idx >= 0 else { return None }
  let body = substr_from(text, idx + marker.length())
  let split_idx = find_line_start_substring(body, "===")
  if split_idx >= 0 {
    Some(substr(body, 0, split_idx))
  } else {
    Some(body)
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
/// Header field names. Header fields are `name: value` lines before the first
/// `===` marker; these constants are the single source of truth for their
/// spelling, shared by the extractors below.
const HEADER_FIELD_LANGUAGE : String = "language"

///|
const HEADER_FIELD_SOURCES : String = "sources"

///|
const HEADER_FIELD_EXTENDS : String = "extends"

///|
/// Language name used when a spec omits `language:`.
const DEFAULT_LANGUAGE : String = "generic"

///|
/// Reads one `name: value` header field, returning the trimmed value.
/// Returns `None` when the field is absent; returns `Some("")` when the field
/// is present but empty, so callers can tell "not declared" from "declared
/// empty" (an `extends:` with no value is a spec authoring error, not an
/// absent field).
fn extract_header_field(text : String, name : String) -> String? {
  let header = extract_header(text)
  let prefix = name + ":"
  for line in split_lines(header) {
    let trimmed = trim_str(line)
    if trimmed.has_prefix(prefix) {
      return Some(trim_str(substr_from(trimmed, prefix.length())))
    }
  }
  None
}

///|
/// Extracts language name from the header.
fn extract_language(text : String) -> String {
  match extract_header_field(text, HEADER_FIELD_LANGUAGE) {
    Some(value) if value.length() > 0 => value
    _ => DEFAULT_LANGUAGE
  }
}

///|
/// Extracts sources from the header.
/// Returns array of source patterns (e.g., [".mbt", ".ts"]).
fn extract_sources(text : String) -> Array[String] {
  match extract_header_field(text, HEADER_FIELD_SOURCES) {
    Some(value) => parse_comma_list(value)
    None => []
  }
}

///|
/// Extracts the `extends:` base spec name from the header.
/// An `extends:` line with an empty value yields `Some("")` so that the
/// registry and `kgf check` can report it as an error rather than silently
/// treating the spec as standalone.
fn extract_extends(text : String) -> String? {
  extract_header_field(text, HEADER_FIELD_EXTENDS)
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
  /// `extends:` base spec name, `None` when the spec is standalone.
  extends : String?
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
/// Returns the `extends:` base spec name declared in the header.
pub fn KGFHeader::get_extends(self : KGFHeader) -> String? {
  self.extends
}

///|
/// Fast header-only parsing for filtering specs without full parse.
/// Only extracts language, sources and extends from the header.
pub fn parse_kgf_header(text : String) -> KGFHeader {
  let language = extract_language(text)
  let sources = extract_sources(text)
  let extends = extract_extends(text)
  { language, sources, extends, }
}

///|
/// Names of every `=== section` a KGF document may declare, in the order they
/// conventionally appear.
///
/// This is the single source of truth for "what a section is" as far as
/// inheritance is concerned: `KGFSpecSource` keys its section map by these
/// names, and `KGFSpecSource::merge_onto` walks exactly this list. A new
/// section type needs adding here (and to `KGFSpecSource::to_spec`) and
/// nothing else in the inheritance path.
pub fn section_names() -> Array[String] {
  [
    "lex", "grammar", "attrs", "features", "semantics", "resolver", "preprocess",
    "preprocess_fst", "ignore", "classify",
  ]
}

///|
/// A KGF document split into its header fields and raw section texts, before
/// any section is parsed.
///
/// This is the form inheritance operates on. Resolving `extends:` by merging
/// raw section texts — rather than merging parsed sections — keeps the lazy
/// parsing in `KGFSpec` intact (a resolved spec still parses each section
/// only when first accessed) and makes the override rule exactly "the winning
/// text is used", with no merge semantics smuggled into the section parsers.
pub struct KGFSpecSource {
  language : String
  sources : Array[String]
  extends : String?
  /// Section name -> raw text, holding only the sections this document
  /// actually declares. Absence here is what an inherited section fills.
  sections : Map[String, String]
}

///|
/// Splits a KGF document into header fields and raw section texts.
pub fn parse_kgf_source(text : String) -> KGFSpecSource {
  let sections : Map[String, String] = Map([])
  for name in section_names() {
    match section_opt(text, name) {
      Some(body) => sections.set(name, body)
      None => ()
    }
  }
  {
    language: extract_language(text),
    sources: extract_sources(text),
    extends: extract_extends(text),
    sections,
  }
}

///|
pub fn KGFSpecSource::get_language(self : KGFSpecSource) -> String {
  self.language
}

///|
pub fn KGFSpecSource::get_sources(self : KGFSpecSource) -> Array[String] {
  self.sources
}

///|
/// Returns the `extends:` base spec name declared by this document.
pub fn KGFSpecSource::get_extends(self : KGFSpecSource) -> String? {
  self.extends
}

///|
/// Returns the raw text of one section, or `None` when this document does not
/// declare it.
pub fn KGFSpecSource::get_section(
  self : KGFSpecSource,
  name : String,
) -> String? {
  self.sections.get(name)
}

///|
/// Returns a new source in which every section this document does not declare
/// is taken from `base`.
///
/// Section-level override: a section declared here — even as an empty body —
/// wins whole, and nothing is merged within a section. `language`, `sources`
/// and `extends` are this document's own and are never taken from `base`.
pub fn KGFSpecSource::merge_onto(
  self : KGFSpecSource,
  base : KGFSpecSource,
) -> KGFSpecSource {
  let merged : Map[String, String] = Map([])
  for name in section_names() {
    match self.sections.get(name) {
      Some(body) => merged.set(name, body)
      None =>
        match base.sections.get(name) {
          Some(body) => merged.set(name, body)
          None => ()
        }
    }
  }
  {
    language: self.language,
    sources: self.sources,
    extends: self.extends,
    sections: merged,
  }
}

///|
/// Builds a lazily-parsed `KGFSpec` from the (already inheritance-resolved)
/// section texts.
pub fn KGFSpecSource::to_spec(self : KGFSpecSource) -> @types.KGFSpec {
  let body = fn(name : String) -> String {
    self.sections.get(name).unwrap_or("")
  }
  // Phase 1 — eager: lightweight metadata needed for registry mapping
  let features = parse_features(body("features"))
  let resolver = parse_resolver_with_sources(body("resolver"), self.sources)
  let ignore = parse_ignore(body("ignore"))
  // Phase 2+ — deferred: raw section text stored for lazy parsing
  @types.KGFSpec::new_lazy(
    self.language,
    resolver,
    features,
    ignore,
    body("lex"),
    body("grammar"),
    body("attrs"),
    body("semantics"),
    body("preprocess"),
    body("preprocess_fst"),
    body("classify"),
    extends=self.extends,
  )
}

///|
/// Parses a full KGF document text into a structured spec.
///
/// Only header, features, resolver, and ignore are parsed eagerly.
/// Heavy sections (lex, grammar, attrs, semantics, preprocess) are
/// stored as raw text and parsed lazily on first access.
///
/// The returned spec is the document on its own: an `extends:` header is
/// recorded but *not* resolved here, because the base spec may live in a
/// different file that this function never sees. Callers that need a fully
/// resolved spec go through `@registry.KGFRegistry`, which resolves
/// inheritance once the whole spec directory is loaded.
pub fn parse_kgf(text : String) -> @types.KGFSpec? {
  Some(parse_kgf_source(text).to_spec())
}

///|
/// Register lazy parsing callbacks so KGFSpec can defer heavy work.
/// Called at module init time.
fn init {
  @types.parse_lex_lazy.val = fn(source) {
    let result = parse_lex(source)
    (result.get_tokens(), result.get_keyword_kinds(), result.get_layout())
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
  let result : Map[String, Array[String]] = Map([])
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() == 0 || trimmed.has_prefix("#") {
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
/// Returns the non-blank, non-comment lines of `text` (one-entry-per-line
/// section format with `#` comments). Shared body for `parse_ignore` and
/// `parse_preprocess`, which have identical line-stripping semantics.
fn parse_line_list(text : String) -> Array[String]? {
  let lines = split_lines(text)
  let result : Array[String] = []
  for line in lines {
    let trimmed = trim_str(line)
    if trimmed.length() > 0 && !trimmed.has_prefix("#") {
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
/// Each line is a pattern (like .gitignore syntax).
/// Lines starting with # are comments.
fn parse_ignore(text : String) -> Array[String]? {
  parse_line_list(text)
}

///|
/// Parses preprocess section into list of transducer names.
fn parse_preprocess(text : String) -> Array[String]? {
  parse_line_list(text)
}
