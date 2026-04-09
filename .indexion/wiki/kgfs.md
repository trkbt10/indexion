# kgfs -- KGF Spec Files

Knowledge Graph Framework (KGF) language specifications for indexion. KGF is a unified specification format for describing programming languages, DSLs, natural languages, and project configuration files. Each `.kgf` file defines lexical tokens, grammar rules, semantic actions, and module resolution strategies, allowing indexion to process source code in a language-agnostic way.

The specs are distributed as a standalone repository (`indexion-kgf`) and can be installed to `~/.indexion/kgfs` or referenced via the `INDEXION_KGFS_DIR` environment variable. indexion auto-detects the appropriate spec based on file extension.

## Contents

```
kgfs/
├── programming/     # 25 general-purpose language specs
├── dsl/             # 10 domain-specific language specs
├── natural/         # 4 natural language specs
├── project/         # 13 build/config file specs
├── toy/             # 11 experimental specs
├── universal.kgf    # Mixed-content fallback spec
├── LICENSE
└── README.md
```

### programming/ (25 specs)

C, C++, C#, Clojure, Dart, Elixir, Go, Haskell, Java, JavaScript, JavaScript-JSX, Julia, Kotlin, Lua, MoonBit, OCaml, PHP, Python, Ruby, Rust, Scala, Swift, TypeScript, TypeScript-JSX, Zig.

### dsl/ (10 specs)

CSS, HTML, Markdown, MoonBit Package (`moon.pkg`), npm `package.json`, Plaintext, SQL, SQL-DDL, TOML.

### natural/ (4 specs)

Chinese, English, Japanese, Korean.

### project/ (13 specs)

`build.gradle.kts`, `Cargo.toml`, `composer.json`, `.csproj`, `deno.json`, `Gemfile`, `go.mod`, `moon.mod.json`, `package.json`, `Package.swift`, `pom.xml`, `pyproject.toml`, `vcpkg.json`.

### toy/ (11 specs)

Experimental and proof-of-concept specs: base64, base64-utf8, JPEG/PNG binary format parsers (hex and base64-encoded), Japanese law text parser, and `reltext`.

### universal.kgf

A fallback spec for mixed-content text (`.txt`, `.text`). Combines programming constructs (keywords, operators, strings), Japanese segmentation (particles, kanji, hiragana, katakana), numbers with units, URLs, and a catch-all token. Used when no language-specific spec matches.

## Usage

indexion searches for KGF specs in this order:

1. Explicit `--specs-dir` CLI option
2. `INDEXION_KGFS_DIR` environment variable
3. `[global].kgfs_dir` in global config
4. `kgfs/` in the target project directory
5. `kgfs/` in the current working directory
6. OS-standard data directory when non-empty

```bash
# Install to user config directory
git clone https://github.com/trkbt10/indexion-kgf.git ~/.indexion/kgfs

# Or set environment variable
export INDEXION_KGFS_DIR=/path/to/indexion-kgf

# Inspect how a file is tokenized with a KGF spec
indexion kgf tokens src/main.mbt
indexion kgf inspect --spec=typescript src/app.ts
```

### KGF File Structure

Each `.kgf` file contains sections separated by `===`:

- `=== lex` -- Lexical rules (token patterns via regex)
- `=== grammar` -- PEG grammar rules
- `=== attrs` -- Token semantic attributes (keyword, operator, literal, etc.)
- `=== features` -- Consumer metadata (reference_token_kinds, document_symbol_kinds, etc.)
- `=== semantics` -- Actions to build semantic graphs (emit, link, scope)
- `=== resolver` -- Module resolution config (relative_prefixes, bare_prefix, exts, etc.)

## See Also

- [KGF System](wiki://kgf-system) -- how specs are structured and how to write new ones

> Source: `kgfs/`
