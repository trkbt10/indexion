// Post-merge enrichment passes that add cross-package edges and canonicalize
// identifiers.
//
// Every rule here is driven by data declared in KGF specs rather than by
// per-language constants hardcoded in this file. The contract between the
// enrichment pass and KGF specs:
//
// * Manifest specs declare their role via a `=== features` entry:
//     manifest_role:  "package" or "project"
//     identity_edge:  edge kind whose `to` is the cluster's public name
//     entry_edges:    edge kinds whose `to` is a path to a cluster entry file
//
// * Source-language specs advertise their package-reference token convention
//   by defining a token whose pattern begins with a sigil character (`@` for
//   MoonBit's `PackageRef`). The enrichment pass scans for these tokens and
//   resolves them against manifest-emitted alias edges.
//
// * External-reference prefixes and external-lookup markers (like `pkg:`,
//   `npm:`, `node_modules/`) come from each spec's resolver section —
//   `bare_prefix` and `resolve_chain[ancestors].files`. No such string ever
//   appears as a literal in this file.

///|
pub fn enrich_graph(
  graph : @graph.CodeGraph,
  file_tokens : Array[FileTokens],
  specs : Map[String, @kgf_types.KGFSpec],
) -> Unit {
  let alias_index = build_alias_index(graph)
  emit_source_alias_edges(graph, file_tokens, specs, alias_index)
  canonicalize_external_refs(graph, specs)
}

// ── Alias index ───────────────────────────────────────────────────────────
//
// Built from every `moduleDependsOn` edge that carries a `via` attribute.
// The alias name is taken from the `alias` attribute when the manifest
// grammar captured one, or (as a cross-language fallback) derived from the
// trailing segment of the `via` path. No language-specific alias format is
// assumed — the `alias` attribute can be any string, and the key is the raw
// token text after a leading sigil is stripped.

///|
priv struct AliasIndex {
  /// Keys are `package_dir \u{1f} alias_name` (alias without leading sigil).
  entries : Map[String, String]
}

///|
fn AliasIndex::new() -> AliasIndex {
  { entries: Map([]) }
}

///|
fn AliasIndex::set(
  self : AliasIndex,
  pkg_dir : String,
  alias_name : String,
  to : String,
) -> Unit {
  let key = pkg_dir + "\u{1f}" + alias_name
  if !self.entries.contains(key) {
    self.entries.set(key, to)
  }
}

///|
fn AliasIndex::get(
  self : AliasIndex,
  pkg_dir : String,
  alias_name : String,
) -> String? {
  self.entries.get(pkg_dir + "\u{1f}" + alias_name)
}

///|
fn build_alias_index(graph : @graph.CodeGraph) -> AliasIndex {
  let idx = AliasIndex::new()
  for edge in graph.get_edges() {
    if !(edge.kind is @graph.ModuleDependsOn) {
      continue
    }
    let via = edge.attrs.get("via").unwrap_or("")
    if via.length() == 0 {
      continue
    }
    let pkg_dir = dir_of(edge.from)
    let alias_attr = edge.attrs.get("alias").unwrap_or("")
    let alias_name = if alias_attr.length() > 0 {
      strip_sigil(alias_attr)
    } else {
      last_segment(via)
    }
    if alias_name.length() == 0 {
      continue
    }
    idx.set(pkg_dir, alias_name, edge.to)
  }
  idx
}

// ── Source-file alias → moduleDependsOn ───────────────────────────────────
//
// For each file that was analyzed under a spec with a "sigil-prefixed" token
// convention, scan its raw tokens. Each distinct alias referenced in the body
// of the file that resolves against the alias index produces one
// moduleDependsOn edge.

