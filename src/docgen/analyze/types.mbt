// Types for KGF-based document analysis pipeline.

///|
/// Detected language/format of a file.
pub(all) enum DetectedLang {
  TypeScript
  JavaScript
  Python
  MoonBit
  Go
  Rust
  Markdown
  Html
  Css
  Sql
  Json
  Yaml
  Unknown
} derive(Eq, Show)

///|
pub fn DetectedLang::to_string(self : DetectedLang) -> String {
  match self {
    TypeScript => "typescript"
    JavaScript => "javascript"
    Python => "python"
    MoonBit => "moonbit"
    Go => "go"
    Rust => "rust"
    Markdown => "markdown"
    Html => "html"
    Css => "css"
    Sql => "sql"
    Json => "json"
    Yaml => "yaml"
    Unknown => "unknown"
  }
}

///|
/// Get the appropriate KGF spec name for documentation extraction.
pub fn DetectedLang::doc_spec_name(self : DetectedLang) -> String {
  match self {
    TypeScript => "typescript"
    JavaScript => "javascript"
    Python => "python"
    MoonBit => "moonbit"
    Go => "go"
    Rust => "rust"
    Markdown => "markdown"
    Html => "html"
    Css => "css"
    Sql => "sql"
    _ => "unknown"
  }
}

///|
/// Information about an analyzed file.
pub(all) struct FileInfo {
  /// File path.
  path : String
  /// Detected language.
  lang : DetectedLang
  /// File extension (without dot).
  ext : String
  /// KGF spec name to use.
  spec_name : String
} derive(Eq, Show)

///|
pub fn FileInfo::new(
  path : String,
  lang : DetectedLang,
  ext : String,
  spec_name : String,
) -> FileInfo {
  { path, lang, ext, spec_name }
}

///|
pub fn FileInfo::get_path(self : FileInfo) -> String {
  self.path
}

///|
pub fn FileInfo::get_lang(self : FileInfo) -> DetectedLang {
  self.lang
}

///|
pub fn FileInfo::get_ext(self : FileInfo) -> String {
  self.ext
}

///|
pub fn FileInfo::get_spec_name(self : FileInfo) -> String {
  self.spec_name
}

///|
/// A documented symbol extracted from KGF analysis.
pub(all) struct DocSymbol {
  /// Symbol ID (file::name format).
  id : String
  /// Symbol name.
  name : String
  /// Symbol kind (Function, Class, etc.).
  kind : String
  /// Documentation comment (raw).
  doc : String?
  /// Parent symbol ID (for methods, properties, etc.).
  mut parent : String?
  /// File where declared.
  file : String
  /// Child symbols.
  children : Array[DocSymbol]
} derive(Eq, Show)

///|
pub fn DocSymbol::new(
  id : String,
  name : String,
  kind : String,
  file : String,
) -> DocSymbol {
  { id, name, kind, doc: None, parent: None, file, children: [] }
}

///|
pub fn DocSymbol::with_doc(
  id : String,
  name : String,
  kind : String,
  file : String,
  doc : String,
) -> DocSymbol {
  { id, name, kind, doc: Some(doc), parent: None, file, children: [] }
}

///|
pub fn DocSymbol::get_id(self : DocSymbol) -> String {
  self.id
}

///|
pub fn DocSymbol::get_name(self : DocSymbol) -> String {
  self.name
}

///|
pub fn DocSymbol::get_kind(self : DocSymbol) -> String {
  self.kind
}

///|
pub fn DocSymbol::get_doc(self : DocSymbol) -> String? {
  self.doc
}

///|
pub fn DocSymbol::get_parent(self : DocSymbol) -> String? {
  self.parent
}

///|
pub fn DocSymbol::get_file(self : DocSymbol) -> String {
  self.file
}

///|
pub fn DocSymbol::get_children(self : DocSymbol) -> Array[DocSymbol] {
  self.children
}

///|
pub fn DocSymbol::set_parent(self : DocSymbol, parent : String) -> Unit {
  self.parent = Some(parent)
}

///|
pub fn DocSymbol::add_child(self : DocSymbol, child : DocSymbol) -> Unit {
  self.children.push(child)
}

///|
/// Result of the complete analysis pipeline.
pub struct AnalysisResult {
  /// All files analyzed.
  files : Array[FileInfo]
  /// Merged code graph from all files.
  mut graph : @graph.CodeGraph
  /// Extracted documentation symbols.
  symbols : Array[DocSymbol]
  /// Module-level documentation.
  module_docs : Map[String, String]
} derive(Eq, Show)

///|
pub fn AnalysisResult::new() -> AnalysisResult {
  { files: [], graph: @graph.CodeGraph::new(), symbols: [], module_docs: {} }
}

///|
pub fn AnalysisResult::add_file(self : AnalysisResult, file : FileInfo) -> Unit {
  self.files.push(file)
}

///|
pub fn AnalysisResult::add_symbol(
  self : AnalysisResult,
  symbol : DocSymbol,
) -> Unit {
  self.symbols.push(symbol)
}

///|
pub fn AnalysisResult::set_module_doc(
  self : AnalysisResult,
  mod_path : String,
  doc : String,
) -> Unit {
  self.module_docs.set(mod_path, doc)
}

///|
pub fn AnalysisResult::get_files(self : AnalysisResult) -> Array[FileInfo] {
  self.files
}

///|
pub fn AnalysisResult::get_graph(self : AnalysisResult) -> @graph.CodeGraph {
  self.graph
}

///|
pub fn AnalysisResult::set_graph(
  self : AnalysisResult,
  g : @graph.CodeGraph,
) -> Unit {
  self.graph = g
}

///|
pub fn AnalysisResult::get_symbols(self : AnalysisResult) -> Array[DocSymbol] {
  self.symbols
}

///|
pub fn AnalysisResult::get_module_docs(
  self : AnalysisResult,
) -> Map[String, String] {
  self.module_docs
}
