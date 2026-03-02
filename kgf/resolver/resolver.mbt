///|
/// FileResolver trait for checking file existence.
/// Implementations should provide the actual file system access.
pub trait FileResolver {
  file_exists(Self, String) -> Bool
}

///|
/// Resolves a module specifier to a project-relative path or a logical id.
/// - Applies resolver aliases.
/// - Handles language-specific namespace prefixes.
/// - Resolves relative prefixes against the importing file or project root.
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
  // Step 3: Handle relative paths
  let is_relative = has_relative_prefix(module0, spec.get_relative_prefixes())
  if is_relative {
    let module0_chars = module0.to_array()
    if module0_chars.length() > 0 && module0_chars[0] == '/' {
      // Absolute relative (starts with /)
      let mod_clean = substr_from_resolver(module0, 1)
      let hit = try_local(
        spec, project_root, mod_clean, project_root, file_resolver,
      )
      match hit {
        Some(path) => return path
        None => ()
      }
    } else {
      // Relative to current file
      let base = dirname(from_file)
      let hit = try_local(spec, base, module0, project_root, file_resolver)
      match hit {
        Some(path) => return path
        None => ()
      }
    }
    return spec.get_bare_prefix() + module0
  }
  // Step 4: Non-relative - attempt under project root
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
  // Step 5: Fallback with bare_prefix
  let head = get_module_head(module0)
  let bare_prefix = spec.get_bare_prefix()
  if bare_prefix.length() > 0 {
    return bare_prefix + head
  }
  module0
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
/// FnFileResolver wraps a function as a FileResolver.
priv struct FnFileResolver {
  check : (String) -> Bool
}

///|
impl FileResolver for FnFileResolver with file_exists(self, path : String) -> Bool {
  (self.check)(path)
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
  let resolver = FnFileResolver::{ check: file_exists_fn }
  resolve_module(spec, language, from_file, module_path, project_root, resolver)
}
