// Types for documentation rendering.

///|
/// Output format selection.
pub enum OutputFormat {
  Markdown
  Json
}

// Factory functions for cross-package enum construction

///|
/// Create Markdown output format.
pub fn OutputFormat::markdown() -> OutputFormat {
  Markdown
}

///|
/// Create JSON output format.
pub fn OutputFormat::json() -> OutputFormat {
  Json
}

///|
/// Render options for documentation generation.
pub struct RenderOptions {
  format : OutputFormat
  include_diagrams : Bool
  include_deps : Bool
  include_calls : Bool
  include_hierarchy : Bool
  include_refs : Bool
  max_diagram_nodes : Int
}

///|
/// Create default render options.
pub fn RenderOptions::default() -> RenderOptions {
  {
    format: Markdown,
    include_diagrams: true,
    include_deps: true,
    include_calls: true,
    include_hierarchy: true,
    include_refs: true,
    max_diagram_nodes: 50,
  }
}

///|
/// Create render options with format.
pub fn RenderOptions::with_format(format : OutputFormat) -> RenderOptions {
  { ..RenderOptions::default(), format, }
}

///|
/// Create render options with custom settings.
pub fn RenderOptions::new(
  format? : OutputFormat = Markdown,
  include_diagrams? : Bool = true,
  include_deps? : Bool = true,
  include_calls? : Bool = true,
  include_hierarchy? : Bool = true,
  include_refs? : Bool = true,
  max_diagram_nodes? : Int = 50,
) -> RenderOptions {
  {
    format,
    include_diagrams,
    include_deps,
    include_calls,
    include_hierarchy,
    include_refs,
    max_diagram_nodes,
  }
}

///|
/// Complete documentation output.
pub struct DocOutput {
  api_reference : String
  dependency_diagram : String?
  call_graph : String?
  type_hierarchy : String?
  cross_references : String?
  json_data : String?
}

///|
/// Create a new DocOutput.
pub fn DocOutput::new(
  api_reference : String,
  dependency_diagram? : String? = None,
  call_graph? : String? = None,
  type_hierarchy? : String? = None,
  cross_references? : String? = None,
  json_data? : String? = None,
) -> DocOutput {
  {
    api_reference,
    dependency_diagram,
    call_graph,
    type_hierarchy,
    cross_references,
    json_data,
  }
}

///|
/// Create DocOutput with JSON data only.
pub fn DocOutput::with_json(json_data : String) -> DocOutput {
  {
    api_reference: "",
    dependency_diagram: None,
    call_graph: None,
    type_hierarchy: None,
    cross_references: None,
    json_data: Some(json_data),
  }
}

// Getters

///|
pub fn RenderOptions::get_format(self : RenderOptions) -> OutputFormat {
  self.format
}

///|
pub fn RenderOptions::get_include_diagrams(self : RenderOptions) -> Bool {
  self.include_diagrams
}

///|
pub fn RenderOptions::get_include_deps(self : RenderOptions) -> Bool {
  self.include_deps
}

///|
pub fn RenderOptions::get_include_calls(self : RenderOptions) -> Bool {
  self.include_calls
}

///|
pub fn RenderOptions::get_include_hierarchy(self : RenderOptions) -> Bool {
  self.include_hierarchy
}

///|
pub fn RenderOptions::get_include_refs(self : RenderOptions) -> Bool {
  self.include_refs
}

///|
pub fn RenderOptions::get_max_diagram_nodes(self : RenderOptions) -> Int {
  self.max_diagram_nodes
}

///|
pub fn DocOutput::get_api_reference(self : DocOutput) -> String {
  self.api_reference
}

///|
pub fn DocOutput::get_dependency_diagram(self : DocOutput) -> String? {
  self.dependency_diagram
}

///|
pub fn DocOutput::get_call_graph(self : DocOutput) -> String? {
  self.call_graph
}

///|
pub fn DocOutput::get_type_hierarchy(self : DocOutput) -> String? {
  self.type_hierarchy
}

///|
pub fn DocOutput::get_cross_references(self : DocOutput) -> String? {
  self.cross_references
}

///|
pub fn DocOutput::get_json_data(self : DocOutput) -> String? {
  self.json_data
}

///|
/// Convert DocOutput to complete markdown string.
pub fn DocOutput::to_markdown(self : DocOutput) -> String {
  let sections : Array[String] = []
  if self.api_reference.length() > 0 {
    sections.push(self.api_reference)
  }
  match self.dependency_diagram {
    Some(d) =>
      if d.length() > 0 {
        sections.push("## Module Dependencies\n\n" + d)
      }
    None => ()
  }
  match self.call_graph {
    Some(c) => if c.length() > 0 { sections.push("## Call Graph\n\n" + c) }
    None => ()
  }
  match self.type_hierarchy {
    Some(h) => if h.length() > 0 { sections.push("## Type Hierarchy\n\n" + h) }
    None => ()
  }
  match self.cross_references {
    Some(r) =>
      if r.length() > 0 {
        sections.push("## Cross References\n\n" + r)
      }
    None => ()
  }
  join_sections(sections)
}

///|
/// Join sections with double newline.
fn join_sections(sections : Array[String]) -> String {
  if sections.length() == 0 {
    return ""
  }
  let result : Array[Char] = []
  for i, section in sections {
    if i > 0 {
      result.push('\n')
      result.push('\n')
    }
    for c in section.to_array() {
      result.push(c)
    }
  }
  String::from_array(result)
}
