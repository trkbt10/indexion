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
} derive(Eq, Debug)

///|
/// Convert the detected language to its lowercase string identifier.
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
} derive(Eq, Debug)

///|
/// Create a new FileInfo with the given path, language, extension, and spec name.
pub fn FileInfo::new(
  path : String,
  lang : DetectedLang,
  ext : String,
  spec_name : String,
) -> FileInfo {
  { path, lang, ext, spec_name }
}

///|
/// Return the file path.
pub fn FileInfo::get_path(self : FileInfo) -> String {
  self.path
}

///|
/// Return the detected language.
pub fn FileInfo::get_lang(self : FileInfo) -> DetectedLang {
  self.lang
}

///|
/// Return the file extension without dot.
pub fn FileInfo::get_ext(self : FileInfo) -> String {
  self.ext
}

///|
/// Return the KGF spec name for this file.
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
} derive(Eq, Debug)

///|
/// Create a new DocSymbol without documentation.
pub fn DocSymbol::new(
  id : String,
  name : String,
  kind : String,
  file : String,
) -> DocSymbol {
  { id, name, kind, doc: None, parent: None, file, children: [] }
}

///|
/// Create a new DocSymbol with an attached documentation string.
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
/// Return the symbol ID.
pub fn DocSymbol::get_id(self : DocSymbol) -> String {
  self.id
}

///|
/// Return the symbol name.
pub fn DocSymbol::get_name(self : DocSymbol) -> String {
  self.name
}

///|
/// Return the symbol kind (e.g. Function, Class).
pub fn DocSymbol::get_kind(self : DocSymbol) -> String {
  self.kind
}

///|
/// Return the documentation comment, if any.
pub fn DocSymbol::get_doc(self : DocSymbol) -> String? {
  self.doc
}

///|
/// Return the parent symbol ID, if any.
pub fn DocSymbol::get_parent(self : DocSymbol) -> String? {
  self.parent
}

///|
/// Return the file where this symbol is declared.
pub fn DocSymbol::get_file(self : DocSymbol) -> String {
  self.file
}

///|
/// Return the child symbols.
pub fn DocSymbol::get_children(self : DocSymbol) -> Array[DocSymbol] {
  self.children
}

///|
/// Set the parent symbol ID.
pub fn DocSymbol::set_parent(self : DocSymbol, parent : String) -> Unit {
  self.parent = Some(parent)
}

///|
/// Append a child symbol.
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
} derive(Eq, Debug)

///|
/// Create an empty analysis result.
pub fn AnalysisResult::new() -> AnalysisResult {
  { files: [], graph: @graph.CodeGraph::new(), symbols: [], module_docs: {} }
}

///|
/// Add an analyzed file to the result.
pub fn AnalysisResult::add_file(self : AnalysisResult, file : FileInfo) -> Unit {
  self.files.push(file)
}

///|
/// Add an extracted documentation symbol to the result.
pub fn AnalysisResult::add_symbol(
  self : AnalysisResult,
  symbol : DocSymbol,
) -> Unit {
  self.symbols.push(symbol)
}

///|
/// Set module-level documentation for a given module path.
pub fn AnalysisResult::set_module_doc(
  self : AnalysisResult,
  mod_path : String,
  doc : String,
) -> Unit {
  self.module_docs.set(mod_path, doc)
}

///|
/// Return all analyzed files.
pub fn AnalysisResult::get_files(self : AnalysisResult) -> Array[FileInfo] {
  self.files
}

///|
/// Return the merged code graph.
pub fn AnalysisResult::get_graph(self : AnalysisResult) -> @graph.CodeGraph {
  self.graph
}

///|
/// Replace the code graph.
pub fn AnalysisResult::set_graph(
  self : AnalysisResult,
  g : @graph.CodeGraph,
) -> Unit {
  self.graph = g
}

///|
/// Return all extracted documentation symbols.
pub fn AnalysisResult::get_symbols(self : AnalysisResult) -> Array[DocSymbol] {
  self.symbols
}

///|
/// Return all module-level documentation entries.
pub fn AnalysisResult::get_module_docs(
  self : AnalysisResult,
) -> Map[String, String] {
  self.module_docs
}
