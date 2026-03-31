///|
/// # Wiki Types
///
/// Data model for wiki pages read from .indexion/wiki/.

///|
/// A single wiki page with content and metadata.
pub struct WikiPage {
  id : String
  title : String
  content : String
  sources : Array[WikiSourceRef]
  headings : Array[WikiHeading]
  children : Array[String]
  parent : String?
} derive(ToJson)

///|
/// Source file reference (e.g., "src/kgf/lexer/lexer.mbt:45-120").
pub struct WikiSourceRef {
  file : String
  start_line : Int
  end_line : Int
}

///|
/// Custom ToJson: { file, lines: [start, end] } for frontend.
pub impl ToJson for WikiSourceRef with to_json(self) {
  let m : Map[String, Json] = {}
  m["file"] = self.file.to_json()
  m["lines"] = [self.start_line.to_json(), self.end_line.to_json()]
  Json::object(m)
}

///|
/// A heading extracted from markdown content for ToC.
pub struct WikiHeading {
  level : Int
  text : String
  anchor : String
} derive(ToJson)

///|
/// Navigation tree item.
pub struct WikiNavItem {
  id : String
  title : String
  children : Array[WikiNavItem]
} derive(ToJson)

///|
/// Navigation tree wrapper.
pub struct WikiNav {
  pages : Array[WikiNavItem]
} derive(ToJson)

///|
/// Wiki data ready for serving.
pub struct WikiData {
  nav : WikiNav
  pages : Map[String, WikiPage]
}

///|
pub fn WikiHeading::new(
  level~ : Int,
  text~ : String,
  anchor~ : String,
) -> WikiHeading {
  { level, text, anchor }
}

///|
pub fn WikiSourceRef::new(
  file~ : String,
  start_line? : Int = 0,
  end_line? : Int = 0,
) -> WikiSourceRef {
  { file, start_line, end_line }
}

// --- Constructors for external use ---

///|
pub fn WikiPage::new(
  id~ : String,
  title~ : String,
  content~ : String,
  sources? : Array[WikiSourceRef] = [],
  headings? : Array[WikiHeading] = [],
  children? : Array[String] = [],
  parent? : String? = None,
) -> WikiPage {
  { id, title, content, sources, headings, children, parent }
}

///|
pub fn WikiNavItem::new(
  id~ : String,
  title~ : String,
  children? : Array[WikiNavItem] = [],
) -> WikiNavItem {
  { id, title, children }
}

///|
pub fn WikiNav::new(pages? : Array[WikiNavItem] = []) -> WikiNav {
  { pages, }
}

///|
pub fn WikiData::new(
  nav~ : WikiNav,
  pages~ : Map[String, WikiPage],
) -> WikiData {
  { nav, pages }
}

///|
/// A page entry in wiki.json manifest.
pub struct ManifestPage {
  id : String
  title : String
  file : String
  sources : Array[String]
  children : Array[String]
} derive(Eq, Show, @json.FromJson)

///|
/// wiki.json manifest.
pub struct WikiManifest {
  title : String
  pages : Array[ManifestPage]
} derive(Eq, Show, @json.FromJson)
