///|
/// Open Knowledge Format (OKF) bundle model.
///
/// OKF v0.1 (GoogleCloudPlatform/knowledge-catalog) represents knowledge as a
/// directory tree of markdown concept documents with YAML frontmatter. The
/// only required frontmatter field is `type`; `title`, `description`, `tags`
/// and `timestamp` are recommended. Concepts reference each other through
/// ordinary markdown links (bundle-root absolute paths are recommended), and
/// every directory may carry a reserved `index.md` listing for progressive
/// disclosure plus an optional `log.md` change history.

///|
/// Reserved OKF filename for per-directory listings (progressive disclosure).
pub const OKF_INDEX_FILE : String = "index.md"

///|
/// Reserved OKF filename for the bundle change log.
pub const OKF_LOG_FILE : String = "log.md"

///|
/// Bundle subdirectory holding concepts for analyzed internal packages.
pub const OKF_PACKAGES_DIR : String = "packages"

///|
/// Bundle subdirectory holding concepts for external dependencies.
pub const OKF_DEPENDENCIES_DIR : String = "dependencies"

///|
/// Concept `type` value for analyzed internal packages.
pub const OKF_TYPE_PACKAGE : String = "Package"

///|
/// Concept `type` value for external dependencies.
pub const OKF_TYPE_EXTERNAL : String = "External Package"

///|
/// Concept path segment used when a package path normalizes to nothing
/// (e.g. the analysis root itself is a package).
pub const OKF_ROOT_CONCEPT : String = "root"

///|
/// A public declaration surfaced in a package concept's Schema section.
pub(all) struct OkfDeclaration {
  name : String
  kind : String
  doc : String
} derive(Eq)

///|
/// A dependency reference from a package.
/// For internal references `target` is the package path of another analyzed
/// package; for external references it is the dependency's import path with
/// any resolver prefix already stripped.
pub(all) struct OkfDepRef {
  target : String
  internal : Bool
  via : String?
} derive(Eq)

///|
/// One analyzed package, mapped to a single OKF concept document.
pub(all) struct OkfPackageConcept {
  path : String
  name : String
  overview : String
  description : String
  languages : Array[String]
  files : Array[String]
  declarations : Array[OkfDeclaration]
  depends_on : Array[OkfDepRef]
}

///|
/// Bundle-level generation options.
/// `timestamp` is an ISO 8601 instant; when absent, concept frontmatter
/// omits `timestamp` and no `log.md` is produced (both are optional in OKF).
pub(all) struct OkfBundleOptions {
  title : String
  timestamp : String?
}
