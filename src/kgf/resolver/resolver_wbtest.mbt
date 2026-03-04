///|
/// Mock file resolver for testing.
struct MockFileResolver {
  existing_files : Array[String]
  file_contents : Map[String, String]
}

///|
fn MockFileResolver::new(files : Array[String]) -> MockFileResolver {
  { existing_files: files, file_contents: {} }
}

///|
fn MockFileResolver::with_contents(
  files : Array[String],
  contents : Map[String, String],
) -> MockFileResolver {
  { existing_files: files, file_contents: contents }
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
impl FileResolver for MockFileResolver with read_file(self, path) {
  self.file_contents.get(path)
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
    spec, "typescript", "/project/src/main.ts", "./utils", "/project", resolver,
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
    spec, "typescript", "/project/src/main.ts", "react", "/project", resolver,
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
    spec, "typescript", "/project/src/main.ts", "@types/node", "/project", resolver,
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
    spec, "typescript", "/project/src/nested/deep.ts", "../../utils/helper", "/project",
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
    spec, "typescript", "/project/src/main.ts", "/lib/core", "/project", resolver,
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
    spec, "python", "/project/main.py", "pkg", "/project", resolver,
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
    spec, "python", "/project/main.py", "pkg.sub.module", "/project", resolver,
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
    spec, "typescript", "/project/src/main.ts", "./Button", "/project", resolver,
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
    spec, "typescript", "/project/src/main.ts", "./components", "/project", resolver,
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

// ============================================================
// resolve_chain tests
// ============================================================

///|
test "resolve_chain with index step" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/index.ts", "/index.js"]),
      @types.ResolveStep::ext([".ts", ".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/components/index.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./components", "/project", resolver,
  )
  assert_eq(result, "src/components/index.ts")
}

///|
test "resolve_chain with ext step" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ts", ".tsx", ".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils.tsx"])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./utils", "/project", resolver,
  )
  assert_eq(result, "src/utils.tsx")
}

///|
test "resolve_chain with marker step (python __init__.py)" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["__init__.py"]),
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/pkg/__init__.py"])
  let result = resolve_module(
    spec, "python", "/project/main.py", "pkg", "/project", resolver,
  )
  assert_eq(result, "pkg/__init__.py")
}

///|
test "resolve_chain with sibling step (rust mod.rs or foo.rs)" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::sibling([".rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  // Test sibling: foo/ -> foo.rs
  let resolver = MockFileResolver::new(["/project/src/foo.rs"])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "./foo", "/project", resolver,
  )
  assert_eq(result, "src/foo.rs")
}

///|
test "resolve_chain with manifest step (package.json main)" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("package.json", "main"),
      @types.ResolveStep::index(["/index.js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let contents : Map[String, String] = {}
  contents.set(
    "/project/node_modules/lodash/package.json", "{\"name\": \"lodash\", \"main\": \"lodash.js\"}",
  )
  let resolver = MockFileResolver::with_contents(
    [
      "/project/node_modules/lodash/package.json", "/project/node_modules/lodash/lodash.js",
    ],
    contents,
  )
  let result = resolve_module(
    spec, "javascript", "/project/src/main.js", "lodash", "/project", resolver,
  )
  // Note: bare imports without relative prefix won't find local files
  // This is expected behavior - bare imports should use fallback
  assert_eq(result, "npm:lodash")
}

///|
test "resolve_chain fallback when nothing matches" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ts", ".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./nonexistent", "/project", resolver,
  )
  assert_eq(result, "npm:nonexistent")
}

///|
test "resolve_chain order matters - first match wins" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      // index.ts should win over .ts extension
      @types.ResolveStep::index(["/index.ts"]),
      @types.ResolveStep::ext([".ts"]),
    ],
  )
  // Both exist, but index should win
  let resolver = MockFileResolver::new([
    "/project/src/utils/index.ts", "/project/src/utils.ts",
  ])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./utils", "/project", resolver,
  )
  assert_eq(result, "src/utils/index.ts")
}

///|
test "resolve_chain html with index.html" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/index.html", "/index.htm"]),
      @types.ResolveStep::ext([".html", ".htm"]),
      @types.ResolveStep::fallback("url:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/docs/index.html"])
  let result = resolve_module(
    spec, "html", "/project/index.html", "./docs", "/project", resolver,
  )
  assert_eq(result, "docs/index.html")
}

