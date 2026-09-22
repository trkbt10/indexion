///|
/// Error type for kgf management operations.
pub suberror KgfManageError {
  ApiError(String)
  InstallError(String)
  NotFoundError(String)
}

///|
/// Format error as human-readable string.
pub fn KgfManageError::to_string(self : KgfManageError) -> String {
  match self {
    ApiError(msg) => "API error: " + msg
    InstallError(msg) => "install error: " + msg
    NotFoundError(msg) => "not found: " + msg
  }
}

///|
/// Metadata about an installed KGF spec.
pub struct KgfSpecInfo {
  name : String
  category : String
  sources : Array[String]
  path : String
  /// `language` of the base spec this one inherits sections from
  /// (`extends:` in the header), or `None` when the spec is standalone.
  extends : String?
}

///|
/// A spec in a resolved, layered spec set.
///
/// `layer` is the index of the directory the winning file came from in the
/// chain that was resolved: 0 is the base set and every higher index is an
/// overlay layered on top. `shadowed` lists the paths of same-named specs from
/// earlier layers that this one replaced, so `kgf list` can show which file won
/// and what it displaced.
pub struct KgfResolvedSpec {
  info : KgfSpecInfo
  layer : Int
  shadowed : Array[String]
}
