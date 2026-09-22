///|
/// Tests for OKF bundle construction.

///|
fn find_file(files : Array[(String, String)], path : String) -> String? {
  for entry in files {
    if entry.0 == path {
      return Some(entry.1)
    }
  }
  None
}

///|
fn contains_sub(s : String, sub : String) -> Bool {
  let hay = s.to_array()
  let needle = sub.to_array()
  if needle.length() == 0 {
    return true
  }
  for i = 0; i + needle.length() <= hay.length(); i = i + 1 {
    let mut matched = true
    for j = 0; j < needle.length(); j = j + 1 {
      if hay[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}

///|
fn sample_packages() -> Array[OkfPackageConcept] {
  let alpha : OkfPackageConcept = {
    path: "./src/alpha",
    name: "alpha",
    overview: "Alpha coordinates the work.",
    description: "Alpha coordinates the work.",
    languages: ["moonbit"],
    files: ["src/alpha/a.mbt"],
    declarations: [{ name: "run", kind: "Function", doc: "Run it.", }],
    depends_on: [
      { target: "src/beta", internal: true, via: Some("@beta"), },
      { target: "acme/util", internal: false, via: None, },
    ],
  }
  let beta : OkfPackageConcept = {
    path: "src/beta",
    name: "beta",
    overview: "",
    description: "Package beta containing 1 source file(s).",
    languages: ["moonbit"],
    files: ["src/beta/b.mbt"],
    declarations: [],
    depends_on: [],
  }
  [alpha, beta]
}

///|
test "bundle contains package and dependency concepts" {
  let files = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: Some("2026-07-20T00:00:00Z"),
  })
  assert_true(find_file(files, "packages/src/alpha.md") is Some(_))
  assert_true(find_file(files, "packages/src/beta.md") is Some(_))
  assert_true(find_file(files, "dependencies/acme/util.md") is Some(_))
}

///|
test "package concept carries frontmatter, schema, links, and files" {
  let files = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: Some("2026-07-20T00:00:00Z"),
  })
  guard find_file(files, "packages/src/alpha.md") is Some(alpha) else {
    fail("missing packages/src/alpha.md")
  }
  assert_true(alpha.has_prefix("---\ntype: Package\n"))
  assert_true(contains_sub(alpha, "title: src/alpha"))
  assert_true(contains_sub(alpha, "tags: [moonbit]"))
  assert_true(contains_sub(alpha, "timestamp: \"2026-07-20T00:00:00Z\""))
  assert_true(contains_sub(alpha, "Alpha coordinates the work."))
  assert_true(contains_sub(alpha, "# Schema"))
  assert_true(contains_sub(alpha, "| `run` | Function | Run it. |"))
  assert_true(
    contains_sub(
      alpha, "* Depends on [src/beta](/packages/src/beta.md) (as `@beta`)",
    ),
  )
  assert_true(
    contains_sub(alpha, "* Depends on [acme/util](/dependencies/acme/util.md)"),
  )
  assert_true(contains_sub(alpha, "* `src/alpha/a.mbt`"))
}

///|
test "internal dependents produce backlinks" {
  let files = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: None,
  })
  guard find_file(files, "packages/src/beta.md") is Some(beta) else {
    fail("missing packages/src/beta.md")
  }
  assert_true(
    contains_sub(beta, "* Used by [src/alpha](/packages/src/alpha.md)"),
  )
}

///|
test "external concept lists dependents" {
  let files = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: None,
  })
  guard find_file(files, "dependencies/acme/util.md") is Some(ext) else {
    fail("missing dependencies/acme/util.md")
  }
  assert_true(ext.has_prefix("---\ntype: External Package\n"))
  assert_true(contains_sub(ext, "title: acme/util"))
  assert_true(
    contains_sub(ext, "* Used by [src/alpha](/packages/src/alpha.md)"),
  )
}

///|
test "every directory gets an index listing" {
  let files = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: None,
  })
  guard find_file(files, "index.md") is Some(root) else {
    fail("missing root index.md")
  }
  assert_true(contains_sub(root, "# Subdirectories"))
  assert_true(contains_sub(root, "* [packages](packages/)"))
  assert_true(contains_sub(root, "* [dependencies](dependencies/)"))
  guard find_file(files, "packages/src/index.md") is Some(src_index) else {
    fail("missing packages/src/index.md")
  }
  assert_true(contains_sub(src_index, "# Package"))
  assert_true(
    contains_sub(
      src_index, "* [src/alpha](alpha.md) - Alpha coordinates the work.",
    ),
  )
}

