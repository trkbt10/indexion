///|
/// Tests for project-local KGF spec overlay resolution.
///
/// The layout under test is a project root holding both a base `kgfs/`
/// directory and a project-local `.indexion/kgfs/` overlay, which is exactly
/// the shape `resolve_kgfs_dirs` has to compose.

///|
fn overlay_temp_dir(prefix : String) -> String {
  "/tmp/indexion-config-test/" + prefix
}

///|
/// Build `<root>/kgfs` and, when asked, `<root>/.indexion/kgfs`, returning the
/// root. `.indexion/` doubles as the project-root marker, so a base-only
/// fixture gets a `.git` marker file instead.
fn make_overlay_fixture(root : String, with_overlay : Bool) -> String {
  teardown_overlay_fixture(root)
  ensure_dir_recursive(join_path(root, "kgfs"))
  if with_overlay {
    ensure_dir_recursive(join_path(root, ".indexion/kgfs"))
  } else {
    ensure_dir_recursive(join_path(root, ".git"))
  }
  root
}

///|
fn teardown_overlay_fixture(root : String) -> Unit {
  for
    path in [
      join_path(root, ".indexion/kgfs"),
      join_path(root, ".indexion"),
      join_path(root, ".git"),
      join_path(root, "kgfs"),
      root,
    ] {
    if @fs.path_exists(path) {
      @fs.remove_dir(path) catch {
        _ => ()
      }
    }
  }
}

///|
test "config: resolve_kgfs_dirs layers the project overlay over the base" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-overlay-"),
    true,
  )
  let dirs = resolve_kgfs_dirs(target_dir=root)
  assert_eq(dirs.length(), 2)
  assert_eq(dirs[0], join_path(root, "kgfs"))
  assert_eq(dirs[1], join_path(root, ".indexion/kgfs"))
  teardown_overlay_fixture(root)
}

///|
test "config: resolve_kgfs_dirs returns the base alone when no overlay exists" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-no-overlay-"),
    false,
  )
  let dirs = resolve_kgfs_dirs(target_dir=root)
  assert_eq(dirs.length(), 1)
  assert_eq(dirs[0], join_path(root, "kgfs"))
  teardown_overlay_fixture(root)
}

///|
test "config: find_kgfs_overlay_dirs finds the overlay from a nested target" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-overlay-nested-"),
    true,
  )
  let nested = join_path(root, "src/deep")
  ensure_dir_recursive(nested)
  assert_eq(find_kgfs_overlay_dirs(target_dir=nested), [
    join_path(root, ".indexion/kgfs"),
  ])
  if @fs.path_exists(nested) {
    @fs.remove_dir(nested) catch {
      _ => ()
    }
  }
  if @fs.path_exists(join_path(root, "src")) {
    @fs.remove_dir(join_path(root, "src")) catch {
      _ => ()
    }
  }
  teardown_overlay_fixture(root)
}

///|
test "config: explicit --specs-dir chain replaces auto-detection entirely" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-explicit-"),
    true,
  )
  // Two explicit directories: base first, overlay second. No implicit overlay
  // is appended, and the order the user gave is preserved.
  let dirs = resolve_kgfs_dirs(
    explicit_paths=[join_path(root, ".indexion/kgfs"), join_path(root, "kgfs")],
    target_dir=root,
  )
  assert_eq(dirs.length(), 2)
  assert_eq(dirs[0], join_path(root, ".indexion/kgfs"))
  assert_eq(dirs[1], join_path(root, "kgfs"))
  teardown_overlay_fixture(root)
}

///|
test "config: resolve_kgfs_dirs never lists the same directory twice" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-dedup-"),
    true,
  )
  let overlay = join_path(root, ".indexion/kgfs")
  let dirs = resolve_kgfs_dirs(
    explicit_paths=[overlay, overlay, join_path(root, "kgfs")],
    target_dir=root,
  )
  assert_eq(dirs.length(), 2)
  assert_eq(dirs[0], overlay)
  assert_eq(dirs[1], join_path(root, "kgfs"))
  teardown_overlay_fixture(root)
}

///|
test "config: an explicit path that does not exist yields no directory" {
  let root = make_overlay_fixture(
    overlay_temp_dir("src-config-kgfs-missing-"),
    true,
  )
  assert_eq(
    resolve_kgfs_dirs(
      explicit_paths=[join_path(root, "__missing__")],
      target_dir=root,
    ),
    [],
  )
  teardown_overlay_fixture(root)
}

///|
test "config: kgfs_overlay_relative names the documented project-local path" {
  assert_eq(kgfs_overlay_relative(), ".indexion/kgfs")
}