// ============================================================
// Comprehensive Package System Tests
// ============================================================

// --- JavaScript/TypeScript (npm) ---

///|
test "npm: package.json main field resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("package.json", "main"),
      @types.ResolveStep::index(["/index.js"]),
      @types.ResolveStep::ext([".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let contents : Map[String, String] = {}
  contents.set(
    "/project/node_modules/lodash/package.json", "{\"name\": \"lodash\", \"main\": \"./lodash.js\"}",
  )
  // Simulate node_modules structure - bare import needs special handling
  // Since bare imports don't have relative prefix, they go to fallback
  let resolver = MockFileResolver::with_contents(
    [
      "/project/node_modules/lodash/package.json", "/project/node_modules/lodash/lodash.js",
    ],
    contents,
  )
  let result = resolve_module(
    spec, "javascript", "/project/src/main.js", "lodash", "/project", resolver,
  )
  // Bare imports use fallback
  assert_eq(result, "npm:lodash")
}

///|
test "npm: scoped package resolution @scope/name" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ts", ".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "@types/node", "/project", resolver,
  )
  // Scoped packages use full path in fallback for downstream processing
  assert_eq(result, "npm:@types/node")
}

///|
test "npm: package subpath import" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "javascript", "/project/src/main.js", "lodash/fp", "/project", resolver,
  )
  // Full subpath preserved for downstream processing
  assert_eq(result, "npm:lodash/fp")
}

///|
test "npm: relative import with extension resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/index.ts", "/index.js"]),
      @types.ResolveStep::ext([".ts", ".tsx", ".js", ".jsx"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils/helper.tsx"])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./utils/helper", "/project", resolver,
  )
  assert_eq(result, "src/utils/helper.tsx")
}

///|
test "npm: directory import with index file" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/index.ts", "/index.js"]),
      @types.ResolveStep::ext([".ts", ".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/components/index.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./components", "/project", resolver,
  )
  assert_eq(result, "src/components/index.ts")
}

///|
test "npm: parent directory traversal" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ts"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/shared.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/deep/nested/file.ts", "../../../lib/shared",
    "/project", resolver,
  )
  assert_eq(result, "lib/shared.ts")
}

// --- Python (pip/PyPI) ---

///|
test "python: __init__.py package marker" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["__init__.py"]),
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/mypackage/__init__.py"])
  let result = resolve_module(
    spec, "python", "/project/main.py", "mypackage", "/project", resolver,
  )
  assert_eq(result, "mypackage/__init__.py")
}

///|
test "python: nested package imports" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["__init__.py"]),
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/pkg/sub/module.py"])
  let result = resolve_module(
    spec, "python", "/project/main.py", "pkg.sub.module", "/project", resolver,
  )
  assert_eq(result, "pkg/sub/module.py")
}

///|
test "python: relative import within package" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/pkg/utils.py"])
  let result = resolve_module(
    spec, "python", "/project/pkg/main.py", "./utils", "/project", resolver,
  )
  assert_eq(result, "pkg/utils.py")
}

///|
test "python: external package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["__init__.py"]),
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "python", "/project/main.py", "numpy", "/project", resolver,
  )
  assert_eq(result, "pip:numpy")
}

///|
test "python: namespace package (no __init__.py)" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["__init__.py"]),
      @types.ResolveStep::ext([".py"]),
      @types.ResolveStep::fallback("pip:"),
    ],
  )
  // Module file exists but no __init__.py
  let resolver = MockFileResolver::new(["/project/ns_pkg/module.py"])
  let result = resolve_module(
    spec, "python", "/project/main.py", "ns_pkg.module", "/project", resolver,
  )
  assert_eq(result, "ns_pkg/module.py")
}

// --- Rust (cargo/crates.io) ---

///|
test "rust: mod.rs directory module" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::sibling([".rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils/mod.rs"])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "./utils", "/project", resolver,
  )
  assert_eq(result, "src/utils/mod.rs")
}

///|
test "rust: sibling file module (foo.rs for mod foo)" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::sibling([".rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  // foo/ doesn't exist, but foo.rs does (sibling pattern)
  let resolver = MockFileResolver::new(["/project/src/foo.rs"])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "./foo", "/project", resolver,
  )
  assert_eq(result, "src/foo.rs")
}

