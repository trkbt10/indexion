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
}
