# indexion

> "The map is not the territory" - Alfred Korzybski

**indexion** is a source code exploration and documentation tool that helps you build dynamic maps of your codebase.

## Features

- **Similarity Analysis**: Find duplicated or similar code patterns
- **Refactoring Planning**: Generate actionable refactoring checklists
- **Documentation Generation**: KGF-based intelligent doc extraction
- **Multi-language Support**: Extensible via KGF specifications


## Commands

### `indexion plan refactor`


Analyzes files in a directory, identifies similar code patterns using
TF-IDF or NCD algorithms, and generates a Markdown checklist for
refactoring candidates.

## Usage

```bash
indexion plan refactor [options] <directory>
```


[Full documentation](cmd/indexion/plan/refactor/README.md)

### `indexion similarity`


Computes similarity/distance metrics between two text inputs using
various algorithms (TF-IDF cosine similarity, NCD compression distance,
or a weighted hybrid).

## Usage

```bash
indexion sim [options] <text1> <text2>
```


[Full documentation](cmd/indexion/similarity/README.md)

### `indexion explore`


Explores a directory and calculates pairwise similarity between all files.
Useful for understanding code patterns and finding potential duplications.

## Usage

```bash
indexion explore [options] <directory>
```


[Full documentation](cmd/indexion/explore/README.md)

### `indexion doc`



[Full documentation](cmd/indexion/doc/README.md)

### `indexion doc graph`



[Full documentation](cmd/indexion/doc/graph/README.md)

### `indexion doc readme`


Extracts `///` documentation comments from MoonBit source files and
outputs them in various formats. Supports flexible package discovery
with include/exclude patterns and template-based generation.

## Usage

```bash
indexion doc readme [options] [paths...]
```


[Full documentation](cmd/indexion/doc/readme/README.md)



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