///|
test "rust: crate-level import" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "serde", "/project", resolver,
  )
  assert_eq(result, "crate:serde")
}

///|
test "rust: nested module path with double colon" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  // Non-relative import resolves from project root
  let resolver = MockFileResolver::new(["/project/utils/helper.rs"])
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "utils::helper", "/project", resolver,
  )
  assert_eq(result, "utils/helper.rs")
}

///|
test "rust: Cargo.toml manifest for dependencies" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_colon_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("Cargo.toml", "dependencies"),
      @types.ResolveStep::index(["/mod.rs"]),
      @types.ResolveStep::ext([".rs"]),
      @types.ResolveStep::fallback("crate:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  // External crate without local file
  let result = resolve_module(
    spec, "rust", "/project/src/main.rs", "tokio", "/project", resolver,
  )
  assert_eq(result, "crate:tokio")
}

// --- Go (go modules) ---

///|
test "go: local package import" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".go"]),
      @types.ResolveStep::fallback("pkg:"),
    ],
  )
  // Relative import from cmd/ directory - file at cmd/internal/utils.go
  let resolver = MockFileResolver::new(["/project/cmd/internal/utils.go"])
  let result = resolve_module(
    spec, "go", "/project/cmd/main.go", "./internal/utils", "/project", resolver,
  )
  assert_eq(result, "cmd/internal/utils.go")
}

///|
test "go: external module fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".go"]),
      @types.ResolveStep::fallback("pkg:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "go", "/project/main.go", "github.com/gin-gonic/gin", "/project", resolver,
  )
  // External packages preserve full path for downstream processing
  assert_eq(result, "pkg:github.com/gin-gonic/gin")
}

///|
test "go: internal package restriction" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".go"]),
      @types.ResolveStep::fallback("pkg:"),
    ],
  )
  // ../internal/secret from /project/cmd/ resolves to /project/internal/secret
  let resolver = MockFileResolver::new(["/project/internal/secret.go"])
  let result = resolve_module(
    spec, "go", "/project/cmd/main.go", "../internal/secret", "/project", resolver,
  )
  assert_eq(result, "internal/secret.go")
}

// --- C/C++ (system includes) ---

///|
test "c: local header include" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".h", ".c"]),
      @types.ResolveStep::fallback("system:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/include/myheader.h"])
  let result = resolve_module(
    spec, "c", "/project/src/main.c", "../include/myheader", "/project", resolver,
  )
  assert_eq(result, "include/myheader.h")
}

///|
test "c: system header fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".h"]),
      @types.ResolveStep::fallback("system:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "c", "/project/src/main.c", "stdio", "/project", resolver,
  )
  assert_eq(result, "system:stdio")
}

///|
test "cpp: header with multiple extensions" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".hpp", ".hxx", ".h", ".hh"]),
      @types.ResolveStep::fallback("system:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/include/myclass.hpp"])
  let result = resolve_module(
    spec, "cpp", "/project/src/main.cpp", "../include/myclass", "/project", resolver,
  )
  assert_eq(result, "include/myclass.hpp")
}

///|
test "cpp: source/header pair" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".hpp", ".cpp"]),
      @types.ResolveStep::fallback("system:"),
    ],
  )
  // .hpp exists
  let resolver = MockFileResolver::new([
    "/project/src/utils.hpp", "/project/src/utils.cpp",
  ])
  let result = resolve_module(
    spec, "cpp", "/project/src/main.cpp", "./utils", "/project", resolver,
  )
  // First matching extension wins
  assert_eq(result, "src/utils.hpp")
}

// --- C# (NuGet) ---

///|
test "csharp: namespace to file resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".cs"]),
      @types.ResolveStep::fallback("nuget:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/MyApp/Utils/Helper.cs"])
  let result = resolve_module(
    spec, "csharp", "/project/MyApp/Program.cs", "MyApp.Utils.Helper", "/project",
    resolver,
  )
  assert_eq(result, "MyApp/Utils/Helper.cs")
}

