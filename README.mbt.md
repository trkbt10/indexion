# indexion

> "The map is not the territory" - Alfred Korzybski

**indexion** is a source code exploration and documentation tool that helps you build dynamic maps of your codebase.

## Features

- **Similarity Analysis**: Find duplicated or similar code patterns
- **Refactoring Planning**: Generate actionable refactoring checklists
- **Documentation Generation**: KGF-based intelligent doc extraction
- **Multi-language Support**: Extensible via KGF specifications


## Commands

### `indexion explore`


Explores a directory and calculates pairwise similarity between all files.
Useful for understanding code patterns and finding potential duplications.

## Usage

```bash
indexion explore [options] <directory>
```


[Full documentation](cmd/indexion/explore/README.md)

### `indexion plan refactor`


Analyzes files in a directory, identifies similar code patterns using
TF-IDF or NCD algorithms, and generates a Markdown checklist for
refactoring candidates.

## Usage

```bash
indexion plan refactor [options] <directory>
```


[Full documentation](cmd/indexion/plan/refactor/README.md)

### `indexion doc gen`


Analyzes source code using KGF (Knowledge Graph Format) specifications,
extracts structure and documentation comments, and generates Markdown
or JSON output with optional Mermaid diagrams.

## Usage

```bash
indexion doc gen [options] [files...]
```


[Full documentation](cmd/indexion/doc/gen/README.md)

### `indexion doc readme`


Extracts `///` documentation comments from MoonBit source files and
generates README.md files for each package, plus an aggregated root README.

## Usage

```bash
indexion doc readme [options] [directory]
```


[Full documentation](cmd/indexion/doc/readme/README.md)

### `indexion sim`


Computes similarity/distance metrics between two text inputs using
various algorithms (TF-IDF cosine similarity, NCD compression distance,
or a weighted hybrid).

## Usage

```bash
indexion sim [options] <text1> <text2>
```


[Full documentation](cmd/indexion/similarity/README.md)

## Installation

### From Release

Download the appropriate binary for your platform from [Releases](https://github.com/trkbt10/indexion/releases).

| Platform | Archive |
|----------|---------|
| Linux x64 | `indexion-linux-x64.tar.gz` |
| macOS ARM64 | `indexion-macos-arm64.tar.gz` |
| Windows x64 | `indexion-windows-x64.zip` |

### From Source

```bash
# Clone repository
git clone https://github.com/trkbt10/indexion.git
cd indexion

# Build native binary
moon build --target native

# Binary is at: target/native/release/build/cmd/indexion/indexion
```

### Requirements

- MoonBit toolchain (for building from source)
- No runtime dependencies

## License

Apache License 2.0
