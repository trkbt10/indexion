///|
/// SoT for CLI option description strings.
/// All argparse `about=` text shared across multiple commands lives here.

///|
pub let specs_dir : String = "KGF specs directory (repeatable: first is the base set, each later one is an overlay layered on top)"

///|
pub let output : String = "Output file path (default: stdout)"

///|
pub let include_pattern : String = "Include files matching glob pattern (repeatable)"

///|
pub let exclude_pattern : String = "Exclude files matching glob pattern (repeatable)"

///|
pub let dir_required : String = "Error: Directory path required."

///|
/// Message for commands that need KGF specs but resolved an empty set.
/// Names every way a user can supply them, so the advice stays in one place.
pub let no_specs_loaded : String = "Error: no KGF specs were loaded. Run from a directory whose ancestry contains a `kgfs/` directory, install specs with `indexion kgf update`, add a project-local `.indexion/kgfs/` overlay, or pass --specs-dir."

///|
/// Sentinel value for `--specs-dir` meaning "not specified — auto-detect".
/// Matches the historical default so behavior is unchanged when the option is
/// omitted. `@kgf_features.load_registry` treats exactly this value as
/// auto-detection.
pub const SPECS_DIR_AUTO : String = "kgfs"

///|
/// Canonical name of the spec-directory option. Commands that need to name the
/// option — to define it, to read it back out of `Matches`, or to ask whether
/// it came from argv — use this rather than repeating the literal.
pub const SPECS_DIR_ARG : String = "specs-dir"

///|
/// SoT for the `--specs-dir` option definition.
///
/// The option is repeatable: the first occurrence is the base spec set and
/// every later occurrence is an overlay layered on top of it, so a spec whose
/// `language:` matches an already-loaded one replaces it. Giving the option
/// once is identical to the previous single-value behavior, and omitting it
/// leaves the `SPECS_DIR_AUTO` sentinel in place, which triggers auto-detection
/// plus the project-local `.indexion/kgfs/` overlay.
///
/// `name` exists because `indexion kgf` spells the same option `--kgf-dir`;
/// `global` makes the option inheritable by subcommands, which `kgf` needs.
pub fn specs_dir_option(
  name? : String = SPECS_DIR_ARG,
  global? : Bool = false,
) -> @argparse.OptionArg {
  @argparse.OptionArg(
    name,
    action=Append,
    about=specs_dir,
    default_values=[SPECS_DIR_AUTO],
    global~,
  )
}