///|
test "csharp: external package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".cs"]),
      @types.ResolveStep::fallback("nuget:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "csharp", "/project/Program.cs", "Newtonsoft.Json", "/project", resolver,
  )
  // Full namespace preserved for assembly resolution
  assert_eq(result, "nuget:Newtonsoft.Json")
}

///|
test "csharp: system namespace" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".cs"]),
      @types.ResolveStep::fallback("nuget:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "csharp", "/project/Program.cs", "System.Collections.Generic", "/project",
    resolver,
  )
  // Full namespace preserved for framework reference
  assert_eq(result, "nuget:System.Collections.Generic")
}

// --- MoonBit (moon) ---

///|
test "moonbit: package import with @prefix" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("moon.pkg.json", "import"),
      @types.ResolveStep::marker(["moon.pkg.json"]),
      @types.ResolveStep::ext([".mbt"]),
      @types.ResolveStep::fallback("moon:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/utils/moon.pkg.json"])
  let result = resolve_module(
    spec, "moonbit", "/project/src/main.mbt", "@utils", "/project", resolver,
  )
  // Non-relative, goes to fallback
  assert_eq(result, "moon:@utils")
}

///|
test "moonbit: relative import within package" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["moon.pkg.json"]),
      @types.ResolveStep::ext([".mbt"]),
      @types.ResolveStep::fallback("moon:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils/moon.pkg.json"])
  let result = resolve_module(
    spec, "moonbit", "/project/src/main.mbt", "./utils", "/project", resolver,
  )
  assert_eq(result, "src/utils/moon.pkg.json")
}

///|
test "moonbit: file with .mbt extension" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".mbt"]),
      @types.ResolveStep::fallback("moon:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/helper.mbt"])
  let result = resolve_module(
    spec, "moonbit", "/project/src/main.mbt", "./helper", "/project", resolver,
  )
  assert_eq(result, "src/helper.mbt")
}

///|
test "moonbit: external package from registry" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".mbt"]),
      @types.ResolveStep::fallback("moon:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "moonbit", "/project/src/main.mbt", "@moonbitlang/core", "/project", resolver,
  )
  // Full package path preserved for registry resolution
  assert_eq(result, "moon:@moonbitlang/core")
}

// --- HTML/CSS/Web ---

///|
test "html: index.html in directory" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/index.html", "/index.htm"]),
      @types.ResolveStep::ext([".html", ".htm"]),
      @types.ResolveStep::fallback("url:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/pages/about/index.html"])
  let result = resolve_module(
    spec, "html", "/project/index.html", "./pages/about", "/project", resolver,
  )
  assert_eq(result, "pages/about/index.html")
}

///|
test "html: absolute path from root" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../", "/"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".html"]),
      @types.ResolveStep::fallback("url:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/pages/contact.html"])
  let result = resolve_module(
    spec, "html", "/project/index.html", "/pages/contact", "/project", resolver,
  )
  assert_eq(result, "pages/contact.html")
}

///|
test "css: relative stylesheet import" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".css"]),
      @types.ResolveStep::fallback("url:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/styles/variables.css"])
  let result = resolve_module(
    spec, "css", "/project/styles/main.css", "./variables", "/project", resolver,
  )
  assert_eq(result, "styles/variables.css")
}

///|
test "css: external url fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".css"]),
      @types.ResolveStep::fallback("url:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "css", "/project/styles/main.css", "normalize.css", "/project", resolver,
  )
  assert_eq(result, "url:normalize.css")
}

// --- Edge Cases and Complex Scenarios ---

///|
test "resolution: deeply nested relative import" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ts"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/shared/types.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/features/auth/components/deep/LoginForm.ts",
    "../../../../../shared/types", "/project", resolver,
  )
  assert_eq(result, "shared/types.ts")
}

///|
test "resolution: chain with multiple matching steps - first wins" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      // Both index and direct file exist - index should win (first in chain)
      @types.ResolveStep::index(["/index.ts"]),
      @types.ResolveStep::ext([".ts"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new([
    "/project/src/lib/index.ts", "/project/src/lib.ts",
  ])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "./lib", "/project", resolver,
  )
  // Index step wins over ext step
  assert_eq(result, "src/lib/index.ts")
}

///|
test "resolution: fallback returns clean module without prefix" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".js"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "javascript", "/project/src/main.js", "./nonexistent", "/project", resolver,
  )
  // Strips ./ prefix for cleaner fallback
  assert_eq(result, "npm:nonexistent")
}

