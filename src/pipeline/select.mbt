///|
/// KGF spec selection utilities for pipeline.
/// Consolidates spec selection logic from graph and readme CLIs.

///|
/// Index mapping source patterns to KGF file paths.
/// Built once from headers, then used to select which KGFs to fully parse.
pub struct KGFIndex {
  /// Maps source pattern (e.g. ".mbt") to KGF file paths
  source_to_files : Map[String, Array[String]]
  /// All KGF file paths in the index
  all_files : Array[String]
}

///|
/// Build KGF index by reading only headers from all KGF files.
/// This is fast because it only parses the header section.
pub fn build_kgf_index(specs_dir : String) -> KGFIndex {
  let source_to_files : Map[String, Array[String]] = Map([])
  let all_files : Array[String] = []
  try {
    if !@fs.is_dir(specs_dir) {
      return { source_to_files, all_files, }
    }
    let entries = @fs.read_dir(specs_dir)
    for entry in entries {
      if entry.has_suffix(".kgf") {
        let spec_path = specs_dir + "/" + entry
        all_files.push(spec_path)
        let content = @fs.read_file_to_string(spec_path)
        let header = @kgf_parser.parse_kgf_header(content)
        for source in header.get_sources() {
          match source_to_files.get(source) {
            Some(arr) => arr.push(spec_path)
            None => source_to_files.set(source, [spec_path])
          }
        }
      }
    }
  } catch {
    _ => ()
  }
  { source_to_files, all_files, }
}

///|
/// Build matching signals from file paths (extensions and basenames).
/// These signals are used to select only relevant KGF specs.
pub fn build_path_signals(file_paths : Array[String]) -> Map[String, Bool] {
  let signals : Map[String, Bool] = Map([])
  for path in file_paths {
    let basename = extract_basename(path)
    signals.set(basename, true)
    let ext = extract_extension(path)
    if ext.length() > 0 {
      signals.set(ext, true)
    }
  }
  signals
}

///|
/// Get KGF file paths that match the given signals using the index.
fn get_matching_kgf_paths(
  index : KGFIndex,
  signals : Map[String, Bool],
) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let result : Array[String] = []
  for entry in index.source_to_files {
    let source = entry.0
    let paths = entry.1
    if signals.contains(source) {
      for path in paths {
        if !seen.contains(path) {
          seen.set(path, true)
          result.push(path)
        }
      }
    }
  }
  result
}

///|
/// Load registry from index, only parsing KGF files that match signals.
pub fn load_registry_from_index(
  index : KGFIndex,
  signals : Map[String, Bool],
) -> @registry.KGFRegistry {
  let registry = @registry.KGFRegistry::new()
  let sources = read_spec_sources(get_matching_kgf_paths(index, signals))
  add_extends_bases(sources, index.all_files)
  registry.register_spec_sources(sources)
  registry
}

///|
/// Split each `.kgf` file at `paths` into its raw sections, skipping files
/// that cannot be read.
fn read_spec_sources(paths : Array[String]) -> Array[@kgf_parser.KGFSpecSource] {
  let sources : Array[@kgf_parser.KGFSpecSource] = []
  for path in paths {
    try {
      let content = @fs.read_file_to_string(path)
      sources.push(@kgf_parser.parse_kgf_source(content))
    } catch {
      _ => ()
    }
  }
  sources
}

///|
/// Extend a selected subset of specs with the bases their `extends:` chains
/// name, reading them from `candidate_paths`.
///
/// Spec selection filters by `sources:`, but a base spec exists to be
/// inherited from and need not claim any extension of its own, so it can be
/// filtered out while a spec that needs it is kept. Without this step a
/// derived spec would silently load with its own sections only — the very
/// N-times-fixed-bug situation `extends:` is meant to end. Resolution itself
/// stays in the registry; this only makes sure the base is in the set.
fn add_extends_bases(
  sources : Array[@kgf_parser.KGFSpecSource],
  candidate_paths : Array[String],
) -> Unit {
  let have : Map[String, Bool] = Map([])
  for source in sources {
    have.set(source.get_language(), true)
  }
  // Each pass can pull in a base that itself extends another, so repeat until
  // no source is missing its base. Every pass adds at least one spec, so the
  // number of candidates bounds the passes.
  for _ in 0..<(candidate_paths.length() + 1) {
    let wanted : Map[String, Bool] = Map([])
    for source in sources {
      match source.get_extends() {
        Some(base) =>
          if base.length() > 0 && !have.contains(base) {
            wanted.set(base, true)
          }
        None => ()
      }
    }
    if wanted.is_empty() {
      return
    }
    let mut added = false
    for path in candidate_paths {
      let content = @fs.read_file_to_string(path) catch { _ => continue }
      let header = @kgf_parser.parse_kgf_header(content)
      if wanted.contains(header.get_language()) {
        sources.push(@kgf_parser.parse_kgf_source(content))
        have.set(header.get_language(), true)
        added = true
      }
    }
    if !added {
      return
    }
  }
}

///|
/// Check if any source pattern matches the signals.
fn sources_match_signals(
  sources : Array[String],
  signals : Map[String, Bool],
) -> Bool {
  for source in sources {
    if signals.contains(source) {
      return true
    }
  }
  false
}

///|
/// Check if a KGF spec is relevant to any discovered file paths.
pub fn spec_matches_signals(
  spec : @kgf_types.KGFSpec,
  signals : Map[String, Bool],
) -> Bool {
  let sources = spec.get_resolver().get_sources()
  sources_match_signals(sources, signals)
}

///|
/// Load only relevant KGF specs from a directory based on discovered file paths.
/// Optimized single-pass: reads each KGF file once, parses header, and if matched, full parses.
pub fn load_registry_for_paths(
  specs_dir : String,
  file_paths : Array[String],
) -> @registry.KGFRegistry {
  let registry = @registry.KGFRegistry::new()
  let signals = build_path_signals(file_paths)
  let selected : Array[@kgf_parser.KGFSpecSource] = []
  let all_paths : Array[String] = []
  try {
    if !@fs.is_dir(specs_dir) {
      return registry
    }
    let entries = @fs.read_dir(specs_dir)
    for entry in entries {
      if entry.has_suffix(".kgf") {
        let spec_path = specs_dir + "/" + entry
        all_paths.push(spec_path)
        let content = @fs.read_file_to_string(spec_path)
        // Fast header-only parse to check sources
        let header = @kgf_parser.parse_kgf_header(content)
        if sources_match_signals(header.get_sources(), signals) {
          // Full split using same content (no re-read)
          selected.push(@kgf_parser.parse_kgf_source(content))
        }
      }
    }
  } catch {
    _ => ()
  }
  add_extends_bases(selected, all_paths)
  registry.register_spec_sources(selected)
  registry
}

///|
/// Filter supported files and read their contents.
pub fn collect_supported_files(
  file_paths : Array[String],
  registry : @registry.KGFRegistry,
) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  for file in load_supported_file_info(file_paths, registry) {
    files.push((file.path, file.content))
  }
  files
}
