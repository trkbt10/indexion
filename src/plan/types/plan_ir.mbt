///|
/// Plan IR - Common intermediate representation for plan outputs.
/// Enables conversion to multiple output formats (Markdown, GitHub Issue, YAML).

///|
/// A complete plan document.
pub struct PlanDocument {
  title : String
  mut description : String
  sections : Array[PlanSection]
  metadata : Map[String, String]
}

///|
/// Create a new empty plan document.
pub fn PlanDocument::new(title : String) -> PlanDocument {
  { title, description: "", sections: [], metadata: Map::new() }
}

///|
/// Add a section to the document.
pub fn PlanDocument::add_section(
  self : PlanDocument,
  section : PlanSection,
) -> Unit {
  self.sections.push(section)
}

///|
/// Set metadata value.
pub fn PlanDocument::set_meta(
  self : PlanDocument,
  key : String,
  value : String,
) -> Unit {
  self.metadata.set(key, value)
}

///|
/// Set description.
pub fn PlanDocument::set_description(
  self : PlanDocument,
  desc : String,
) -> Unit {
  self.description = desc
}

///|
/// A section within a plan document.
pub struct PlanSection {
  id : String
  heading : String
  content : SectionContent
}

///|
/// Create a new section.
pub fn PlanSection::new(
  id : String,
  heading : String,
  content : SectionContent,
) -> PlanSection {
  { id, heading, content }
}

///|
/// Content types that can appear in a section.
pub enum SectionContent {
  Text(String)
  List(Array[ListItem])
  Table(TableData)
  Checklist(Array[ChecklistItem])
  Code(String, String) // (language, code)
  Nested(Array[PlanSection])
  KeyValue(Array[(String, String)])
}

///|
/// Create text content.
pub fn SectionContent::text(s : String) -> SectionContent {
  Text(s)
}

///|
/// Create list content.
pub fn SectionContent::list(items : Array[ListItem]) -> SectionContent {
  List(items)
}

///|
/// Create table content.
pub fn SectionContent::table(data : TableData) -> SectionContent {
  Table(data)
}

///|
/// Create checklist content.
pub fn SectionContent::checklist(
  items : Array[ChecklistItem],
) -> SectionContent {
  Checklist(items)
}

///|
/// Create code content.
pub fn SectionContent::code(lang : String, code : String) -> SectionContent {
  Code(lang, code)
}

///|
/// Create nested sections content.
pub fn SectionContent::nested(sections : Array[PlanSection]) -> SectionContent {
  Nested(sections)
}

///|
/// Create key-value content.
pub fn SectionContent::keyvalue(
  pairs : Array[(String, String)],
) -> SectionContent {
  KeyValue(pairs)
}

///|
/// A list item with optional description.
pub struct ListItem {
  text : String
  description : String
}

///|
pub fn ListItem::simple(text : String) -> ListItem {
  { text, description: "" }
}

///|
pub fn ListItem::with_desc(text : String, description : String) -> ListItem {
  { text, description }
}

///|
/// Table data with headers and rows.
pub struct TableData {
  headers : Array[String]
  rows : Array[Array[String]]
  alignments : Array[TableAlign]
}

///|
pub fn TableData::new(headers : Array[String]) -> TableData {
  let alignments : Array[TableAlign] = []
  for _ in headers {
    alignments.push(TableAlign::Left)
  }
  { headers, rows: [], alignments }
}

///|
pub fn TableData::add_row(self : TableData, row : Array[String]) -> Unit {
  self.rows.push(row)
}

///|
/// Table column alignment.
pub enum TableAlign {
  Left
  Center
  Right
}

///|
/// Get default alignment (Left).
pub fn TableAlign::default_left() -> TableAlign {
  Left
}

///|
/// A checklist item with priority and status.
pub struct ChecklistItem {
  label : String
  description : String
  checked : Bool
  priority : Int // 0 = no priority, 1 = highest
}

///|
pub fn ChecklistItem::new(label : String) -> ChecklistItem {
  { label, description: "", checked: false, priority: 0 }
}