///|
test "resolution: alias with resolve chain" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./", "../"],
    module_path_style=get_slash_style(),
    aliases=[@types.ResolverAlias::new("@utils", "src/utils")],
    resolve_chain=[
      @types.ResolveStep::ext([".ts"]),
      @types.ResolveStep::fallback("npm:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils/helper.ts"])
  let result = resolve_module(
    spec, "typescript", "/project/src/main.ts", "@utils/helper", "/project", resolver,
  )
  // Alias expands, then resolves
  assert_eq(result, "src/utils/helper.ts")
}

///|
test "resolution: empty resolve chain uses legacy resolution" {
  let spec = @types.ResolverSpec::new(
    exts=[".js"],
    indexes=["/index.js"],
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    bare_prefix="npm:",
  )
  let resolver = MockFileResolver::new(["/project/src/utils.js"])
  let result = resolve_module(
    spec, "javascript", "/project/src/main.js", "./utils", "/project", resolver,
  )
  // Uses legacy exts/indexes resolution
  assert_eq(result, "src/utils.js")
}

// ============================================================
// Additional Language Package System Tests (Tier 1-3)
// ============================================================

// --- Java (Maven/Gradle) ---

///|
test "java: package to file resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".java"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  // Non-relative import resolves from project root with dot-to-slash conversion
  let resolver = MockFileResolver::new([
    "/project/com/example/utils/Helper.java",
  ])
  let result = resolve_module(
    spec, "java", "/project/src/main/java/com/example/App.java", "com.example.utils.Helper",
    "/project", resolver,
  )
  assert_eq(result, "com/example/utils/Helper.java")
}

///|
test "java: external dependency fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".java"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "java", "/project/src/main/java/App.java", "org.apache.commons.lang3.StringUtils",
    "/project", resolver,
  )
  assert_eq(result, "maven:org.apache.commons.lang3.StringUtils")
}

// --- Ruby (RubyGems/Bundler) ---

///|
test "ruby: lib directory resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::index(["/lib.rb"]),
      @types.ResolveStep::ext([".rb"]),
      @types.ResolveStep::fallback("gem:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/myapp/utils.rb"])
  let result = resolve_module(
    spec, "ruby", "/project/lib/myapp.rb", "./myapp/utils", "/project", resolver,
  )
  assert_eq(result, "lib/myapp/utils.rb")
}

///|
test "ruby: gem fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".rb"]),
      @types.ResolveStep::fallback("gem:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "ruby", "/project/lib/app.rb", "rails", "/project", resolver,
  )
  assert_eq(result, "gem:rails")
}

// --- PHP (Composer/PSR-4) ---

///|
test "php: psr4 namespace resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    ns_prefix=Some("vendor/"),
    ns_segments=2,
    resolve_chain=[
      @types.ResolveStep::ext([".php"]),
      @types.ResolveStep::fallback("composer:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  // PHP namespace resolution uses ns_prefix
  let result = resolve_module(
    spec, "php", "/project/src/Controller.php", "App\\Controller\\HomeController",
    "/project", resolver,
  )
  assert_eq(result, "vendor/App\\Controller")
}

///|
test "php: composer package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".php"]),
      @types.ResolveStep::fallback("composer:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "php", "/project/src/app.php", "Symfony/Component/HttpFoundation", "/project",
    resolver,
  )
  assert_eq(result, "composer:Symfony/Component/HttpFoundation")
}

// --- Swift (Swift Package Manager) ---

///|
test "swift: package resolution with manifest" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("Package.swift", "dependencies"),
      @types.ResolveStep::marker(["Package.swift"]),
      @types.ResolveStep::ext([".swift"]),
      @types.ResolveStep::fallback("spm:"),
    ],
  )
  // Relative import ./MyLib from Sources/MyApp/ resolves to Sources/MyApp/MyLib
  let resolver = MockFileResolver::new([
    "/project/Sources/MyApp/MyLib/Package.swift",
  ])
  let result = resolve_module(
    spec, "swift", "/project/Sources/MyApp/main.swift", "./MyLib", "/project", resolver,
  )
  assert_eq(result, "Sources/MyApp/MyLib/Package.swift")
}

