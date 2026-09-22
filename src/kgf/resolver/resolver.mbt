///|
/// FileResolver trait for checking file existence and reading files.
/// Implementations should provide the actual file system access.
pub trait FileResolver {
  fn file_exists(Self, String) -> Bool
  /// Read a file's content. Returns None if the file doesn't exist or can't be read.
  fn read_file(Self, String) -> String?
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
  // Step 2: Determine base path for resolution
  let is_relative = has_relative_prefix(module0, spec.get_relative_prefixes())
  let (base_path, mod_clean) = if is_relative {
    let module0_chars = module0.to_array()
    if module0_chars.length() > 0 && module0_chars[0] == '/' {
      // Absolute relative (starts with /)
      (project_root, @config.substring_from(module0, 1))
    } else {
      // Relative to current file
      (dirname(from_file), module0)
    }
  } else {
    (project_root, module0)
  }
  // Step 3: Use resolve_chain if defined
  if spec.has_resolve_chain() {
    let result = resolve_with_chain(
      spec, base_path, mod_clean, from_file, project_root, file_resolver,
    )
    match result {
      Some(path) => return path
      None => ()
    }
    // Nothing on disk answered the module. Only now do the prefix fallbacks
    // apply: a namespaced id that no file backs is an EXTERNAL package, and
    // the vendor-style prefix names its distribution.
    match namespace_fallback(spec, module0) {
      Some(id) => return id
      None => ()
    }
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
    match namespace_fallback(spec, module0) {
      Some(id) => return id
      None => ()
    }
    return spec.get_bare_prefix() + module0
  }
  // Non-relative - attempt under project root
  let mod_path = module_to_path(
    module0,
    spec.get_module_path_style(),
    relative_prefixes=spec.get_relative_prefixes(),
  )
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
  // Nothing matched on disk — fall back to the prefixes, namespace first.
  match namespace_fallback(spec, module0) {
    Some(id) => return id
    None => ()
  }
  let head = get_module_head(module0)
  let bare_prefix = spec.get_bare_prefix()
  if bare_prefix.length() > 0 {
    return bare_prefix + head
  }
  module0
}

///|
/// The namespaced-package fallback: for a spec that declares an `ns_prefix`,
/// a backslash-namespaced identifier that no file backs names a package in the
/// ecosystem's vendor tree, identified by its first `ns_segments` segments
/// (`Vendor\Package\Thing` → `vendor/Vendor\Package`).
///
/// This runs only AFTER every file probe has missed. Deciding it up front —
/// as the resolver once did — meant that any identifier containing a
/// backslash was declared external before a single file was looked at, so a
/// project's own namespaced classes could never resolve to their files.
///
/// A relative specifier is exempt: it is navigation syntax, not a namespace.
fn namespace_fallback(
  spec : @types.ResolverSpec,
  module_str : String,
) -> String? {
  let prefix = match spec.get_ns_prefix() {
    Some(p) => p
    None => return None
  }
  if prefix.length() == 0 {
    return None
  }
  if !contains_char(module_str, '\\') {
    return None
  }
  if has_relative_prefix(module_str, spec.get_relative_prefixes()) {
    return None
  }
  let parts = split_by_backslash(module_str)
  let take = min_int(spec.get_ns_segments(), parts.length())
  Some(prefix + join_with_backslash(parts, take))
}

