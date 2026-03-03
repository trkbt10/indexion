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

// Additional comprehensive tests for resolver

///|
test "resolve_module typescript config" {
  // Match the actual typescript.kgf resolver section
  let spec = @types.ResolverSpec::new(
    sources=[".ts", ".tsx", ".d.ts"],
    exts=[".ts", ".tsx", ".d.ts"],
    indexes=["/index.ts", "/index.tsx", "/index.d.ts"],
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
    bare_prefix="npm:",
  )
  let resolver = MockFileResolver::new(["/project/src/utils.ts"])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "./utils",
    "/project",
    resolver,
  )
  assert_eq(result, "src/utils.ts")
}

///|
test "resolve_module typescript bare import" {
  let spec = @types.ResolverSpec::new(
    exts=[".ts", ".tsx", ".d.ts"],
    indexes=["/index.ts"],
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
    bare_prefix="npm:",
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "react",
    "/project",
    resolver,
  )
  assert_eq(result, "npm:react")
}

///|
test "resolve_module typescript scoped package" {
  let spec = @types.ResolverSpec::new(
    exts=[".ts"],
    indexes=["/index.ts"],
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    bare_prefix="npm:",
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "@types/node",
    "/project",
    resolver,
  )
  // Scoped packages should preserve the full module name
  assert_eq(result, "npm:@types")
}

///|
test "resolve_module parent directory" {
  let spec = @types.ResolverSpec::new(
    exts=[".ts"],
    indexes=[],
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
  )
  let resolver = MockFileResolver::new(["/project/utils/helper.ts"])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/nested/deep.ts",
    "../../utils/helper",
    "/project",
    resolver,
  )
  assert_eq(result, "utils/helper.ts")
}

///|
test "resolve_module absolute path from root" {
  let spec = @types.ResolverSpec::new(
    exts=[".ts"],
    indexes=[],
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
  )
  let resolver = MockFileResolver::new(["/project/lib/core.ts"])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "/lib/core",
    "/project",
    resolver,
  )
  assert_eq(result, "lib/core.ts")
}

///|
test "resolve_module python init file" {
  let spec = @types.ResolverSpec::new(
    exts=[".py"],
    indexes=["/__init__.py"],
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
  )
  let resolver = MockFileResolver::new(["/project/pkg/__init__.py"])
  let result = resolve_module(
    spec,
    "python",
    "/project/main.py",
    "pkg",
    "/project",
    resolver,
  )
  assert_eq(result, "pkg/__init__.py")
}

///|
test "resolve_module python nested module" {
  let spec = @types.ResolverSpec::new(
    exts=[".py"],
    indexes=["/__init__.py"],
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
  )
  let resolver = MockFileResolver::new(["/project/pkg/sub/module.py"])
  let result = resolve_module(
    spec,
    "python",
    "/project/main.py",
    "pkg.sub.module",
    "/project",
    resolver,
  )
  assert_eq(result, "pkg/sub/module.py")
}

///|
test "resolve_module tries multiple extensions" {
  let spec = @types.ResolverSpec::new(
    exts=[".js", ".ts", ".tsx"],
    indexes=[],
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
  )
  // Only .tsx file exists
  let resolver = MockFileResolver::new(["/project/src/Button.tsx"])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "./Button",
    "/project",
    resolver,
  )
  assert_eq(result, "src/Button.tsx")
}

///|
test "resolve_module tries index files in order" {
  let spec = @types.ResolverSpec::new(
    exts=[".ts"],
    indexes=["/index.js", "/index.ts"],
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
  )
  // Only index.ts exists
  let resolver = MockFileResolver::new(["/project/src/components/index.ts"])
  let result = resolve_module(
    spec,
    "typescript",
    "/project/src/main.ts",
    "./components",
    "/project",
    resolver,
  )
  assert_eq(result, "src/components/index.ts")
}

///|
test "apply_aliases multiple aliases" {
  let aliases = [
    @types.ResolverAlias::new("@utils", "src/utils"),
    @types.ResolverAlias::new("@components", "src/components"),
  ]
  let result1 = apply_aliases("@utils/helper", aliases)
  assert_eq(result1, "src/utils/helper")
  let result2 = apply_aliases("@components/Button", aliases)
  assert_eq(result2, "src/components/Button")
}

///|
test "apply_aliases order matters" {
  // More specific aliases should come first
  let aliases = [
    @types.ResolverAlias::new("@ui/icons", "assets/icons"),
    @types.ResolverAlias::new("@ui", "src/ui"),
  ]
  let result = apply_aliases("@ui/icons/home", aliases)
  assert_eq(result, "assets/icons/home")
}

///|
test "normalize_path edge cases" {
  assert_eq(normalize_path(""), "")
  assert_eq(normalize_path("/"), "/")
  assert_eq(normalize_path("."), ".")
  assert_eq(normalize_path(".."), "..")
  assert_eq(normalize_path("../.."), "../..")
  assert_eq(normalize_path("a/b/../../c"), "c")
  assert_eq(normalize_path("/a/b/../../c"), "/c")
}

///|
test "relative_path deeper nesting" {
  assert_eq(relative_path("/a/b/c", "/a/b/c/d/e"), "d/e")
  assert_eq(relative_path("/a/b/c/d/e", "/a/b/c"), "../..")
  assert_eq(relative_path("/a/b", "/c/d"), "../../c/d")
}

///|
test "join_path edge cases" {
  assert_eq(join_path([]), "")
  assert_eq(join_path([""]), "")
  assert_eq(join_path(["a"]), "a")
  assert_eq(join_path(["a", "b"]), "a/b")
  assert_eq(join_path(["/a", "b", "c"]), "/a/b/c")
}

///|
test "dirname edge cases" {
  assert_eq(dirname(""), ".")
  assert_eq(dirname("/"), "/")
  assert_eq(dirname("a"), ".")
  assert_eq(dirname("a/b"), "a")
  // Trailing slash is normalized, so /a/b/c/ becomes /a/b/c, and dirname is /a/b
  assert_eq(dirname("/a/b/c/"), "/a/b")
}

///|
test "basename edge cases" {
  assert_eq(basename(""), "")
  assert_eq(basename("/"), "")
  assert_eq(basename("a"), "a")
  assert_eq(basename("/a"), "a")
  assert_eq(basename("a/b/c.txt"), "c.txt")
}

///|
test "module_to_path edge cases" {
  assert_eq(module_to_path("", get_dot_style()), "")
  assert_eq(module_to_path("a", get_dot_style()), "a")
  assert_eq(module_to_path("a.b", get_dot_style()), "a/b")
  assert_eq(module_to_path("", get_colon_style()), "")
  assert_eq(module_to_path("a", get_colon_style()), "a")
  assert_eq(module_to_path("a::b", get_colon_style()), "a/b")
}
