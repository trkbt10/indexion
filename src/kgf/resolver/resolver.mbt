///|
/// FileResolver trait for checking file existence and reading files.
/// Implementations should provide the actual file system access.
pub trait FileResolver {
  file_exists(Self, String) -> Bool
  /// Read a file's content. Returns None if the file doesn't exist or can't be read.
  read_file(Self, String) -> String?
}

///|
/// Resolves a module specifier to a project-relative path or a logical id.
/// - Applies resolver aliases.
/// - Handles language-specific namespace prefixes.
/// - Resolves relative prefixes against the importing file or project root.
/// - Uses resolve_chain if defined, otherwise falls back to legacy resolution.
pub fn resolve_module(
  spec : @types.ResolverSpec,
  language : String,
  from_file : String,
  module_path : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String {
  let _ = language
  // Step 1: Apply aliases
  let module0 = apply_aliases(module_path, spec.get_aliases())
  // Step 2: Handle namespaced (composer-like) resolution
  let ns_prefix = spec.get_ns_prefix()
  let has_ns_prefix = match ns_prefix {
    Some(prefix) => prefix.length() > 0
    None => false
  }
  let is_namespaced = contains_char(module0, '\\')
  let is_relative_prefixed = has_relative_prefix(
    module0,
    spec.get_relative_prefixes(),
  )
  if has_ns_prefix && is_namespaced && not(is_relative_prefixed) {
    let parts = split_by_backslash(module0)
    let take = min_int(spec.get_ns_segments(), parts.length())
    let key = join_with_backslash(parts, take)
    match ns_prefix {
      Some(prefix) => return prefix + key
      None => ()
    }
  }
  // Step 3: Determine base path for resolution
  let is_relative = has_relative_prefix(module0, spec.get_relative_prefixes())
  let (base_path, mod_clean) = if is_relative {
    let module0_chars = module0.to_array()
    if module0_chars.length() > 0 && module0_chars[0] == '/' {
      // Absolute relative (starts with /)
      (project_root, substr_from_resolver(module0, 1))
    } else {
      // Relative to current file
      (dirname(from_file), module0)
    }
  } else {
    (project_root, module0)
  }
  // Step 4: Use resolve_chain if defined
  if spec.has_resolve_chain() {
    let result = resolve_with_chain(
      spec, base_path, mod_clean, project_root, file_resolver,
    )
    match result {
      Some(path) => return path
      None => ()
    }
    // Fallback to bare_prefix if chain didn't resolve
    let bare_prefix = spec.get_bare_prefix()
    if bare_prefix.length() > 0 {
      return bare_prefix + get_module_head(module0)
    }
    return module0
  }
  // Legacy resolution (when resolve_chain is not defined)
  if is_relative {
    let hit = try_local(spec, base_path, mod_clean, project_root, file_resolver)
    match hit {
      Some(path) => return path
      None => ()
    }
    return spec.get_bare_prefix() + module0
  }
  // Non-relative - attempt under project root
  let mod_path = module_to_path(module0, spec.get_module_path_style())
  let local_try = join_path([project_root, mod_path])
  // Try extensions
  for ext in spec.get_exts() {
    let p = local_try + ext
    if file_resolver.file_exists(p) {
      return normalize_relative_result(project_root, p)
    }
  }
  // Try index files
  for idx in spec.get_indexes() {
    let p = local_try + idx
    if file_resolver.file_exists(p) {
      return normalize_relative_result(project_root, p)
    }
  }
  // Fallback with bare_prefix
  let head = get_module_head(module0)
  let bare_prefix = spec.get_bare_prefix()
  if bare_prefix.length() > 0 {
    return bare_prefix + head
  }
  module0
}

///|
/// Resolves a module using the resolve chain.
fn resolve_with_chain(
  spec : @types.ResolverSpec,
  base_path : String,
  module_str : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  let mod_path = module_to_path(module_str, spec.get_module_path_style())
  let base_abs = if is_absolute(base_path) {
    base_path
  } else {
    join_path([project_root, base_path])
  }
  let target_path = normalize_path(join_path([base_abs, mod_path]))
  for step in spec.get_resolve_chain() {
    let result = execute_resolve_step(
      step, target_path, module_str, project_root, file_resolver,
    )
    match result {
      Some(path) => return Some(path)
      None => continue
    }
  }
  None
}

///|
/// Executes a single resolve step.
fn execute_resolve_step(
  step : @types.ResolveStep,
  target_path : String,
  module_str : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  match step.get_step_type() {
    @types.ResolveStepType::Manifest => {
      // Try to read manifest file and extract entry point
      let manifest_path = join_path([target_path, step.get_file()])
      match file_resolver.read_file(manifest_path) {
        Some(content) => {
          let entry = query_manifest(content, step.get_query())
          match entry {
            Some(entry_file) => {
              let full_path = normalize_path(
                join_path([target_path, entry_file]),
              )
              if file_resolver.file_exists(full_path) {
                return Some(normalize_relative_result(project_root, full_path))
              }
            }
            None => ()
          }
        }
        None => ()
      }
      None
    }
    @types.ResolveStepType::Marker => {
      // Check if any marker file exists
      for marker in step.get_files() {
        let marker_path = join_path([target_path, marker])
        if file_resolver.file_exists(marker_path) {
          return Some(normalize_relative_result(project_root, marker_path))
        }
      }
      None
    }
    @types.ResolveStepType::Index => {
      // Try index files
      for idx in step.get_files() {
        let p = target_path + idx
        if file_resolver.file_exists(p) {
          return Some(normalize_relative_result(project_root, p))
        }
      }
      None
    }
    @types.ResolveStepType::Ext => {
      // Try extensions
      for ext in step.get_files() {
        let p = target_path + ext
        if file_resolver.file_exists(p) {
          return Some(normalize_relative_result(project_root, p))
        }
      }
      None
    }
    @types.ResolveStepType::Sibling => {
      // Try sibling file (e.g., foo/ -> foo.rs)
      let dir_name = basename(target_path)
      let parent = dirname(target_path)
      for ext in step.get_files() {
        let p = join_path([parent, dir_name + ext])
        if file_resolver.file_exists(p) {
          return Some(normalize_relative_result(project_root, p))
        }
      }
      None
    }
    @types.ResolveStepType::Fallback => {
      // Fallback step returns the prefixed module path
      let prefix = step.get_prefix()
      // Strip relative prefix from module_str for cleaner fallback
      let clean_module = strip_relative_prefix(module_str)
      Some(prefix + clean_module)
    }
  }
}

///|
/// Strips relative prefixes (./, ../) from module string.
fn strip_relative_prefix(module_str : String) -> String {
  if module_str.has_prefix("./") {
    return substr_from_resolver(module_str, 2)
  }
  if module_str.has_prefix("../") {
    // For ../ we keep it as is since it's meaningful
    return module_str
  }
  module_str
}

///|
/// Query a manifest file (package.json, Cargo.toml) for an entry point.
/// Supports simple JSON path queries like "main", "exports['.'].import".
fn query_manifest(content : String, query : String) -> String? {
  // Split query by comma or pipe for alternatives
  let alternatives = split_by_char(query, ',')
  for alt in alternatives {
    let alt_trimmed = trim_string(alt)
    // Handle pipe alternatives within a single alternative
    let pipe_parts = split_by_char(alt_trimmed, '|')
    for part in pipe_parts {
      let part_trimmed = trim_string(part)
      let result = query_json_simple(content, part_trimmed)
      match result {
        Some(value) => return Some(value)
        None => continue
      }
    }
  }
  None
}

///|
/// Simple JSON query for common manifest fields.
/// Supports: "main", "module", "exports['.'].import", etc.
fn query_json_simple(content : String, path : String) -> String? {
  // Very simple JSON parsing for common cases
  // This is a simplified implementation - a full JSON parser would be better
  if path == "main" || path == "module" || path == "types" {
    return find_json_string_value(content, path)
  }
  // For more complex paths, we need proper JSON parsing
  // For now, just try the simple case
  None
}

///|
/// Find a simple string value in JSON content.
fn find_json_string_value(content : String, key : String) -> String? {
  // Look for "key": "value" or "key":"value"
  let pattern = "\"" + key + "\""
  let idx = find_substring(content, pattern)
  guard idx >= 0 else { return None }
  // Find the colon after the key
  let after_key = idx + pattern.length()
  let chars = content.to_array()
  let mut i = after_key
  // Skip whitespace
  while i < chars.length() && (chars[i] == ' ' || chars[i] == '\t') {
    i += 1
  }
  guard i < chars.length() && chars[i] == ':' else { return None }
  i += 1
  // Skip whitespace
  while i < chars.length() && (chars[i] == ' ' || chars[i] == '\t') {
    i += 1
  }
  guard i < chars.length() && chars[i] == '"' else { return None }
  i += 1
  // Read the string value
  let value = StringBuilder::new()
  while i < chars.length() && chars[i] != '"' {
    if chars[i] == '\\' && i + 1 < chars.length() {
      // Escape sequence
      i += 1
      value.write_char(chars[i])
    } else {
      value.write_char(chars[i])
    }
    i += 1
  }
  Some(value.to_string())
}

///|
/// Split a string by a character.
fn split_by_char(s : String, c : Char) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for ch in s {
    if ch == c {
      result.push(current.to_string())
      current.reset()
    } else {
      current.write_char(ch)
    }
  }
  result.push(current.to_string())
  result
}