///|
/// Resolves a module using the resolve chain.
fn resolve_with_chain(
  spec : @types.ResolverSpec,
  base_path : String,
  module_str : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  let mod_path = module_to_path(
    module_str,
    spec.get_module_path_style(),
    relative_prefixes=spec.get_relative_prefixes(),
  )
  let base_abs = if is_absolute(base_path) {
    base_path
  } else {
    join_path([project_root, base_path])
  }
  let target_path = normalize_path(join_path([base_abs, mod_path]))
  let steps = spec.get_resolve_chain()
  // Collect the file-probe steps that precede the first Progressive step, if
  // any. Progressive replays those specific steps against progressively
  // shorter paths *in place* during the chain traversal, so the standard
  // iteration order continues to Fallback only after Progressive gives up.
  let prefix_steps = collect_leading_non_progressive(steps)
  for step in steps {
    let t = step.get_step_type()
    if t == @types.ResolveStepType::Progressive {
      // Replay prefix_steps on successively shorter targets.
      if prefix_steps.length() == 0 {
        continue
      }
      let mut shorter = strip_last_segment(target_path)
      while shorter.length() >= base_abs.length() {
        for pstep in prefix_steps {
          let result = execute_resolve_step(
            pstep, shorter, module_str, project_root, file_resolver,
          )
          match result {
            Some(path) => return Some(path)
            None => ()
          }
        }
        if shorter == base_abs || !contains_char(shorter, '/') {
          break
        }
        let next = strip_last_segment(shorter)
        if next == shorter {
          break
        }
        shorter = next
      }
      continue
    }
    if t == @types.ResolveStepType::Ancestors {
      let from_dir = dirname(
        if is_absolute(from_file) {
          from_file
        } else {
          join_path([project_root, from_file])
        },
      )
      let result = resolve_ancestors(
        spec, step, mod_path, from_dir, project_root, file_resolver,
      )
      match result {
        Some(path) => return Some(path)
        None => continue
      }
    }
    if t == @types.ResolveStepType::Fallback {
      // Every file probe has now missed, so the module is external and only
      // its NAME is left to report. A spec that declares an `ns_prefix` has
      // said how a namespaced id names its package in that ecosystem's vendor
      // tree, and that is more specific than the generic prefix — so it is
      // consulted first. Both are prefix fallbacks; neither may run before
      // the probes, which is why this sits at the Fallback step rather than
      // at the top of resolve_module.
      match namespace_fallback(spec, module_str) {
        Some(id) => return Some(id)
        None => ()
      }
    }
    if t == @types.ResolveStepType::NamespaceMap ||
      t == @types.ResolveStepType::SourceRoots {
      let result = resolve_mapped_bases(
        spec, step, module_str, from_file, project_root, file_resolver,
      )
      match result {
        Some(path) => return Some(path)
        // No mapping matched (or the mapped file is absent): fall through to
        // the chain's remaining steps, which resolve the module the ordinary
        // way. A declared mapping narrows resolution; it never blocks it.
        None => continue
      }
    }
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
/// Collect the in-file resolution steps (exact/index/ext/sibling) that can be
/// replayed against progressively shorter paths. Manifest/Ancestors/Fallback
/// are skipped because replaying them at a shorter path has no consistent
/// meaning.
fn collect_leading_non_progressive(
  steps : Array[@types.ResolveStep],
) -> Array[@types.ResolveStep] {
  let result : Array[@types.ResolveStep] = []
  for step in steps {
    match step.get_step_type() {
      @types.ResolveStepType::Exact
      | @types.ResolveStepType::Index
      | @types.ResolveStepType::Ext
      | @types.ResolveStepType::Sibling => result.push(step)
      _ => ()
    }
  }
  result
}

///|
fn strip_last_segment(path : String) -> String {
  let last = @config.find_last_char(path, '/')
  if last < 0 {
    return path
  }
  @config.substring(path, 0, last)
}

///|
/// Resolve by walking ancestor directories from base up to project root.
/// For each ancestor, joins ancestor/<dir>/<module> and runs the remaining
/// chain steps (exact, manifest, index, ext) against it.
fn resolve_ancestors(
  spec : @types.ResolverSpec,
  step : @types.ResolveStep,
  mod_path : String,
  base_abs : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  let dirs = step.get_files() // e.g. ["node_modules/"] or ["vendor/"]
  let remaining_steps = collect_non_ancestors_non_fallback(spec)
  let mut dir = base_abs
  while true {
    for pkg_dir in dirs {
      let candidate = normalize_path(join_path([dir, pkg_dir, mod_path]))
      for s in remaining_steps {
        let result = execute_resolve_step(
          s, candidate, mod_path, project_root, file_resolver,
        )
        match result {
          Some(path) => return Some(path)
          None => continue
        }
      }
    }
    if dir == project_root || dir == "." || dir == "/" || dir == "" {
      break
    }
    let parent = dirname(dir)
    if parent == dir {
      break
    }
    dir = parent
  }
  None
}

///|
/// Collect resolve chain steps that apply as single-step file probes
/// (exact/manifest/marker/index/ext/sibling). Ancestors, Progressive, and
/// Fallback are chain-level directives and are excluded.
fn collect_non_ancestors_non_fallback(
  spec : @types.ResolverSpec,
) -> Array[@types.ResolveStep] {
  let result : Array[@types.ResolveStep] = []
  for step in spec.get_resolve_chain() {
    let t = step.get_step_type()
    if t != @types.ResolveStepType::Ancestors &&
      t != @types.ResolveStepType::Progressive &&
      t != @types.ResolveStepType::Fallback {
      result.push(step)
    }
  }
  result
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
    @types.ResolveStepType::Exact => {
      // Check if the target path exists as-is
      if file_resolver.file_exists(target_path) {
        return Some(normalize_relative_result(project_root, target_path))
      }
      None
    }
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
    @types.ResolveStepType::Ancestors =>
      // Handled at resolve_with_chain level, not here
      None
    @types.ResolveStepType::Progressive =>
      // Progressive is a chain-level directive handled by resolve_with_chain,
      // which replays the prefix steps with successively shorter targets. It
      // never fires as a standalone per-step operation.
      None
    @types.ResolveStepType::NamespaceMap
    | @types.ResolveStepType::SourceRoots =>
      // Both rewrite the base directory and then replay the chain's own file
      // probes, which resolve_with_chain drives; neither is a per-step probe.
      None
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
    return @config.substring_from(module_str, 2)
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
  // Simple top-level keys: "main", "module", "types"
  if !path.contains("[") && !path.contains(".") {
    return find_json_string_value(content, path)
  }
  // Nested paths like exports["."].types, exports["."].import, exports["."]
  // Parse using @json for correctness
  let json : Json = @json.parse(content) catch { _ => return None }
  resolve_json_path(json, path)
}

///|
/// Resolve a dot/bracket path against a parsed JSON value.
/// Supports: "main", "exports[\".\"].import", "exports[\".\"]"
fn resolve_json_path(json : Json, path : String) -> String? {
  match descend_json_path(json, path) {
    // Terminal value must be a string
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Walk a dot/bracket path into a parsed JSON value and return whatever node
/// sits at the end, without demanding a particular shape. The string-valued
/// and object-valued manifest queries are both built on this so a query like
/// `autoload.psr-4` is parsed exactly once, by the same path grammar.
fn descend_json_path(json : Json, path : String) -> Json? {
  let segments = split_json_path(path)
  let mut current = json
  for seg in segments {
    match current {
      Object(obj) =>
        match obj.get(seg) {
          Some(next) => current = next
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
/// Query a manifest for an OBJECT-valued field — a namespace/alias map such
/// as composer's `autoload.psr-4` (`{"App\\": "src/"}`) or tsconfig's
/// `compilerOptions.paths` (`{"@app/*": ["src/*"]}`).
///
/// Each entry is returned as a (key, directory) pair. A value may be either a
/// plain string or an array of strings; an array contributes one pair per
/// element, in declaration order, so a caller that probes the pairs in order
/// tries the manifest's own preference order. Entries whose value is neither
/// a string nor a list of strings are skipped rather than failing the query —
/// a manifest may legitimately carry shapes this step has no use for.
///
/// Alternatives (`a | b`, `a, b`) are supported exactly as in the
/// string-valued `query_manifest`: the first query that yields a non-empty
/// map wins.
fn query_manifest_map(
  content : String,
  query : String,
) -> Array[(String, String)]? {
  let json : Json = @json.parse(content) catch { _ => return None }
  for alt in split_by_char(query, ',') {
    for part in split_by_char(trim_string(alt), '|') {
      let part_trimmed = trim_string(part)
      if part_trimmed.length() == 0 {
        continue
      }
      match descend_json_path(json, part_trimmed) {
        Some(Object(obj)) => {
          let pairs : Array[(String, String)] = []
          for entry in obj {
            let key = entry.0
            match entry.1 {
              String(v) => pairs.push((key, v))
              Array(items) =>
                for item in items {
                  match item {
                    String(v) => pairs.push((key, v))
                    _ => ()
                  }
                }
              _ => ()
            }
          }
          if pairs.length() > 0 {
            return Some(pairs)
          }
        }
        _ => ()
      }
    }
  }
  None
}

///|
/// Split a JSON path like `exports["."].import` into segments ["exports", ".", "import"].
fn split_json_path(path : String) -> Array[String] {
  let segments : Array[String] = []
  let buf = StringBuilder()
  let mut in_bracket = false
  for c in path {
    if c == '[' {
      let s = buf.to_string()
      if s.length() > 0 {
        segments.push(s)
      }
      buf.reset()
      in_bracket = true
    } else if c == ']' {
      let s = buf.to_string()
      // Strip quotes: "." → .
      if s.length() >= 2 && s[0] == '"' {
        let inner = s[1:s.length() - 1].to_owned()
        segments.push(inner)
      } else {
        segments.push(s)
      }
      buf.reset()
      in_bracket = false
    } else if c == '.' && !in_bracket {
      let s = buf.to_string()
      if s.length() > 0 {
        segments.push(s)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let s = buf.to_string()
  if s.length() > 0 {
    segments.push(s)
  }
  segments
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
  let value = StringBuilder()
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
  let current = StringBuilder()
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
  let result = StringBuilder()
  for i = start; i < end_idx; i = i + 1 {
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
  let mod_path = module_to_path(
    module_str,
    spec.get_module_path_style(),
    relative_prefixes=spec.get_relative_prefixes(),
  )
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
///
/// Relativising is only meaningful when the two paths are anchored the same
/// way: `relative_path` compares them segment by segment, so it silently
/// treats a relative root as if it were the absolute one. With the root the
/// docgen pipeline passes (`""`), an absolute hit like `/abs/proj/src/x.ts`
/// came back as `abs/proj/src/x.ts` — an id no file on disk carries, so the
/// module was registered with `file: null` and its edge counted as
/// unresolved. An analysis rooted outside the current directory (an absolute
/// path on the command line) has no relative form to report, so the absolute
/// path IS the identity and is kept verbatim.
fn normalize_relative_result(project_root : String, path : String) -> String {
  let rel = if is_absolute(path) && !is_absolute(project_root) {
    normalize_path(path)
  } else {
    relative_path(project_root, path)
  }
  // Replace backslashes with forward slashes (for Windows compatibility)
  replace_backslashes(rel)
}

///|
/// Replaces backslashes with forward slashes.
fn replace_backslashes(s : String) -> String {
  let result = StringBuilder()
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
/// Gets the head part of a module (before the first `.`, `::`, `/` or `\`).
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
  let backslash_pos = find_char_pos(module_str, '\\')
  if backslash_pos >= 0 && backslash_pos < end {
    end = backslash_pos
  }
  // Handle :: by checking for first :
  let colon_pos = find_char_pos(module_str, ':')
  if colon_pos >= 0 && colon_pos < end {
    end = colon_pos
  }
  @config.substring(module_str, 0, end)
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
  let current = StringBuilder()
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
  let result = StringBuilder()
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
impl FileResolver for FnFileResolver with fn file_exists(self, path : String) -> Bool {
  (self.check)(path)
}

///|
impl FileResolver for FnFileResolver with fn read_file(self, path : String) -> String? {
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
  let resolver = FnFileResolver::{ check: file_exists_fn, read: read_file_fn, }
  resolve_module(spec, language, from_file, module_path, project_root, resolver)
}

///|
/// Resolution result indicating success or circular dependency.
pub enum ResolutionResult {
  /// Successfully resolved to a path
  Resolved(String)
  /// Circular dependency detected
  Circular(String, String) // (from_file, module_path)
}

///|
/// Resolves a module specifier with caching and circular dependency detection.
/// Returns a ResolutionResult indicating success or circular detection.
pub fn resolve_module_cached(
  cache : @types.ResolutionCache,
  spec : @types.ResolverSpec,
  language : String,
  from_file : String,
  module_path : String,
  project_root : String,
  file_exists_fn : (String) -> Bool,
  read_file_fn : (String) -> String?,
) -> ResolutionResult {
  let key = @types.ResolutionCache::make_key(from_file, module_path)
  // Check cache first
  match cache.get(key) {
    Some(resolved) => {
      cache.record_hit()
      return Resolved(resolved)
    }
    None => ()
  }
  // Check for circular dependency
  if cache.is_resolving(key) {
    cache.record_circular(from_file, module_path)
    return Circular(from_file, module_path)
  }
  cache.record_miss()
  // Push onto resolution stack
  cache.push_resolving(key)
  // Create a cached file_exists function
  let cached_file_exists = fn(path : String) -> Bool {
    cache.check_file_exists(path, file_exists_fn)
  }
  // Perform resolution (with read_file for manifest/ancestors support)
  let resolved = resolve_module_with_fns(
    spec, language, from_file, module_path, project_root, cached_file_exists, read_file_fn,
  )
  // Pop from resolution stack
  cache.pop_resolving()
  // Cache the result
  cache.set(key, resolved)
  Resolved(resolved)
}

///|
/// Converts a ResolutionResult to a string for JSON serialization.
/// Returns the resolved path, or a sentinel value for circular dependencies.
pub fn ResolutionResult::to_string(self : ResolutionResult) -> String {
  match self {
    Resolved(path) => path
    Circular(from_file, module_path) =>
      @types.circular_sentinel_prefix + from_file + "::" + module_path
  }
}

///|
/// Checks if a resolved path is a circular dependency sentinel.
pub fn is_circular_sentinel(path : String) -> Bool {
  path.has_prefix(@types.circular_sentinel_prefix)
}

///|
/// Parses a circular sentinel to extract (from_file, module_path).
/// Returns None if not a valid sentinel.
pub fn parse_circular_sentinel(path : String) -> (String, String)? {
  if !is_circular_sentinel(path) {
    return None
  }
  let rest = @config.substring_from(
    path,
    @types.circular_sentinel_prefix.length(),
  )
  let sep_idx = find_substring(rest, "::")
  if sep_idx < 0 {
    return None
  }
  let from_file = @config.substring(rest, 0, sep_idx)
  let module_path = @config.substring_from(rest, sep_idx + 2)
  Some((from_file, module_path))
}
