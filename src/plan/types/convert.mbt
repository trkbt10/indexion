///|
/// Converters from domain-specific analysis results to PlanDocument.

///|
/// Conversion context for building PlanDocument.
pub struct ConvertContext {
  project_name : String
  project_version : String
}

///|
pub fn ConvertContext::new() -> ConvertContext {
  { project_name: "", project_version: "" }
}

///|
pub fn ConvertContext::with_project(name : String, version : String) -> ConvertContext {
  { project_name: name, project_version: version }
}
