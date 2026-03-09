///|
/// Types for GitHub Issue/PR templates.

///|
/// GitHub Issue Form template (YAML format).
pub struct IssueFormTemplate {
  mut name : String
  mut description : String
  mut title : String // May contain placeholders like [Bug]:
  mut labels : Array[String]
  mut assignees : Array[String]
  body : Array[FormField]
}

///|
pub fn IssueFormTemplate::new() -> IssueFormTemplate {
  {
    name: "",
    description: "",
    title: "",
    labels: [],
    assignees: [],
    body: [],
  }
}

///|
/// A field in the issue form.
pub enum FormField {
  Markdown(MarkdownField)
  Textarea(TextareaField)
  Input(InputField)
  Dropdown(DropdownField)
  Checkboxes(CheckboxesField)
}

///|
/// Markdown content (static, not user-editable).
pub struct MarkdownField {
  value : String
}

///|
/// Multi-line text input.
pub struct TextareaField {
  id : String
  label : String
  description : String
  placeholder : String
  value : String // default value
  render : String // "markdown" or empty
  required : Bool
}

///|
/// Single-line text input.
pub struct InputField {
  id : String
  label : String
  description : String
  placeholder : String
  value : String
  required : Bool
}

///|
/// Dropdown selection.
pub struct DropdownField {
  id : String
  label : String
  description : String
  options : Array[String]
  default_index : Int
  multiple : Bool
  required : Bool
}

///|
/// Checkboxes group.
pub struct CheckboxesField {
  id : String
  label : String
  description : String
  options : Array[CheckboxOption]
  required : Bool
}

///|
/// Single checkbox option.
pub struct CheckboxOption {
  label : String
  required : Bool
}

///|
/// Markdown template (legacy .md format).
pub struct MarkdownTemplate {
  content : String
  placeholders : Array[TemplatePlaceholder]
}

///|
/// A placeholder in a template.
pub struct TemplatePlaceholder {
  key : String
  start_pos : Int
  end_pos : Int
}
