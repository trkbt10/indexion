///|
/// Mock file resolver for testing.
struct MockFileResolver {
  existing_files : Array[String]
}

///|
fn MockFileResolver::new(files : Array[String]) -> MockFileResolver {
  { existing_files: files }
}

///|
impl FileResolver for MockFileResolver with file_exists(self, path) {
  for file in self.existing_files {
    if file == path {
      return true
    }
  }
  false
}

///|
fn get_dot_style() -> @types.ModulePathStyle {
  @types.ModulePathStyle::from_string("dot").unwrap()
}

///|
fn get_colon_style() -> @types.ModulePathStyle {
  @types.ModulePathStyle::from_string("coloncol").unwrap()
}

///|
fn get_slash_style() -> @types.ModulePathStyle {
  @types.ModulePathStyle::from_string("slash").unwrap()
}

///|
test "join_path basic" {
  let result = join_path(["a", "b", "c"])
  assert_eq(result, "a/b/c")
}

///|
test "join_path with absolute" {
  let result = join_path(["/root", "path", "file.txt"])
  assert_eq(result, "/root/path/file.txt")
}

///|
test "join_path with empty parts" {
  let result = join_path(["a", "", "b", "c"])
  assert_eq(result, "a/b/c")
}

///|
test "dirname basic" {
  let result = dirname("/a/b/c.txt")
  assert_eq(result, "/a/b")
}

///|
test "dirname root file" {
  let result = dirname("/file.txt")
  assert_eq(result, "/")
}

///|
test "dirname no directory" {
  let result = dirname("file.txt")
  assert_eq(result, ".")
}

///|
test "basename basic" {
  let result = basename("/a/b/c.txt")
  assert_eq(result, "c.txt")
}

///|
test "basename no directory" {
  let result = basename("file.txt")
  assert_eq(result, "file.txt")
}

///|
test "normalize_path removes dot" {
  let result = normalize_path("a/./b/c")
  assert_eq(result, "a/b/c")
}

///|
test "normalize_path resolves dotdot" {
  let result = normalize_path("a/b/../c")
  assert_eq(result, "a/c")
}

///|
test "normalize_path removes double slash" {
  let result = normalize_path("a//b/c")
  assert_eq(result, "a/b/c")
}

///|
test "normalize_path absolute" {
  let result = normalize_path("/a/b/../c")
  assert_eq(result, "/a/c")
}

///|
test "relative_path same directory" {
  let result = relative_path("/a/b", "/a/b")
  assert_eq(result, ".")
}

///|
test "relative_path child" {
  let result = relative_path("/a/b", "/a/b/c/d")
  assert_eq(result, "c/d")
}

///|
test "relative_path parent" {
  let result = relative_path("/a/b/c", "/a/b")
  assert_eq(result, "..")
}

///|
test "relative_path sibling" {
  let result = relative_path("/a/b/c", "/a/b/d")
  assert_eq(result, "../d")
}

///|
test "is_absolute true" {
  assert_true(is_absolute("/path/to/file"))
}

///|
test "is_absolute false" {
  assert_false(is_absolute("relative/path"))
}

///|
test "module_to_path dot style" {
  let result = module_to_path("a.b.c", get_dot_style())
  assert_eq(result, "a/b/c")
}

///|
test "module_to_path colon style" {
  let result = module_to_path("a::b::c", get_colon_style())
  assert_eq(result, "a/b/c")
}

///|
test "module_to_path slash style" {
  let result = module_to_path("a/b/c", get_slash_style())
  assert_eq(result, "a/b/c")
}

///|
test "apply_aliases basic" {
  let aliases = [@types.ResolverAlias::new("@utils", "src/utils")]
  let result = apply_aliases("@utils/helper", aliases)
  assert_eq(result, "src/utils/helper")
}

///|
test "apply_aliases prefix pattern" {
  let aliases = [@types.ResolverAlias::new("^@/", "src/")]
  let result = apply_aliases("@/components/Button", aliases)
  assert_eq(result, "src/components/Button")
}

///|
test "apply_aliases no match" {
  let aliases = [@types.ResolverAlias::new("@utils", "src/utils")]
  let result = apply_aliases("other/path", aliases)
  assert_eq(result, "other/path")
}

///|
test "resolve_module with extensions" {
  let spec = @types.ResolverSpec::new(
    exts=[".js", ".ts"],
    indexes=["/index.js", "/index.ts"],
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
  )
  let resolver = MockFileResolver::new(["/project/src/utils/helper.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/index.ts", "./utils/helper", "/project", resolver,
  )
  assert_eq(result, "src/utils/helper.ts")
}

///|
test "resolve_module with index file" {
  let spec = @types.ResolverSpec::new(
    exts=[".js", ".ts"],
    indexes=["/index.js", "/index.ts"],
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
  )
  let resolver = MockFileResolver::new(["/project/src/components/index.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/index.ts", "./components", "/project", resolver,
  )
  assert_eq(result, "src/components/index.ts")
}

///|
test "resolve_module fallback to bare_prefix" {
  let spec = @types.ResolverSpec::new(
    exts=[".js"],
    indexes=[],
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    bare_prefix="node_modules/",
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "javascript", "/project/src/index.js", "lodash", "/project", resolver,
  )
  assert_eq(result, "node_modules/lodash")
}

///|
test "resolve_module namespace resolution" {
  let spec = @types.ResolverSpec::new(
    exts=[".php"],
    indexes=[],
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    ns_prefix=Some("vendor/"),
    ns_segments=2,
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "php", "/project/src/index.php", "Vendor\\Package\\Class", "/project",
    resolver,
  )
  assert_eq(result, "vendor/Vendor\\Package")
}

///|
test "resolve_module dot style module" {
  let spec = @types.ResolverSpec::new(
    exts=[".py"],
    indexes=["/__init__.py"],
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
  )
  let resolver = MockFileResolver::new(["/project/utils/helper.py"])
  let result = resolve_module(
    spec, "python", "/project/main.py", "utils.helper", "/project", resolver,
  )
  assert_eq(result, "utils/helper.py")
}

///|
test "resolve_module colon style module" {
  let spec = @types.ResolverSpec::new(
    exts=[".rs"],
    indexes=["/mod.rs"],
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
  )
  // utils::helper is a non-relative path, so it will be searched under project root
  let resolver = MockFileResolver::new(["/project/utils/helper.rs"])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "utils::helper", "/project", resolver,
  )
  assert_eq(result, "utils/helper.rs")
}