///|
fn emit_source_alias_edges(
  graph : @graph.CodeGraph,
  file_tokens : Array[FileTokens],
  specs : Map[String, @kgf_types.KGFSpec],
  alias_index : AliasIndex,
) -> Unit {
  for ft in file_tokens {
    let spec = match specs.get(ft.get_spec_name()) {
      Some(s) => s
      None => continue
    }
    // Skip files parsed by a manifest spec — those already emit their own
    // moduleDependsOn edges through the grammar (e.g. moon.pkg's `on
    // ImportItem`). Running the source-alias scan on a manifest would
    // duplicate every edge the manifest grammar already produced.
    if first_feature_value(spec, "manifest_role").length() > 0 {
      continue
    }
    let alias_token_kinds = collect_sigil_token_kinds(spec)
    if alias_token_kinds.length() == 0 {
      continue
    }
    let pkg_dir = dir_of(ft.get_path())
    let seen : Map[String, Bool] = {}
    for tok in ft.get_tokens() {
      if !contains_str(alias_token_kinds, tok.get_kind()) {
        continue
      }
      let alias_name = strip_sigil(tok.get_text())
      if alias_name.length() == 0 {
        continue
      }
      if seen.contains(alias_name) {
        continue
      }
      seen.set(alias_name, true)
      match alias_index.get(pkg_dir, alias_name) {
        Some(target) => {
          let sigil = leading_sigil(tok.get_text())
          let via_label = sigil + alias_name
          let attrs : Map[String, String] = {}
          attrs.set("via", via_label)
          attrs.set("dep_kind", "value")
          attrs.set("alias", via_label)
          graph.add_edge(
            @graph.EdgeKind::from_string("moduleDependsOn"),
            ft.get_path(),
            target,
            attrs~,
          )
        }
        None => ()
      }
    }
  }
}

///|
/// Return the token kinds whose pattern starts with a non-alphanumeric,
/// non-whitespace character — the spec's "sigil tokens". This is the
/// language-neutral way MoonBit's `@name`, Ruby's `@var`, etc. declare their
/// package/namespace references. A sigil token is recognized by its pattern
/// beginning with a character that is neither an ASCII letter, digit,
/// whitespace, regex quantifier, nor a character class opener.
fn collect_sigil_token_kinds(spec : @kgf_types.KGFSpec) -> Array[String] {
  let kinds : Array[String] = []
  for tok_def in spec.get_tokens() {
    let pattern = tok_def.get_pattern()
    if is_sigil_pattern(pattern) {
      kinds.push(tok_def.get_name())
    }
  }
  kinds
}

