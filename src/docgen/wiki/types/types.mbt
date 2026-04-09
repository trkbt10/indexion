///|
/// # Wiki Types
///
/// Backend-agnostic data model for wiki pages.
/// Used by reader, interop, search, and all CLI consumers.

///|
/// A single wiki page with content and metadata.
pub struct WikiPage {
  id : String
  title : String
  content : String
  /// Source file name from manifest (e.g. "overview.md")
  file : String
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

///|
pub fn WikiPage::new(
  id~ : String,
  title~ : String,
  content~ : String,
  file? : String = "",
  sources? : Array[WikiSourceRef] = [],
  headings? : Array[WikiHeading] = [],
  children? : Array[String] = [],
  parent? : String? = None,
) -> WikiPage {
  { id, title, content, file, sources, headings, children, parent }
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
/// Wiki manifest file name (SoT).
/// All consumers must use this constant instead of hardcoding "wiki.json".
pub const WIKI_MANIFEST_FILE : String = "wiki.json"

///|
/// Wiki log file name (SoT).
/// All consumers must use this constant instead of hardcoding "log.json".
pub const WIKI_LOG_FILE : String = "log.json"

///|
/// Construct the full path to the wiki log file in a given directory.
pub fn wiki_log_path(dir : String) -> String {
  dir + "/" + WIKI_LOG_FILE
}

///|
/// Construct the full path to the wiki manifest in a given directory.
pub fn wiki_manifest_path(dir : String) -> String {
  dir + "/" + WIKI_MANIFEST_FILE
}

///|
/// A page entry in wiki.json manifest.
pub struct ManifestPage {
  id : String
  title : String
  file : String
  sources : Array[String]
  children : Array[String]
  /// Content provenance: "extracted" | "synthesized" | "manual".
  /// None if not yet classified.
  provenance : String?
  /// Who last modified: "indexion" | "agent:<name>" | "user".
  /// None if not yet tracked.
  last_actor : String?
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub fn ManifestPage::new(
  id~ : String,
  title~ : String,
  file~ : String,
  sources? : Array[String] = [],
  children? : Array[String] = [],
  provenance? : String? = None,
  last_actor? : String? = None,
) -> ManifestPage {
  { id, title, file, sources, children, provenance, last_actor }
}

///|
/// Create an updated copy of a ManifestPage with selected fields replaced.
pub fn ManifestPage::with_updates(
  self : ManifestPage,
  sources? : Array[String],
  children? : Array[String],
  provenance? : String?,
  last_actor? : String?,
) -> ManifestPage {
  {
    id: self.id,
    title: self.title,
    file: self.file,
    sources: match sources {
      Some(s) => s
      None => self.sources
    },
    children: match children {
      Some(c) => c
      None => self.children
    },
    provenance: match provenance {
      Some(p) => p
      None => self.provenance
    },
    last_actor: match last_actor {
      Some(a) => a
      None => self.last_actor
    },
  }
}

///|
/// wiki.json manifest.
pub struct WikiManifest {
  title : String
  pages : Array[ManifestPage]
} derive(Eq, Show, ToJson, @json.FromJson)

///|
pub fn WikiManifest::new(
  title~ : String,
  pages~ : Array[ManifestPage],
) -> WikiManifest {
  { title, pages }
}