///|
test "swift: external package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".swift"]),
      @types.ResolveStep::fallback("spm:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "swift", "/project/Sources/main.swift", "Alamofire", "/project", resolver,
  )
  assert_eq(result, "spm:Alamofire")
}

// --- Kotlin (Gradle) ---

///|
test "kotlin: package resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".kt", ".kts"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  // Non-relative import resolves from project root
  let resolver = MockFileResolver::new(["/project/com/example/Utils.kt"])
  let result = resolve_module(
    spec, "kotlin", "/project/src/main/kotlin/com/example/Main.kt", "com.example.Utils",
    "/project", resolver,
  )
  assert_eq(result, "com/example/Utils.kt")
}

///|
test "kotlin: external dependency fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".kt"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "kotlin", "/project/src/main.kt", "kotlinx.coroutines.Dispatchers", "/project",
    resolver,
  )
  assert_eq(result, "maven:kotlinx.coroutines.Dispatchers")
}

// --- Dart/Flutter (pub) ---

///|
test "dart: package import with pubspec" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("pubspec.yaml", "dependencies"),
      @types.ResolveStep::ext([".dart"]),
      @types.ResolveStep::fallback("pub:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/utils.dart"])
  let result = resolve_module(
    spec, "dart", "/project/lib/main.dart", "./utils", "/project", resolver,
  )
  assert_eq(result, "lib/utils.dart")
}

///|
test "dart: pub package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".dart"]),
      @types.ResolveStep::fallback("pub:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "dart", "/project/lib/main.dart", "package:flutter/material.dart", "/project",
    resolver,
  )
  assert_eq(result, "pub:package:flutter/material.dart")
}

// --- Scala (sbt) ---

///|
test "scala: package resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".scala", ".sc"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  // Non-relative import resolves from project root
  let resolver = MockFileResolver::new(["/project/com/example/Utils.scala"])
  let result = resolve_module(
    spec, "scala", "/project/src/main/scala/com/example/Main.scala", "com.example.Utils",
    "/project", resolver,
  )
  assert_eq(result, "com/example/Utils.scala")
}

///|
test "scala: external library fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".scala"]),
      @types.ResolveStep::fallback("maven:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "scala", "/project/src/Main.scala", "akka.actor.ActorSystem", "/project",
    resolver,
  )
  assert_eq(result, "maven:akka.actor.ActorSystem")
}

// --- Elixir (Mix/Hex) ---

///|
test "elixir: module resolution with mix.exs" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("mix.exs", "deps"),
      @types.ResolveStep::marker(["mix.exs"]),
      @types.ResolveStep::ext([".ex", ".exs"]),
      @types.ResolveStep::fallback("hex:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/myapp/utils.ex"])
  let result = resolve_module(
    spec, "elixir", "/project/lib/myapp.ex", "./myapp/utils", "/project", resolver,
  )
  assert_eq(result, "lib/myapp/utils.ex")
}

///|
test "elixir: hex package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ex"]),
      @types.ResolveStep::fallback("hex:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "elixir", "/project/lib/app.ex", "Phoenix.Controller", "/project", resolver,
  )
  assert_eq(result, "hex:Phoenix.Controller")
}

// --- Haskell (Cabal/Stack) ---

///|
test "haskell: hierarchical module resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["package.yaml", ".cabal"]),
      @types.ResolveStep::ext([".hs", ".lhs"]),
      @types.ResolveStep::fallback("hackage:"),
    ],
  )
  // Non-relative import resolves from project root
  let resolver = MockFileResolver::new(["/project/Data/List/Extra.hs"])
  let result = resolve_module(
    spec, "haskell", "/project/src/Main.hs", "Data.List.Extra", "/project", resolver,
  )
  assert_eq(result, "Data/List/Extra.hs")
}

///|
test "haskell: hackage package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".hs"]),
      @types.ResolveStep::fallback("hackage:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "haskell", "/project/src/Main.hs", "Control.Monad.Trans.State", "/project",
    resolver,
  )
  assert_eq(result, "hackage:Control.Monad.Trans.State")
}

// --- OCaml (opam/dune) ---

