# okf

## API

- **`OkfDepRef`** (Struct) — A dependency reference from a package.
- **`sanitize_bundle_path`** (Function) — Sanitize an arbitrary identifier into a safe bundle-relative path:
- **`build_bundle`** (Function) — Build a complete OKF bundle from package concepts.
- **`allocate_concept_path`** (Function) — Reserve a concept file path under `dir` for `name`, escaping the final
- **`normalize_package_path`** (Function) — Normalize an analyzed package path into a bundle path segment:
- **`OkfBundleOptions`** (Struct) — Bundle-level generation options.
- **`render_frontmatter`** (Function) — Render a YAML frontmatter block, including both `---` fences and a
- **`yaml_scalar`** (Function) — Quote a scalar for YAML when plain style would be ambiguous;
- **`render_indexes`** (Function) — Render `index.md` for every directory that holds concepts (root included).
- **`needs_quoting`** (Function) — Whether a scalar needs double-quoting to survive YAML plain-style parsing.
- **`ConceptEntry`** (Struct) — Internal record of an emitted concept, used to build index listings.
- **`concept_link`** (Function) — Markdown link to a concept, resolved through the allocated path map.
- **`OkfDeclaration`** (Struct) — A public declaration surfaced in a package concept's Schema section.
- **`OkfValue`** (Enum) — A frontmatter value: scalar string or flow-style list of strings.
- **`parent_of`** (Function) — Parent directory of a bundle-relative path ("" at the top level).
- **`OkfPackageConcept`** (Struct) — One analyzed package, mapped to a single OKF concept document.
- **`escape_table_cell`** (Function) — Escape a value for use inside a markdown table cell.
- **`render_external_concept`** (Function) — Render one external dependency concept document.
- **`date_of`** (Function) — The `YYYY-MM-DD` prefix of an ISO 8601 instant.
- **`base_of`** (Function) — Final path component of a bundle-relative path.
- **`render_package_concept`** (Function) — Render one internal package concept document.
- **`render_log`** (Function) — Render the root `log.md` generation history.
- **`join_segments`** (Function) — 


- **`push_segment`** (Function) — 


- **`trim_trailing_newlines`** (Function) — 


- **`sorted_or_empty`** (Function) —
