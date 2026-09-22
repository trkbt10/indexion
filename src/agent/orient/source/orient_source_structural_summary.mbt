///|
pub fn structural_summary(
  file : @pipeline.SupportedFile,
  graph : @graph.CodeGraph,
  symbols_by_module : Map[String, Array[String]],
) -> String {
  let summary = StringBuilder()
  summary.write_string(file.path)
  summary.write_string("\n")
  match symbols_by_module.get(file.path) {
    Some(lines) =>
      for line in lines {
        summary.write_string(line)
        summary.write_string("\n")
      }
    None => ()
  }
  for note in graph.get_notes("module_doc", file.path) {
    summary.write_string(note.content)
    summary.write_string("\n")
  }
  summary.to_string()
}

///|
pub fn symbol_line(name : String, kind : String, doc : String?) -> String {
  match doc {
    Some(text) if text.length() > 0 => kind + " " + name + " " + text
    _ => kind + " " + name
  }
}
