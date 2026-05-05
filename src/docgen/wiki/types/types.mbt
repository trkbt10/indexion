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
  /// Navigation index content (index.md), if present.
  /// Used by export to populate the Home page equivalent.
  index_content : String?
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
  index_content? : String? = None,
) -> WikiData {
  { nav, pages, index_content }
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
/// Wiki navigation index file name (SoT).
pub const WIKI_INDEX_FILE : String = "index.md"

///|
/// Construct the full path to the wiki log file in a given directory.
pub fn wiki_log_path(dir : String) -> String {
  dir + "/" + WIKI_LOG_FILE
}

///|
/// Construct the full path to the wiki navigation index in a given directory.
pub fn wiki_index_path(dir : String) -> String {
  dir + "/" + WIKI_INDEX_FILE
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
} derive(Eq, Debug, ToJson)

///|
pub impl Show for ManifestPage with output(self, logger) {
  to_repr(self).output(logger)
}

///|
pub impl @json.FromJson for ManifestPage with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "ManifestPage::from_json: expected object"),
    )
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "ManifestPage: missing 'id'"))
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "ManifestPage: missing 'title'"))
  }
  let file = match obj.get("file") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "ManifestPage: missing 'file'"))
  }
  let sources : Array[String] = match obj.get("sources") {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        if item is String(s) {
          result.push(s)
        }
      }
      result
    }
    Some(Null) | None => []
    _ => raise @json.JsonDecodeError((path, "ManifestPage: invalid 'sources'"))
  }
  let children : Array[String] = match obj.get("children") {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        if item is String(s) {
          result.push(s)
        }
      }
      result
    }
    Some(Null) | None => []
    _ => raise @json.JsonDecodeError((path, "ManifestPage: invalid 'children'"))
  }
  let provenance : String? = match obj.get("provenance") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    _ =>
      raise @json.JsonDecodeError((path, "ManifestPage: invalid 'provenance'"))
  }
  let last_actor : String? = match obj.get("last_actor") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    _ =>
      raise @json.JsonDecodeError((path, "ManifestPage: invalid 'last_actor'"))
  }
  { id, title, file, sources, children, provenance, last_actor }
}

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
} derive(Eq, Debug, ToJson)

///|
pub impl Show for WikiManifest with output(self, logger) {
  to_repr(self).output(logger)
}

///|
pub impl @json.FromJson for WikiManifest with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError(
      (path, "WikiManifest::from_json: expected object"),
    )
  }
  let title = match obj.get("title") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "WikiManifest: missing 'title'"))
  }
  let pages : Array[ManifestPage] = match obj.get("pages") {
    Some(Array(arr)) => {
      let result : Array[ManifestPage] = []
      for i, item in arr {
        result.push(
          @json.from_json(item) catch {
            e =>
              raise @json.JsonDecodeError(
                (
                  path.add_index(i),
                  "WikiManifest: invalid page: " + e.to_string(),
                ),
              )
          },
        )
      }
      result
    }
    Some(Null) | None => []
    _ => raise @json.JsonDecodeError((path, "WikiManifest: invalid 'pages'"))
  }
  { title, pages }
}

///|
pub fn WikiManifest::new(
  title~ : String,
  pages~ : Array[ManifestPage],
) -> WikiManifest {
  { title, pages }
}
