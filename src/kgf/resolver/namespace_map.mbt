///|
/// # Manifest-driven namespace/path mapping
///
/// Real projects rarely lay their module namespace over the directory tree
/// one-to-one from a single base. They DECLARE the mapping in the project
/// manifest, and every toolchain in that ecosystem reads it from there:
///
///   * composer.json  `autoload.psr-4`  — `{"App\\": "src/"}`
///   * tsconfig.json  `compilerOptions.paths` + `baseUrl` — `{"@app/*": ["src/*"]}`
///   * Java/Kotlin    a conventional, fixed source root (`src/main/java`)
///
/// The first two are the same shape — a map from a namespace/alias PREFIX to
/// a directory — so they are one step (`namespace_map`) parameterised by the
/// manifest file and the field to read. The third has no map to read, only a
/// fixed list, so it is a second step (`source_roots`) that shares the same
/// anchoring and probing.
///
/// Both are anchored at the NEAREST ANCESTOR manifest of the importing file,
/// not at the project root: a monorepo has one manifest per package and an
/// import inside a package must follow that package's own mapping.

///|
/// One resolved mapping: a base directory (absolute) and the remainder of the
/// module identifier that should be appended to it. `prefix_len` is the
/// length of the matched key, kept so callers can prefer the longest match.
priv struct NamespaceBinding {
  base_dir : String
  rest : String
  prefix_len : Int
}