///|
/// Trim whitespace from a string.
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start += 1
  }
  let mut end_idx = chars.length()
  while end_idx > start &&
        (chars[end_idx - 1] == ' ' || chars[end_idx - 1] == '\t') {
    end_idx -= 1
  }
  if start == 0 && end_idx == chars.length() {
    return s
  }
  let result = StringBuilder::new()
  for i = start; i < end_idx; i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Returns substring from start position to end of string.
fn substr_from_resolver(s : String, start : Int) -> String {
  if start >= s.length() {
    return ""
  }
  let chars = s.to_array()
  let result = StringBuilder::new()
  for i = start; i < chars.length(); i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Returns substring from start to end position (exclusive).
fn substr_resolver(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  let actual_start = if start < 0 { 0 } else { start }
  if actual_start >= actual_end {
    return ""
  }
  let result = StringBuilder::new()
  for i = actual_start; i < actual_end; i = i + 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
/// Tries to resolve a module path locally, checking extensions and index files.
fn try_local(
  spec : @types.ResolverSpec,
  base : String,
  module_str : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  let mod_path = module_to_path(module_str, spec.get_module_path_style())
  let base_abs = if is_absolute(base) {
    base
  } else {
    join_path([project_root, base])
  }
  let basepath = normalize_path(join_path([base_abs, mod_path]))
  // Try extensions
  for ext in spec.get_exts() {
    let p = basepath + ext
    if file_resolver.file_exists(p) {
      return Some(normalize_relative_result(project_root, p))
    }
  }
  // Try index files
  for idx in spec.get_indexes() {
    let p = basepath + idx
    if file_resolver.file_exists(p) {
      return Some(normalize_relative_result(project_root, p))
    }
  }
  None
}

///|
/// Normalizes a result path to be relative to project root.
fn normalize_relative_result(project_root : String, path : String) -> String {
  let rel = relative_path(project_root, path)
  // Replace backslashes with forward slashes (for Windows compatibility)
  replace_backslashes(rel)
}

///|
/// Replaces backslashes with forward slashes.
fn replace_backslashes(s : String) -> String {
  let result = StringBuilder::new()
  for c in s {
    if c == '\\' {
      result.write_char('/')
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}

///|
/// Checks if a module path has any of the relative prefixes.
fn has_relative_prefix(module_path : String, prefixes : Array[String]) -> Bool {
  for prefix in prefixes {
    if prefix.length() > 0 && module_path.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
/// Gets the head part of a module (before first . or :: or /).
fn get_module_head(module_str : String) -> String {
  let mut end = module_str.length()
  let dot_pos = find_char_pos(module_str, '.')
  if dot_pos >= 0 && dot_pos < end {
    end = dot_pos
  }
  let slash_pos = find_char_pos(module_str, '/')
  if slash_pos >= 0 && slash_pos < end {
    end = slash_pos
  }
  // Handle :: by checking for first :
  let colon_pos = find_char_pos(module_str, ':')
  if colon_pos >= 0 && colon_pos < end {
    end = colon_pos
  }
  substr_resolver(module_str, 0, end)
}

///|
/// Checks if a string contains a specific character.
fn contains_char(s : String, c : Char) -> Bool {
  for ch in s {
    if ch == c {
      return true
    }
  }
  false
}

///|
/// Splits a string by backslash.
fn split_by_backslash(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for c in s {
    if c == '\\' {
      result.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  result.push(current.to_string())
  result
}

///|
/// Joins array elements with backslash up to a count.
fn join_with_backslash(parts : Array[String], count : Int) -> String {
  if count <= 0 || parts.length() == 0 {
    return ""
  }
  let take_count = if count > parts.length() { parts.length() } else { count }
  let result = StringBuilder::new()
  result.write_string(parts[0])
  for i = 1; i < take_count; i = i + 1 {
    result.write_char('\\')
    result.write_string(parts[i])
  }
  result.to_string()
}

///|
/// Finds the position of a character in a string.
fn find_char_pos(s : String, c : Char) -> Int {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == c {
      return i
    }
  }
  -1
}

///|
/// Returns the minimum of two integers.
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// FnFileResolver wraps functions as a FileResolver.
priv struct FnFileResolver {
  check : (String) -> Bool
  read : (String) -> String?
}

///|
impl FileResolver for FnFileResolver with file_exists(self, path : String) -> Bool {
  (self.check)(path)
}

///|
impl FileResolver for FnFileResolver with read_file(self, path : String) -> String? {
  (self.read)(path)
}

///|
/// Resolves a module specifier using a function to check file existence.
/// This is a convenience wrapper around resolve_module that accepts a function
/// instead of a trait reference.
pub fn resolve_module_with_fn(
  spec : @types.ResolverSpec,
  language : String,
  from_file : String,
  module_path : String,
  project_root : String,
  file_exists_fn : (String) -> Bool,
) -> String {
  let resolver = FnFileResolver::{
    check: file_exists_fn,
    read: fn(_path) { None },
  }
  resolve_module(spec, language, from_file, module_path, project_root, resolver)
}

///|
/// Resolves a module specifier using functions for file existence and reading.
/// This is a convenience wrapper for resolve_chain support.
pub fn resolve_module_with_fns(
  spec : @types.ResolverSpec,
  language : String,
  from_file : String,
  module_path : String,
  project_root : String,
  file_exists_fn : (String) -> Bool,
  read_file_fn : (String) -> String?,
) -> String {
  let resolver = FnFileResolver::{ check: file_exists_fn, read: read_file_fn }
  resolve_module(spec, language, from_file, module_path, project_root, resolver)
}
