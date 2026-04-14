# src/config -- Configuration & Path Management

The config package is the Single Source of Truth for all path resolution, project/global configuration loading, and OS-specific directory detection. It serves as the foundation layer that nearly every other package depends on.

Configuration is layered: global config (OS-standard config dir) can be overridden by project config (`.indexion.toml` or `.indexion.json` in the project root). The package also provides specialized config structs for reconcile, digest, documentation, wiki, MCP, and embedding commands.

## Architecture

```mermaid
graph TD
    subgraph "Config Loading"
        global["load_global_config()"]
        project["load_project_config(path)"]
        merge["merge_global_into_file()"]
    end

    subgraph "Path Resolution"
        os_dirs["get_global_config_dir / data / cache"]
        paths["basename / dirname / extension / relative_to"]
        project_root["find_project_root()"]
        marker["find_nearest_marker_dir()"]
        kgfs["find_kgfs_dir()"]
    end

    subgraph "Command Configs"
        reconcile["ReconcileFileConfig"]
        digest["DigestFileConfig"]
        doc["DocConfig / DocFileConfig"]
        wiki["WikiFileConfig"]
        mcp["McpFileConfig"]
        embedding["EmbeddingFileConfig"]
    end

    global --> merge
    project --> merge
    merge --> reconcile
    merge --> digest
    merge --> doc
    merge --> wiki
    merge --> mcp
    merge --> embedding
```

## Key Types

| Type | File | Description |
|------|------|-------------|
| `ProjectFileConfig` | `project_config.mbt` | Project-level configuration with `inherit_global` flag and command-specific settings (reconcile, digest, embedding, mcp, doc, wiki) |
| `GlobalConfig` | `global_config.mbt` | Global configuration loaded from OS-standard config directory, mirrors ProjectFileConfig fields |
| `EffectiveReconcileConfig` | `project_config.mbt` | Merged reconcile config with provenance tracking |
| `ReconcileFileConfig` | `reconcile_config.mbt` | Reconcile command settings: specs dir, document scopes, thresholds |
| `ReconcileDocumentScope` | `reconcile_config.mbt` | Document scope with paths and spec patterns |
| `DigestFileConfig` | `digest_config.mbt` | Digest command settings (currently placeholder; provider settings moved to EmbeddingFileConfig) |
| `EmbeddingFileConfig` | `digest_config.mbt` | Embedding provider configuration shared across digest, search, serve, and wiki |
| `ProviderFileEntry` | `digest_config.mbt` | Per-provider entry with kind, dim, api_key_env, api_base_url, model |
| `DocConfig` | `doc_config.mbt` | Documentation command settings: output, packages, root structure |
| `DocOutputConfig` | `doc_config.mbt` | Documentation output settings (directory, format) |
| `DocPackageEntry` | `doc_config.mbt` | Per-package documentation configuration |
| `DocRootConfig` | `doc_config.mbt` | Root documentation sections configuration |
| `DocRootSection` | `doc_config.mbt` | Enum for root documentation section variants |
| `DocFileConfig` | `doc_config.mbt` | Doc settings from `.indexion.toml` / `.indexion.json` (config_path, per_package) |
| `WikiFileConfig` | `wiki_config.mbt` | Wiki branding configuration: title, logo, color scheme, locale, dark/light colors |
| `WikiColorConfig` | `wiki_config.mbt` | Color overrides for a single color scheme (background, foreground, primary, accent) |
| `McpFileConfig` | `mcp_config.mbt` | MCP command settings: transport, port, host, specs_dir |

## Public API

### OS Directory Resolution (`app.mbt`)

| Function | Description |
|----------|-------------|
| `get_global_config_dir()` | OS-standard config directory (e.g., `~/Library/Application Support/indexion`) |
| `get_global_data_dir()` | OS-standard data directory |
| `get_global_cache_dir()` | OS-standard cache directory |
| `get_install_dir()` | Binary install directory |
| `get_platform_asset_name()` | Platform-specific release asset name |
| `get_archive_extension()` | Archive extension for the current platform |
| `get_binary_name()` | Binary name for the current platform |

### Path Utilities (`paths.mbt`)