///|
/// Locate the nearest ancestor directory of `from_file` that contains
/// `manifest`, and return that directory together with the manifest's
/// contents. Walking up rather than using the project root is what makes the
/// step work in a monorepo, where each package declares its own mapping.
fn find_nearest_manifest(
  manifest : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> (String, String)? {
  if manifest.length() == 0 {
    return None
  }
  walk_up_from_file(from_file, project_root, fn(dir) {
    match file_resolver.read_file(join_path([dir, manifest])) {
      Some(content) => Some((dir, content))
      None => None
    }
  })
}

///|
/// Walk from the importing file's directory up to the project root, handing
/// each directory to `probe` and stopping at the first one that answers.
///
/// This is the traversal both mapping steps are anchored by; they differ only
/// in what they ask of each directory, so the walk itself — including where it
/// must stop — lives in one place. Resolution must not escape the analysed
/// tree, so the project root is the last directory examined, and the walk has
/// to terminate on a relative root ("." or "", which is what the docgen
/// pipeline passes) exactly as it does on an absolute one.
fn[T] walk_up_from_file(
  from_file : String,
  project_root : String,
  probe : (String) -> T?,
) -> T? {
  let from_abs = if is_absolute(from_file) {
    from_file
  } else {
    join_path([project_root, from_file])
  }
  let root_abs = project_root_abs(project_root)
  let mut dir = dirname(from_abs)
  while true {
    match probe(dir) {
      Some(found) => return Some(found)
      None => ()
    }
    if dir == root_abs || dir == "." || dir == "/" || dir == "" {
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
/// The project root in the form the walk compares against.
fn project_root_abs(project_root : String) -> String {
  if is_absolute(project_root) {
    normalize_path(project_root)
  } else {
    normalize_path(join_path([project_root]))
  }
}

///|
/// Match a module identifier against a manifest-declared namespace map and
/// return every applicable binding, LONGEST KEY FIRST.
///
/// Two key shapes are handled by one rule, because they are the same rule
/// written twice by two ecosystems:
///
///   * A key containing the wildcard `*` (`@app/*`) matches when the module
///     starts with the part before the wildcard; the text the wildcard stands
///     for becomes the remainder. The value's own `*` — `src/*` — is where
///     that remainder is substituted, so the directory is the value's text
///     before the wildcard.
///   * A key with no wildcard (`App\`) is a plain prefix: the module must
///     start with it and everything after it is the remainder. This is
///     psr-4, where the namespace prefix maps onto a directory wholesale.
///
/// In both cases the DIRECTORY is the value with its wildcard tail removed,
/// which is why the two collapse into a single implementation.
///
/// Longest-key-first ordering is the precedence rule both ecosystems specify:
/// with `{"App\\": "src/", "App\\Dto\\": "custom/dto/"}` an `App\Dto\UserDto`
/// must take the more specific second entry.
fn bindings_for_module(
  module_str : String,
  pairs : Array[(String, String)],
  manifest_dir : String,
  base_dir_rel : String,
) -> Array[NamespaceBinding] {
  let matches : Array[NamespaceBinding] = []
  for pair in pairs {
    let key = pair.0
    let value = pair.1
    let key_star = find_char_pos(key, '*')
    let key_prefix = if key_star >= 0 {
      @config.substring(key, 0, key_star)
    } else {
      key
    }
    // An empty key prefix (`"*"`, or `""`) maps everything; that is legal and
    // simply yields a zero-length match, which sorts last.
    if key_prefix.length() > 0 && !module_str.has_prefix(key_prefix) {
      continue
    }
    let rest = @config.substring_from(module_str, key_prefix.length())
    let value_star = find_char_pos(value, '*')
    let dir_part = if value_star >= 0 {
      @config.substring(value, 0, value_star)
    } else {
      value
    }
    let base_dir = normalize_path(
      join_path([manifest_dir, base_dir_rel, dir_part]),
    )
    matches.push({ base_dir, rest, prefix_len: key_prefix.length(), })
  }
  sort_bindings_longest_first(matches)
  matches
}

///|
/// Execute a NamespaceMap or SourceRoots step: work out the candidate base
/// directories this step declares, then probe each of them with the chain's
/// own file steps.
///
/// Returning `None` means "this step had nothing to say", and the caller
/// continues down the chain — a manifest that declares no map, a module that
/// matches no key, and a mapped path with no file behind it are all the same
/// kind of miss, and none of them may swallow the module.
fn resolve_mapped_bases(
  spec : @types.ResolverSpec,
  step : @types.ResolveStep,
  module_str : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String? {
  let bindings = match step.get_step_type() {
    @types.ResolveStepType::NamespaceMap =>
      namespace_map_bindings(
        step, module_str, from_file, project_root, file_resolver,
      )
    @types.ResolveStepType::SourceRoots =>
      source_root_bindings(
        step, module_str, from_file, project_root, file_resolver,
      )
    _ => return None
  }
  if bindings.length() == 0 {
    return None
  }
  // Only the in-file probes are replayed. Manifest/Ancestors/Fallback are
  // chain-level directives whose meaning does not transfer to a rewritten
  // base, and Fallback in particular would report success for every module.
  let probes = collect_leading_non_progressive(spec.get_resolve_chain())
  if probes.length() == 0 {
    return None
  }
  for binding in bindings {
    // The remainder is still a module identifier in the spec's own style, so
    // it goes through the same dot/backslash/:: conversion as any other path.
    let rest_path = module_to_path(
      binding.rest,
      spec.get_module_path_style(),
      relative_prefixes=spec.get_relative_prefixes(),
    )
    let target = normalize_path(join_path([binding.base_dir, rest_path]))
    for probe in probes {
      match
        execute_resolve_step(
          probe,
          target,
          binding.rest,
          project_root,
          file_resolver,
        ) {
        Some(path) => return Some(path)
        None => ()
      }
    }
  }
  None
}

///|
/// Bindings declared by a manifest's namespace map.
fn namespace_map_bindings(
  step : @types.ResolveStep,
  module_str : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> Array[NamespaceBinding] {
  let (manifest_dir, content) = match
    find_nearest_manifest(
      step.get_file(),
      from_file,
      project_root,
      file_resolver,
    ) {
    Some(found) => found
    None => return []
  }
  let pairs = match query_manifest_map(content, step.get_query()) {
    Some(p) => p
    None => return []
  }
  // The map's values may themselves be relative to a directory named by a
  // second field — tsconfig states its `paths` relative to `baseUrl`. When no
  // such field is declared, or it is absent from this manifest, the values are
  // relative to the manifest's own directory.
  let base_dir_rel = if step.get_base_query().length() > 0 {
    match query_manifest(content, step.get_base_query()) {
      Some(v) => v
      None => ""
    }
  } else {
    ""
  }
  bindings_for_module(module_str, pairs, manifest_dir, base_dir_rel)
}

///|
/// Bindings declared inline by the spec as fixed source roots. The anchor is
/// the nearest ancestor directory holding one of the step's markers; when the
/// step declares no marker, or none is found, the project root is the anchor,
/// which is the single-module layout.
fn source_root_bindings(
  step : @types.ResolveStep,
  module_str : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> Array[NamespaceBinding] {
  let roots = step.get_files()
  if roots.length() == 0 {
    return []
  }
  let anchor = nearest_marker_dir(
    step.get_file(),
    from_file,
    project_root,
    file_resolver,
  )
  let bindings : Array[NamespaceBinding] = []
  for root in roots {
    bindings.push({
      base_dir: normalize_path(join_path([anchor, root])),
      rest: module_str,
      // Fixed roots match no key, so they carry no precedence of their own:
      // they are probed in the order the spec lists them.
      prefix_len: 0,
    })
  }
  bindings
}

///|
/// The nearest ancestor directory of `from_file` containing any of the
/// comma-separated `markers`, falling back to the project root.
fn nearest_marker_dir(
  markers : String,
  from_file : String,
  project_root : String,
  file_resolver : &FileResolver,
) -> String {
  let root_abs = project_root_abs(project_root)
  if markers.length() == 0 {
    return root_abs
  }
  let marker_list : Array[String] = []
  for m in split_by_char(markers, ',') {
    let t = trim_string(m)
    if t.length() > 0 {
      marker_list.push(t)
    }
  }
  let found = walk_up_from_file(from_file, project_root, fn(dir) {
    for marker in marker_list {
      if file_resolver.file_exists(join_path([dir, marker])) {
        return Some(dir)
      }
    }
    None
  })
  match found {
    Some(dir) => dir
    // No marker anywhere above the file: the project root IS the module root,
    // which is the single-module layout.
    None => root_abs
  }
}

///|
/// Order bindings by descending matched-prefix length. Insertion sort keeps
/// the relative order of equal-length keys, so a manifest that lists several
/// directories for one key is probed in its own declared order.
fn sort_bindings_longest_first(items : Array[NamespaceBinding]) -> Unit {
  for i = 1; i < items.length(); i = i + 1 {
    let current = items[i]
    let mut j = i - 1
    while j >= 0 && items[j].prefix_len < current.prefix_len {
      items[j + 1] = items[j]
      j = j - 1
    }
    items[j + 1] = current
  }
}