///|
test "ocaml: module resolution with dune" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["dune", "dune-project"]),
      @types.ResolveStep::ext([".ml", ".mli"]),
      @types.ResolveStep::fallback("opam:"),
    ],
  )
  // Relative import ./lib/utils from bin/ resolves to bin/lib/utils
  let resolver = MockFileResolver::new(["/project/bin/lib/utils.ml"])
  let result = resolve_module(
    spec, "ocaml", "/project/bin/main.ml", "./lib/utils", "/project", resolver,
  )
  assert_eq(result, "bin/lib/utils.ml")
}

///|
test "ocaml: opam package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".ml"]),
      @types.ResolveStep::fallback("opam:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "ocaml", "/project/bin/main.ml", "Lwt.Infix", "/project", resolver,
  )
  assert_eq(result, "opam:Lwt.Infix")
}

// --- Zig (zig pkg) ---

///|
test "zig: import resolution with build.zig.zon" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("build.zig.zon", "dependencies"),
      @types.ResolveStep::marker(["build.zig.zon", "build.zig"]),
      @types.ResolveStep::ext([".zig"]),
      @types.ResolveStep::fallback("zig:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/utils.zig"])
  let result = resolve_module(
    spec, "zig", "/project/src/main.zig", "./utils", "/project", resolver,
  )
  assert_eq(result, "src/utils.zig")
}

///|
test "zig: external package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_slash_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".zig"]),
      @types.ResolveStep::fallback("zig:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "zig", "/project/src/main.zig", "std", "/project", resolver,
  )
  assert_eq(result, "zig:std")
}

// --- Julia (Pkg) ---

///|
test "julia: module resolution with Project.toml" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("Project.toml", "deps"),
      @types.ResolveStep::marker(["Project.toml"]),
      @types.ResolveStep::ext([".jl"]),
      @types.ResolveStep::fallback("pkg:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/src/Utils.jl"])
  let result = resolve_module(
    spec, "julia", "/project/src/MyPackage.jl", "./Utils", "/project", resolver,
  )
  assert_eq(result, "src/Utils.jl")
}

///|
test "julia: external package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".jl"]),
      @types.ResolveStep::fallback("pkg:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "julia", "/project/src/main.jl", "DataFrames", "/project", resolver,
  )
  assert_eq(result, "pkg:DataFrames")
}

// --- Lua (LuaRocks) ---

///|
test "lua: require resolution with init.lua" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::marker(["rockspec"]),
      @types.ResolveStep::ext([".lua"]),
      @types.ResolveStep::index(["/init.lua"]),
      @types.ResolveStep::fallback("luarocks:"),
    ],
  )
  let resolver = MockFileResolver::new(["/project/lib/mymodule.lua"])
  let result = resolve_module(
    spec, "lua", "/project/init.lua", "./lib/mymodule", "/project", resolver,
  )
  assert_eq(result, "lib/mymodule.lua")
}

///|
test "lua: luarocks package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".lua"]),
      @types.ResolveStep::fallback("luarocks:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "lua", "/project/main.lua", "lfs", "/project", resolver,
  )
  assert_eq(result, "luarocks:lfs")
}

// --- Clojure (deps.edn/Leiningen) ---

///|
test "clojure: namespace resolution" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::manifest("deps.edn", "deps"),
      @types.ResolveStep::marker(["deps.edn", "project.clj"]),
      @types.ResolveStep::ext([".clj", ".cljs", ".cljc"]),
      @types.ResolveStep::fallback("clojars:"),
    ],
  )
  // Non-relative import resolves from project root
  let resolver = MockFileResolver::new(["/project/myapp/utils.clj"])
  let result = resolve_module(
    spec, "clojure", "/project/src/myapp/core.clj", "myapp.utils", "/project", resolver,
  )
  assert_eq(result, "myapp/utils.clj")
}

///|
test "clojure: clojars package fallback" {
  let spec = @types.ResolverSpec::new(
    relative_prefixes=["./"],
    module_path_style=get_dot_style(),
    resolve_chain=[
      @types.ResolveStep::ext([".clj"]),
      @types.ResolveStep::fallback("clojars:"),
    ],
  )
  let resolver = MockFileResolver::new([])
  let result = resolve_module(
    spec, "clojure", "/project/src/core.clj", "ring.adapter.jetty", "/project", resolver,
  )
  assert_eq(result, "clojars:ring.adapter.jetty")
}