| Function | Description |
|----------|-------------|
| `normalize_path(path)` | Remove trailing slashes |
| `join_path(base, child)` | Join two path segments |
| `dirname(path)` | Get parent directory |
| `basename(path)` | Get file name |
| `extension(path)` | Get file extension |
| `substring(s, start, end)` | Extract substring by indices |
| `substring_from(s, start)` | Extract substring from start to end |
| `is_absolute_path(path)` | Check if path is absolute |
| `resolve_path(base_dir, path)` | Resolve relative path against a base |
| `relative_to(root, path)` | Compute relative path from root to path |
| `find_last_char(text, target)` | Find last occurrence of a character |
| `config_base_dir(target_dir, config_path)` | Base directory for config-relative paths (config dir if path present, else target dir) |
| `resolve_config_path_value(target_dir, config_path, value)` | Resolve a path value using config directory when present, otherwise target root |

### Project Root Detection (`paths.mbt`)

| Function | Description |
|----------|-------------|
| `find_project_root(target_dir, registry)` | Find project root using KGF registry markers |
| `find_nearest_marker_dir(target_dir, markers)` | Find nearest directory containing marker files |
| `ancestors_top_down(target_dir, root)` | List ancestor directories from root down to target |
| `find_indexion_config_path(target_dir)` | Find `.indexion.toml` or `.indexion.json` |
| `find_kgfs_dir(target_dir, registry)` | Find KGF specs directory |
| `get_kgfs_install_dir()` | Get installed KGF specs directory |
| `get_wiki_install_dir()` | Get installed wiki directory |

### Directory Management (`paths.mbt`)

| Function | Description |
|----------|-------------|
| `ensure_parent_dir(path)` | Create parent directories recursively |
| `ensure_dir_recursive(path)` | Create directories recursively |
| `resolve_project_indexion_dir(target_dir)` | Resolve `.indexion/` directory for a project |
| `default_reconcile_index_dir(target_dir)` | Default cache directory for reconcile index |
| `default_tool_dir(target_dir, tool_subdir)` | Default tool-specific directory |

### Config Loading (`project_config.mbt`, `global_config.mbt`)

| Function | Description |
|----------|-------------|
| `load_global_config()` | Load global config from OS config directory |
| `get_global_config_path()` | Get path to global config file |
| `parse_global_toml_config(content)` | Parse TOML content into GlobalConfig |
| `load_project_config(path)` | Load project config from file |
| `parse_project_toml_config(content)` | Parse TOML content into ProjectFileConfig |
| `merge_global_into_file(global, file)` | Merge global config into project config |
| `resolve_effective_reconcile_config(...)` | Resolve effective reconcile config with provenance |
| `load_effective_reconcile_config(...)` | Load and resolve effective reconcile config |
| `load_effective_digest_config(...)` | Load and resolve effective digest config |
| `load_effective_embedding_config(...)` | Load and resolve effective embedding config |

### Reconcile Config (`reconcile_config.mbt`)

| Function | Description |
|----------|-------------|
| `ReconcileFileConfig::empty()` | Create empty reconcile config |
| `resolve_reconcile_specs_dir(target_dir, explicit_specs_dir?)` | Resolve KGF specs directory for reconcile |
| `normalize_reconcile_doc_scope(scope)` | Normalize document scope name to canonical value (`package-docs`, `tree-docs`, `custom`) |
| `reconcile_doc_scope_paths(scope, index_patterns?, wildcard_patterns?)` | Default document glob paths for a given scope preset |
| `reconcile_doc_scope_specs(scope, doc_specs?)` | Default KGF spec names for a given scope preset |
| `resolve_reconcile_document_scope(scope, doc_paths?, ...)` | Build fully resolved document scope from scope name, paths, and specs |
| `load_reconcile_file_config(path)` | Load reconcile config from TOML or JSON file |
| `parse_reconcile_toml_config(content)` | Parse reconcile TOML content |
| `trim_toml_comment(line)` | Strip inline TOML comments while respecting quoted strings |

### Digest & Embedding Config (`digest_config.mbt`)