///|
pub fn ChecklistItem::with_priority(
  label : String,
  priority : Int,
) -> ChecklistItem {
  { label, description: "", checked: false, priority }
}

///|
pub fn ChecklistItem::with_desc(
  label : String,
  description : String,
) -> ChecklistItem {
  { label, description, checked: false, priority: 0 }
}

// =============================================================================
// JSON Serialization
// =============================================================================

///|
/// Convert PlanDocument to JSON.
pub fn PlanDocument::to_json(self : PlanDocument) -> Json {
  let obj : Map[String, Json] = Map::new()
  obj.set("title", self.title.to_json())
  obj.set("description", self.description.to_json())
  // Sections
  let sections_arr : Array[Json] = []
  for section in self.sections {
    sections_arr.push(section.to_json())
  }
  obj.set("sections", Json::array(sections_arr))
  // Metadata
  let meta_obj : Map[String, Json] = Map::new()
  self.metadata.each(fn(k, v) { meta_obj.set(k, v.to_json()) })
  obj.set("metadata", Json::object(meta_obj))
  Json::object(obj)
}

///|
/// Convert PlanSection to JSON.
pub fn PlanSection::to_json(self : PlanSection) -> Json {
  let obj : Map[String, Json] = Map::new()
  obj.set("id", self.id.to_json())
  obj.set("heading", self.heading.to_json())
  obj.set("content", self.content.to_json())
  Json::object(obj)
}

///|
/// Convert SectionContent to JSON.
pub fn SectionContent::to_json(self : SectionContent) -> Json {
  let obj : Map[String, Json] = Map::new()
  match self {
    Text(s) => {
      obj.set("type", "text".to_json())
      obj.set("value", s.to_json())
    }
    List(items) => {
      obj.set("type", "list".to_json())
      let arr : Array[Json] = []
      for item in items {
        let item_obj : Map[String, Json] = Map::new()
        item_obj.set("text", item.text.to_json())
        if item.description.length() > 0 {
          item_obj.set("description", item.description.to_json())
        }
        arr.push(Json::object(item_obj))
      }
      obj.set("items", Json::array(arr))
    }
    Table(data) => {
      obj.set("type", "table".to_json())
      obj.set("headers", json_string_array(data.headers))
      let rows_arr : Array[Json] = []
      for row in data.rows {
        rows_arr.push(json_string_array(row))
      }
      obj.set("rows", Json::array(rows_arr))
    }
    Checklist(items) => {
      obj.set("type", "checklist".to_json())
      let arr : Array[Json] = []
      for item in items {
        let item_obj : Map[String, Json] = Map::new()
        item_obj.set("label", item.label.to_json())
        if item.description.length() > 0 {
          item_obj.set("description", item.description.to_json())
        }
        item_obj.set("checked", item.checked.to_json())
        if item.priority > 0 {
          item_obj.set("priority", item.priority.to_json())
        }
        arr.push(Json::object(item_obj))
      }
      obj.set("items", Json::array(arr))
    }
    Code(lang, code) => {
      obj.set("type", "code".to_json())
      obj.set("language", lang.to_json())
      obj.set("code", code.to_json())
    }
    Nested(sections) => {
      obj.set("type", "nested".to_json())
      let arr : Array[Json] = []
      for section in sections {
        arr.push(section.to_json())
      }
      obj.set("sections", Json::array(arr))
    }
    KeyValue(pairs) => {
      obj.set("type", "keyvalue".to_json())
      let arr : Array[Json] = []
      for pair in pairs {
        let (k, v) = pair
        let pair_obj : Map[String, Json] = Map::new()
        pair_obj.set("key", k.to_json())
        pair_obj.set("value", v.to_json())
        arr.push(Json::object(pair_obj))
      }
      obj.set("pairs", Json::array(arr))
    }
  }
  Json::object(obj)
}

///|
fn json_string_array(arr : Array[String]) -> Json {
  let result : Array[Json] = []
  for s in arr {
    result.push(s.to_json())
  }
  Json::array(result)
}
