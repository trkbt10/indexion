# interop

## API

- **`detect_wiki_spec`** (Function) — Detect which KGF wiki spec matches a directory.
- **`load_wiki_auto`** (Function) — Load wiki from directory, auto-detecting format.
- **`list_md_files_recursive`** (Function) — List .md files recursively (for nested directory wikis like GitLab).
- **`extract_sources_kgf`** (Function) — Extract META_COMMENT tokens containing indexion:sources metadata.
- **`convert_internal_to_wikilinks`** (Function) — Convert wiki:// links to [[wiki links]].
- **`parse_source_strings`** (Function) — Parse source reference strings like "src/foo.mbt:45-120" into @types.WikiSourceRef.
- **`list_md_files`** (Function) — List .md files in a directory (flat, without extension), excluding special files.
- **`load_wiki_spec`** (Function) — Load a named KGF wiki spec (e.g., "github-wiki", "gitlab-wiki").
- **`WikiBackendConfig`** (Struct) — Backend configuration for the generic load/export pipeline.
- **`slug_to_title`** (Function) — Convert slug to display title (capitalize after hyphens).
- **`WikiBackendSpec`** (Struct) — Loaded KGF spec context shared across wiki backends.
- **`detect_wiki_format`** (Function) — Detect wiki format from directory contents.
- **`load_external_wiki`** (Function) — Generic load for any external wiki backend.
- **`slug_to_id`** (Function) — Convert slug to lowercase ID.
- **`WikiFormat`** (Enum) — Wiki storage format.