///|
test "log.md is written only with a timestamp" {
  let with_ts = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: Some("2026-07-20T12:34:56Z"),
  })
  guard find_file(with_ts, "log.md") is Some(log) else {
    fail("missing log.md")
  }
  assert_true(contains_sub(log, "## 2026-07-20"))
  assert_true(
    contains_sub(
      log, "Generated 2 package concept(s) and 1 dependency concept(s) for demo.",
    ),
  )
  let without_ts = build_bundle(sample_packages(), {
    title: "demo",
    timestamp: None,
  })
  assert_true(find_file(without_ts, "log.md") is None)
}

///|
test "dependency on an unknown package is ignored in backlinks" {
  let orphan : OkfPackageConcept = {
    path: "src/orphan",
    name: "orphan",
    overview: "",
    description: "Package orphan.",
    languages: [],
    files: [],
    declarations: [],
    depends_on: [{ target: "src/missing", internal: true, via: None, }],
  }
  let files = build_bundle([orphan], { title: "demo", timestamp: None, })
  // The unknown internal target must not create a concept or crash...
  assert_true(find_file(files, "packages/src/missing.md") is None)
  // ...and the emitting concept must not carry a dangling link to it.
  guard find_file(files, "packages/src/orphan.md") is Some(orphan_md) else {
    fail("missing packages/src/orphan.md")
  }
  assert_true(!contains_sub(orphan_md, "/packages/src/missing.md"))
  assert_true(!contains_sub(orphan_md, "# Dependencies"))
}

///|
test "packages named like reserved files are escaped, not clobbered" {
  let index_pkg : OkfPackageConcept = {
    path: "src/digest/index",
    name: "index",
    overview: "",
    description: "Package index.",
    languages: ["moonbit"],
    files: ["src/digest/index/i.mbt"],
    declarations: [],
    depends_on: [],
  }
  let user_pkg : OkfPackageConcept = {
    path: "src/user",
    name: "user",
    overview: "",
    description: "Package user.",
    languages: ["moonbit"],
    files: ["src/user/u.mbt"],
    declarations: [],
    depends_on: [{ target: "src/digest/index", internal: true, via: None, }],
  }
  let files = build_bundle([index_pkg, user_pkg], {
    title: "demo",
    timestamp: None,
  })
  // The concept lives at an escaped filename...
  guard find_file(files, "packages/src/digest/index_.md") is Some(concept) else {
    fail("missing escaped concept packages/src/digest/index_.md")
  }
  assert_true(concept.has_prefix("---\ntype: Package\n"))
  // ...while the reserved path stays a directory listing (no frontmatter).
  guard find_file(files, "packages/src/digest/index.md") is Some(listing) else {
    fail("missing directory listing packages/src/digest/index.md")
  }
  assert_true(!listing.has_prefix("---"))
  // Links from other concepts resolve to the escaped path.
  guard find_file(files, "packages/src/user.md") is Some(user_md) else {
    fail("missing packages/src/user.md")
  }
  assert_true(contains_sub(user_md, "(/packages/src/digest/index_.md)"))
  // The backlink from the escaped concept resolves normally.
  assert_true(
    contains_sub(concept, "* Used by [src/user](/packages/src/user.md)"),
  )
}

///|
test "normalize_package_path handles relative and root inputs" {
  assert_eq(normalize_package_path("./src/config"), "src/config")
  assert_eq(normalize_package_path("src/config"), "src/config")
  assert_eq(normalize_package_path("."), "root")
  assert_eq(normalize_package_path(""), "root")
  assert_eq(normalize_package_path("/abs/path"), "abs/path")
}

///|
test "sanitize_bundle_path neutralizes separators and traversal" {
  assert_eq(sanitize_bundle_path("a:b\\c"), "a_b/c")
  assert_eq(sanitize_bundle_path("a//b/./c"), "a/b/c")
  assert_eq(sanitize_bundle_path("../a/../b"), "a/b")
}
