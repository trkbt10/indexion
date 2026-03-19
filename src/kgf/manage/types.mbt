///|
/// Error type for kgf management operations.
pub suberror KgfManageError {
  NetworkError(String)
  ApiError(String)
  InstallError(String)
  NotFoundError(String)
}

///|
pub fn KgfManageError::to_string(self : KgfManageError) -> String {
  match self {
    NetworkError(msg) => "network error: " + msg
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
