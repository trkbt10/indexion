///|
/// `extends:` validation — checks that every spec's declared base exists and
/// that no `extends:` chain loops.
///
/// Loading a spec directory cannot report these problems: it runs on the hot
/// path of every command and deliberately degrades to "use the spec's own
/// sections" when a base is missing. This module re-runs the same resolution
/// (`@registry.resolve_spec_source`) with the diagnostics kept, so
/// `kgf check` can name the problem instead of leaving a derived spec quietly
/// missing its inherited grammar.

///|
/// Section name a diagnostic about `extends:` is reported under. The value is
/// the header field itself, since `extends:` lives in the header, not in a
/// `=== section`.
const EXTENDS_SECTION : String = "extends"

///|
/// Validate the `extends:` declaration of one spec against the set it was
/// loaded with.
///
/// `by_language` maps language name to spec source for every spec in the same
/// directory — the same set the registry resolves against, so the check sees
/// exactly what loading saw.
pub fn check_extends(
  source : @parser.KGFSpecSource,
  by_language : Map[String, @parser.KGFSpecSource],
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let (_, error) = @registry.resolve_spec_source(source, by_language)
  match error {
    Some(err) =>
      diagnostics.push(Diagnostic::new(EXTENDS_SECTION, "error", err.message()))
    None => ()
  }
  diagnostics
}

///|
/// Split every `.kgf` file under `dir` into raw sections, keyed by the
/// `language:` each one declares.
///
/// This is the set both the registry and `check_extends` resolve `extends:`
/// against, so `kgf check` and a normal load agree on what a base name means.
pub fn load_spec_sources(dir : String) -> Map[String, @parser.KGFSpecSource] {
  load_spec_sources_from_dirs([dir])
}

///|
/// Split every `.kgf` file under a layered chain of directories into raw
/// sections, keyed by the `language:` each one declares.
///
/// `dirs[0]` is the base set and each later entry is an overlay layered on
/// top, so a spec whose language repeats replaces the earlier one. Because the
/// map is keyed by language and filled in chain order, flattening and
/// overriding fall out of the fill itself — which is exactly what
/// `KGFRegistry::load_from_dirs` does before it resolves `extends:`, so
/// `kgf check` and a normal load agree on what a base name means even when an
/// overlay replaced the spec that name refers to.
pub fn load_spec_sources_from_dirs(
  dirs : Array[String],
) -> Map[String, @parser.KGFSpecSource] {
  let by_language : Map[String, @parser.KGFSpecSource] = Map([])
  for dir in dirs {
    collect_sources(dir, by_language)
  }
  by_language
}

///|
fn collect_sources(
  dir : String,
  by_language : Map[String, @parser.KGFSpecSource],
) -> Unit {
  try {
    if !@fs.is_dir(dir) {
      return
    }
    let entries = @fs.read_dir(dir).to_owned()
    entries.sort()
    for entry in entries {
      let path = dir + "/" + entry
      if entry.has_suffix(".kgf") {
        let source = @parser.parse_kgf_source(@fs.read_file_to_string(path))
        by_language.set(source.get_language(), source)
      } else if @fs.is_dir(path) && !entry.has_prefix(".") {
        collect_sources(path, by_language)
      }
    }
  } catch {
    _ => ()
  }
}

///|
/// Validate every spec in `by_language`, reporting each `extends:` problem
/// once, prefixed with the language it was found in.
pub fn check_extends_all(
  by_language : Map[String, @parser.KGFSpecSource],
) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  let languages : Array[String] = []
  for entry in by_language {
    languages.push(entry.0)
  }
  languages.sort()
  for language in languages {
    match by_language.get(language) {
      Some(source) =>
        for diagnostic in check_extends(source, by_language) {
          diagnostics.push(diagnostic)
        }
      None => ()
    }
  }
  diagnostics
}
