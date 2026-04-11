///|
pub fn cache_path(dir : String, file_name : String) -> String {
  dir + "/" + file_name
}

///|
/// Ensures that `cache_dir` exists and is a directory.
/// Returns `Ok(())` on success, or `Err(message)` describing the failure.
pub fn ensure_cache_dir(
  cache_dir : String,
  label : String,
) -> Result[Unit, String] {
  if @fs.path_exists(cache_dir) {
    let is_dir = @fs.is_dir(cache_dir) catch {
      err => {
        return Err(
          "Error: failed to inspect " +
          label +
          " `" +
          cache_dir +
          "`: " +
          err.to_string(),
        )
      }
    }
    if !is_dir {
      return Err(
        "Error: " +
        label +
        " `" +
        cache_dir +
        "` exists and is not a directory.",
      )
    }
  }
  @config.ensure_dir_recursive(cache_dir)
  Ok(())
}

///|
/// Writes JSON to `path`. Returns `Ok(())` on success,
/// or `Err(message)` describing the failure.
pub fn write_json_file(
  path : String,
  json : Json,
  label : String,
) -> Result[Unit, String] {
  @fs.write_string_to_file(path, json.stringify(indent=2)) catch {
    err => {
      return Err(
        "Error: failed to write " +
        label +
        " `" +
        path +
        "`: " +
        err.to_string(),
      )
    }
  }
  Ok(())
}

///|
/// Reads and parses a JSON file at `path`. Returns `Ok(json)` on success,
/// or `Err(message)` describing the failure.
pub fn read_json_file(
  path : String,
  label : String,
) -> Result[Json, String] {
  let text = @fs.read_file_to_string(path) catch {
    err => {
      return Err(
        "Error: failed to read " +
        label +
        " `" +
        path +
        "`: " +
        err.to_string(),
      )
    }
  }
  let json : Json = @json.parse(text) catch {
    err => {
      return Err(
        "Error: failed to parse " +
        label +
        " `" +
        path +
        "`: " +
        err.to_string(),
      )
    }
  }
  Ok(json)
}