///|
fn is_sigil_pattern(pattern : String) -> Bool {
  if pattern.length() == 0 {
    return false
  }
  let chars = pattern.to_array()
  let c = chars[0]
  // Skip escapes — those start with `\` and typically match special chars.
  if c == '\\' {
    return false
  }
  // Alphanumeric first chars are "normal" tokens (Ident, KEYWORD patterns).
  if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
    return false
  }
  // Whitespace, quantifiers, class openers, grouping — not a sigil.
  if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
    return false
  }
  if c == '[' ||
    c == '(' ||
    c == '^' ||
    c == '*' ||
    c == '+' ||
    c == '?' ||
    c == '|' ||
    c == '.' {
    return false
  }
  // A sigil pattern must be followed by an identifier class so the full token
  // is "<sigil><name>". We check for a `[` shortly after — heuristic for an
  // identifier character class.
  let mut i = 1
  while i < chars.length() && i < 4 {
    if chars[i] == '[' {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn leading_sigil(s : String) -> String {
  if s.length() == 0 {
    return ""
  }
  let chars = s.to_array()
  let c = chars[0]
  if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
    return ""
  }
  let sb = StringBuilder::new()
  sb.write_char(c)
  sb.to_string()
}

///|
/// Strip a single leading non-alphanumeric character (the sigil).
fn strip_sigil(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let chars = s.to_array()
  let c = chars[0]
  if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
    return s
  }
  let sb = StringBuilder::new()
  for i = 1; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

// ── Canonicalization ─────────────────────────────────────────────────────
//
// A cluster is a package (or umbrella project containing packages). Each
// cluster is anchored by a manifest file whose KGF spec declares:
//   - manifest_role (package | project)
//   - identity_edge (edge kind naming the cluster)
//   - entry_edges   (edge kinds whose `to` points at the cluster's entry
//                    files — e.g. `main`, `types`, `exports` in npm)
//
// With these declarations in hand, the canonicalization pass can:
//   1. Build `ProjectEntry` records from every identity_edge in the graph.
//   2. Collect per-manifest entry candidates from every entry_edge.
//   3. For each edge target that looks like an external reference
//      (starts with any resolver's `bare_prefix`, or traverses any resolver's
//      `ancestors` directory), try to rewrite it to a canonical internal id.

///|
priv struct ClusterMeta {
  /// Strings that, when a target begins with one, indicate an external
  /// reference whose remainder encodes a cluster identity.
  bare_prefixes : Array[String]
  /// Ancestor-walk directory names (e.g. "node_modules/"). A target whose
  /// path contains "/<dir_name><cluster_name>/..." is a symlinked import of
  /// that cluster.
  ancestor_dirs : Array[String]
  /// Edge kinds declared by any manifest spec as `identity_edge`.
  identity_edge_kinds : @hashset.HashSet[String]
  /// Edge kinds declared by any manifest spec as entries.
  entry_edge_kinds : @hashset.HashSet[String]
  /// Edge kinds declared as `source_dir_edge`. Their `to` is a source
  /// sub-directory name relative to the manifest (e.g. "src" for MoonBit).
  source_dir_edge_kinds : @hashset.HashSet[String]
  /// Default source directory to assume when an identity-edge manifest is
  /// seen but no corresponding `source_dir_edge` was emitted for it. Keyed by
  /// the identity edge kind, since the convention is language-specific.
  default_source_dir_by_identity : Map[String, String]
}

///|
priv struct ProjectEntry {
  name : String
  root_dir : String
  manifest_path : String
  /// Source sub-directory under `root_dir`, per the manifest's
  /// `source_dir_edge` or spec-declared default. Empty when the manifest
  /// does not participate in source-dir resolution.
  source_dir : String
}

///|
fn build_cluster_meta(specs : Map[String, @kgf_types.KGFSpec]) -> ClusterMeta {
  let bare_prefixes : Array[String] = []
  let ancestor_dirs : Array[String] = []
  let identity_edge_kinds : @hashset.HashSet[String] = HashSet([])
  let entry_edge_kinds : @hashset.HashSet[String] = HashSet([])
  let source_dir_edge_kinds : @hashset.HashSet[String] = HashSet([])
  let default_source_dir_by_identity : Map[String, String] = {}
  let seen_prefix : Map[String, Bool] = {}
  let seen_anc : Map[String, Bool] = {}
  for entry in specs {
    let spec = entry.1
    let resolver = spec.get_resolver()
    let prefix = resolver.get_bare_prefix()
    if prefix.length() > 0 && !seen_prefix.contains(prefix) {
      seen_prefix.set(prefix, true)
      bare_prefixes.push(prefix)
    }
    for step in resolver.get_resolve_chain() {
      if step.get_step_type() == @kgf_types.ResolveStepType::Ancestors {
        for d in step.get_files() {
          let normalized = ensure_trailing_slash(d)
          if !seen_anc.contains(normalized) {
            seen_anc.set(normalized, true)
            ancestor_dirs.push(normalized)
          }
        }
      }
    }
    // A spec only contributes identity/entry edge kinds when it declares
    // itself as a manifest via `manifest_role`. This keeps source-language
    // specs from accidentally donating an edge kind to the cluster model.
    if first_feature_value(spec, "manifest_role").length() == 0 {
      continue
    }
    let identity_kinds_in_spec : Array[String] = match
      spec.get_feature("identity_edge") {
      Some(arr) => arr
      None => []
    }
    for e_kind in identity_kinds_in_spec {
      identity_edge_kinds.add(e_kind)
    }
    match spec.get_feature("entry_edges") {
      Some(arr) =>
        for e_kind in arr {
          entry_edge_kinds.add(e_kind)
        }
      None => ()
    }
    match spec.get_feature("source_dir_edge") {
      Some(arr) =>
        for e_kind in arr {
          source_dir_edge_kinds.add(e_kind)
        }
      None => ()
    }
    let default_src_dir = first_feature_value(spec, "source_dir_default")
    if default_src_dir.length() > 0 {
      for e_kind in identity_kinds_in_spec {
        default_source_dir_by_identity.set(e_kind, default_src_dir)
      }
    }
  }
  {
    bare_prefixes,
    ancestor_dirs,
    identity_edge_kinds,
    entry_edge_kinds,
    source_dir_edge_kinds,
    default_source_dir_by_identity,
  }
}

///|
fn first_feature_value(spec : @kgf_types.KGFSpec, name : String) -> String {
  match spec.get_feature(name) {
    Some(arr) => if arr.length() > 0 { arr[0] } else { "" }
    None => ""
  }
}

///|
fn ensure_trailing_slash(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let chars = s.to_array()
  if chars[chars.length() - 1] == '/' {
    return s
  }
  s + "/"
}

///|
fn canonicalize_external_refs(
  graph : @graph.CodeGraph,
  specs : Map[String, @kgf_types.KGFSpec],
) -> Unit {
  let meta = build_cluster_meta(specs)
  if meta.identity_edge_kinds.length() == 0 {
    return
  }
  let (projects, entries_by_manifest) = collect_clusters(graph, meta)
  if projects.length() == 0 {
    return
  }
  let modules = graph.get_modules()
  let rewrite : Map[String, String] = {}
  for edge in graph.get_edges() {
    let target = edge.to
    if rewrite.contains(target) {
      continue
    }
    if modules.contains(target) {
      continue
    }
    match
      resolve_to_internal(target, projects, entries_by_manifest, meta, modules) {
      Some(canonical) =>
        if canonical != target {
          rewrite.set(target, canonical)
        }
      None => ()
    }
  }
  if rewrite.is_empty() {
    return
  }
  graph.rewrite_edge_targets(rewrite)
}

///|
/// Walk the graph once and:
///  - produce ProjectEntry records keyed by cluster name.
///  - produce a manifest → [entry_file_path] map for later fallback lookup.
fn collect_clusters(
  graph : @graph.CodeGraph,
  meta : ClusterMeta,
) -> (Array[ProjectEntry], Map[String, Array[String]]) {
  // First pass: collect per-manifest source-dir overrides.
  let source_dir_by_manifest : Map[String, String] = {}
  for edge in graph.get_edges() {
    if meta.source_dir_edge_kinds.contains(edge.kind.to_string()) {
      if edge.to.length() > 0 {
        source_dir_by_manifest.set(edge.from, edge.to)
      }
    }
  }
  // Second pass: collect identity edges and entry edges, pairing each project
  // with the source_dir found in pass 1 (or the spec-declared default).
  let projects : Array[ProjectEntry] = []
  let entries_by_manifest : Map[String, Array[String]] = {}
  for edge in graph.get_edges() {
    let kind_str = edge.kind.to_string()
    if meta.identity_edge_kinds.contains(kind_str) {
      let name = edge.to
      if name.length() > 0 {
        let root_dir = dir_of(edge.from)
        let source_dir = match source_dir_by_manifest.get(edge.from) {
          Some(v) => v
          None =>
            match meta.default_source_dir_by_identity.get(kind_str) {
              Some(v) => v
              None => ""
            }
        }
        projects.push({ name, root_dir, manifest_path: edge.from, source_dir })
      }
    }
    if meta.entry_edge_kinds.contains(kind_str) {
      let entries = match entries_by_manifest.get(edge.from) {
        Some(a) => a
        None => {
          let a : Array[String] = []
          entries_by_manifest.set(edge.from, a)
          a
        }
      }
      entries.push(edge.to)
    }
  }
  (projects, entries_by_manifest)
}

///|
/// Try to rewrite `target` to a canonical internal id. Returns None when no
/// rewrite applies.
///
/// The rewrite walks two channels, both fully KGF-declared:
///
///   A. Bare prefix: strip any registered `bare_prefix`, then try to match
///      the remainder against any project/package identity. If it matches,
///      resolve the suffix relative to the manifest's containing directory
///      and consult the entry_edges for candidate entry files.
///   B. Ancestor walk: detect `…/<ancestor_dir>/<name>/…` segments (with
///      `<ancestor_dir>` supplied by a resolver's Ancestors step). Use the
///      same cluster-identity lookup as above on `<name>`.
fn resolve_to_internal(
  target : String,
  projects : Array[ProjectEntry],
  entries_by_manifest : Map[String, Array[String]],
  meta : ClusterMeta,
  modules : Map[String, @graph.ModuleNode],
) -> String? {
  // Channel A: bare prefix.
  let (prefix_stripped, _) = strip_any_prefix(target, meta.bare_prefixes)
  if prefix_stripped != target {
    match
      try_match_project(prefix_stripped, projects, entries_by_manifest, modules) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  // Channel B: ancestor traversal.
  for anc in meta.ancestor_dirs {
    match find_substring_pos(target, anc) {
      Some(idx) => {
        let after = substring_after(target, idx + anc.length())
        match try_match_project(after, projects, entries_by_manifest, modules) {
          Some(v) => return Some(v)
          None => ()
        }
      }
      None => ()
    }
  }
  None
}

///|
/// Given a path-like string that begins with a cluster identity, return the
/// canonical internal id that represents that cluster's target.
fn try_match_project(
  s : String,
  projects : Array[ProjectEntry],
  entries_by_manifest : Map[String, Array[String]],
  modules : Map[String, @graph.ModuleNode],
) -> String? {
  for proj in projects {
    let name = proj.name
    if name.length() == 0 {
      continue
    }
    match extract_rest(s, name) {
      Some(rel_path) => {
        // Build candidate directories. When the project declares a source_dir
        // (e.g. MoonBit's "src"), prefer `<root>/<src>/<rel>` first — that's
        // where the code actually lives on disk. Fall back to `<root>/<rel>`
        // for projects that don't nest their source packages (npm etc.).
        let candidate_dirs : Array[String] = []
        if proj.source_dir.length() > 0 {
          let with_src = join_path_parts(
            join_path_parts(proj.root_dir, proj.source_dir),
            rel_path,
          )
          candidate_dirs.push(with_src)
        }
        candidate_dirs.push(join_path_parts(proj.root_dir, rel_path))
        for candidate_dir in candidate_dirs {
          if modules.contains(candidate_dir) {
            return Some(candidate_dir)
          }
        }
        if rel_path.length() == 0 {
          // Cluster-root reference: prefer entry edges declared by the
          // manifest (main/types/exports for npm, packageEntry for moon.pkg…).
          match entries_by_manifest.get(proj.manifest_path) {
            Some(entries) =>
              for entry in entries {
                let full = join_path_parts(
                  proj.root_dir,
                  strip_leading_dot_slash(entry),
                )
                if modules.contains(full) {
                  return Some(full)
                }
              }
            None => ()
          }
        } else {
          // Sub-package reference: look for a nested manifest whose dirname
          // matches one of the candidate directories.
          for entry in entries_by_manifest {
            let manifest_path = entry.0
            if !modules.contains(manifest_path) {
              continue
            }
            let m_dir = dir_of(manifest_path)
            for candidate_dir in candidate_dirs {
              if m_dir == candidate_dir {
                return Some(manifest_path)
              }
            }
          }
          // No manifest under candidate_dir — languages without per-directory
          // manifests (Go, Python without __init__.py, etc.) still put source
          // files directly under the sub-package dir. Accept any module whose
          // file path sits exactly in candidate_dir. This is deterministic
          // because Map iteration in MoonBit preserves insertion order and
          // the first match wins.
          for candidate_dir in candidate_dirs {
            let prefix = candidate_dir + "/"
            for entry in modules {
              let mod_id = entry.0
              let mod = entry.1
              match mod.file {
                Some(f) =>
                  if f.has_prefix(prefix) && dir_of(f) == candidate_dir {
                    return Some(mod_id)
                  }
                None => ()
              }
            }
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
/// Join `base` and `tail` as path segments with a single `/` separator,
/// handling the common edge cases of either side being empty. When `base` is
/// empty the result is just `tail`; when `tail` is empty the result is just
/// `base`. When both are present, exactly one `/` is placed between them.
fn join_path_parts(base : String, tail : String) -> String {
  if base.length() == 0 {
    return tail
  }
  if tail.length() == 0 {
    return base
  }
  base + "/" + tail
}

///|
fn strip_leading_dot_slash(s : String) -> String {
  if s.has_prefix("./") {
    return substring_after(s, 2)
  }
  s
}

///|
fn strip_any_prefix(s : String, prefixes : Array[String]) -> (String, Bool) {
  for p in prefixes {
    if s.has_prefix(p) {
      return (substring_after(s, p.length()), true)
    }
  }
  (s, false)
}

///|
fn extract_rest(s : String, name : String) -> String? {
  if s == name {
    return Some("")
  }
  let name_slash = name + "/"
  if s.has_prefix(name_slash) {
    return Some(substring_after(s, name_slash.length()))
  }
  None
}

///|
fn substring_after(s : String, start : Int) -> String {
  let chars = s.to_array()
  if start >= chars.length() {
    return ""
  }
  let sb = StringBuilder::new()
  for i = start; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn find_substring_pos(text : String, needle : String) -> Int? {
  let t = text.to_array()
  let n = needle.to_array()
  if n.length() == 0 {
    return Some(0)
  }
  if n.length() > t.length() {
    return None
  }
  for i = 0; i <= t.length() - n.length(); i = i + 1 {
    let mut ok = true
    for j = 0; j < n.length(); j = j + 1 {
      if t[i + j] != n[j] {
        ok = false
        break
      }
    }
    if ok {
      return Some(i)
    }
  }
  None
}

///|
fn dir_of(path : String) -> String {
  let chars = path.to_array()
  let mut last = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last = i
    }
  }
  if last < 0 {
    return ""
  }
  let sb = StringBuilder::new()
  for i = 0; i < last; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn last_segment(path : String) -> String {
  let chars = path.to_array()
  let mut last = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      last = i
    }
  }
  if last < 0 {
    return path
  }
  let sb = StringBuilder::new()
  for i = last + 1; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn contains_str(arr : Array[String], target : String) -> Bool {
  for s in arr {
    if s == target {
      return true
    }
  }
  false
}
