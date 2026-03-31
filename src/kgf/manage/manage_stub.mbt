///|
/// Stub for non-native targets.
pub async fn install_kgfs_from_dir(
  _src_kgfs : String,
) -> Unit raise KgfManageError {
  raise KgfManageError::InstallError(
    "kgf install is only supported on native target",
  )
}

///|
/// Stub for non-native targets.
pub async fn install_single_kgf(
  _relative_path : String,
  _content : Bytes,
) -> Unit raise KgfManageError {
  raise KgfManageError::InstallError(
    "kgf install is only supported on native target",
  )
}

///|
/// Stub for non-native targets.
pub async fn update_kgfs() -> Unit raise KgfManageError {
  raise KgfManageError::InstallError(
    "kgf update is only supported on native target",
  )
}

///|
/// Stub for non-native targets.
pub async fn add_kgf(_spec_name : String) -> Unit raise KgfManageError {
  raise KgfManageError::InstallError(
    "kgf add is only supported on native target",
  )
}