| Function | Description |
|----------|-------------|
| `DigestFileConfig::empty()` | Create empty digest config |
| `parse_digest_section_key(config, key, value)` | Parse key-value in `[digest]` section (currently no-op; provider settings in `[embedding]`) |
| `merge_digest_configs(primary, fallback)` | Merge two digest configs |
| `EmbeddingFileConfig::empty()` | Create empty embedding config |
| `ProviderFileEntry::empty()` | Create empty provider entry |
| `parse_embedding_section_key(config, key, value)` | Parse key-value in `[embedding]` section |
| `parse_embedding_provider_key(config, key, value)` | Parse key-value in `[[embedding.providers]]` section |
| `start_embedding_provider_entry(config)` | Start a new `[[embedding.providers]]` entry |
| `load_embedding_from_json_root(root)` | Load EmbeddingFileConfig from JSON root object (falls back to `[digest]` for backward compat) |
| `merge_embedding_configs(primary, fallback)` | Merge two embedding configs; primary takes precedence |

### Doc Config (`doc_config.mbt`)

| Function | Description |
|----------|-------------|
| `DocConfig::empty()` | Create empty doc config |
| `load_doc_config(path)` | Load doc config from JSON file |
| `DocFileConfig::empty()` | Create empty doc file config |
| `parse_doc_section_key(config, key, value)` | Parse key-value in `[doc]` section of TOML |
| `load_doc_from_json_root(root)` | Load DocFileConfig from JSON root object |
| `merge_doc_configs(primary, fallback)` | Merge two doc file configs |
| `load_effective_doc_config(project_config_path)` | Load merged doc config from project + global config files |

### Wiki Config (`wiki_config.mbt`)

| Function | Description |
|----------|-------------|
| `WikiColorConfig::empty()` | Create empty color config |
| `parse_wiki_color_key(config, key, value)` | Parse key-value in `[wiki.colors.dark]` or `[wiki.colors.light]` section |
| `merge_wiki_color_configs(primary, fallback)` | Merge two color configs; primary takes precedence |
| `WikiColorConfig::to_json(self)` | Convert color config to JSON object |
| `WikiFileConfig::empty()` | Create empty wiki branding config |
| `parse_wiki_section_key(config, key, value)` | Parse key-value in `[wiki]` section (flat keys: title, logo_url, logo_alt, default_color_scheme, locale) |
| `merge_wiki_configs(primary, fallback)` | Merge two wiki configs; primary takes precedence |
| `WikiFileConfig::to_branding_json(self)` | Convert wiki config to JSON for `/api/config` branding response |
| `load_wiki_from_json_root(root)` | Load WikiFileConfig from JSON root object |
| `load_effective_wiki_config(project_config_path)` | Load merged wiki config from project + global config files |

### MCP Config (`mcp_config.mbt`)

| Function | Description |
|----------|-------------|
| `McpFileConfig::empty()` | Create empty MCP config |
| `parse_mcp_section_key(config, key, value)` | Parse key-value in `[mcp]` section of TOML |
| `load_mcp_from_json_root(root)` | Load McpFileConfig from JSON root object |
| `merge_mcp_configs(primary, fallback)` | Merge two MCP configs; primary takes precedence |
| `load_effective_mcp_config(project_config_path)` | Load merged MCP config from project + global config files |

### Ignore Patterns (`ignore.mbt`)

| Function | Description |
|----------|-------------|
| `load_indexionignore(dir)` | Load `.indexionignore` patterns from a directory |
| `INDEXIONIGNORE_FILENAME` | Constant: `.indexionignore` |

## Dependencies

| Package | Alias | Purpose |
|---------|-------|---------|
| `moonbitlang/core/json` | `@json` | JSON config file parsing |
| `src/scope` | `@scope` | Scope resolution for config values |
| `src/platform` | `@platform` | OS/arch detection |
| `src/ignorefile` | `@ignorefile` | Ignore file pattern parsing |
| `moonbitlang/x/fs` | `@fs` | Filesystem operations |
| `mizchi/x/sys` | `@sys` | System utilities |
| `trkbt10/osenv/platform` | `@osenv_platform` | OS platform detection |
| `trkbt10/osenv/dirs` | `@osenv_dirs` | OS-standard directory resolution |
| `trkbt10/osenv/path` | `@osenv_path` | OS path operations |

> Source: `src/config/`
