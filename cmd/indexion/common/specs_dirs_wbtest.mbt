///|
/// CLI-level tests for the repeatable `--specs-dir` option.
///
/// These parse real argv through the shared option definition, so they cover
/// the contract every command inherits: omitting the option means auto-detect,
/// giving it once behaves as it always did, and repeating it builds a
/// base-then-overlays chain in the order the user typed.

///|
/// A throwaway command carrying only the shared `--specs-dir` definition.
fn specs_dirs_test_command() -> @argparse.Command {
  @argparse.Command("probe", options=[@help.specs_dir_option()])
}

///|
fn parse_specs_dirs(argv : Array[String]) -> Array[String] {
  let matches = specs_dirs_test_command().parse(argv=argv[:]) catch {
    _ => return ["<parse-error>"]
  }
  arg_specs_dirs(matches)
}

///|
test "common: omitting --specs-dir leaves the chain empty (auto-detect)" {
  assert_eq(parse_specs_dirs([]), [])
}

///|
test "common: a single --specs-dir is the base, with no overlays" {
  assert_eq(parse_specs_dirs(["--specs-dir=vendor/kgfs"]), ["vendor/kgfs"])
  assert_eq(parse_specs_dirs(["--specs-dir", "vendor/kgfs"]), ["vendor/kgfs"])
}

///|
test "common: repeating --specs-dir builds base-then-overlay in order" {
  assert_eq(
    parse_specs_dirs([
      "--specs-dir=vendor/kgfs", "--specs-dir=.indexion/kgfs", "--specs-dir=local",
    ]),
    ["vendor/kgfs", ".indexion/kgfs", "local"],
  )
}

///|
test "common: the auto-detect sentinel never reaches the chain" {
  // A user who spells out the historical default gets auto-detection, not a
  // literal relative `kgfs` directory forced as the base.
  assert_eq(parse_specs_dirs(["--specs-dir=kgfs"]), [])
  assert_eq(parse_specs_dirs(["--specs-dir=kgfs", "--specs-dir=mine"]), ["mine"])
}

///|
test "common: specs_dirs_of maps a single value to a chain" {
  assert_eq(specs_dirs_of("vendor/kgfs"), ["vendor/kgfs"])
  assert_eq(specs_dirs_of(""), [])
  assert_eq(specs_dirs_of("kgfs"), [])
}
