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

Analyze similarity across files in a directory.

## Usage

```bash
indexion explore [options] <directory>
```



[Full documentation](cmd/indexion/explore/README.md)

### `indexion plan refactor`

Generate refactoring plan based on file similarity analysis.

## Usage

```bash
indexion plan refactor [options] <directory>
```



[Full documentation](cmd/indexion/plan/refactor/README.md)

### `indexion sim`

Calculate text similarity and distance between two texts.

## Usage

```bash
indexion sim [options] <text1> <text2>
```



[Full documentation](cmd/indexion/similarity/README.md)

### `indexion doc`

Documentation commands for generating and managing documentation.


[Full documentation](cmd/indexion/doc/README.md)

### `indexion doc readme`

Extract documentation from source files and generate README files.

## Usage

```bash
indexion doc readme [options] [paths...]
```



[Full documentation](cmd/indexion/doc/readme/README.md)

## Installation

### Quick Install (Linux/macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/trkbt10/indexion/main/install.sh | bash
```

Installs to `~/.indexion/` with KGF language specs. Add to PATH:

```bash
export PATH="$HOME/.indexion/bin:$PATH"
```

### Manual Download

Download from [Releases](https://github.com/trkbt10/indexion/releases):

| Platform | Archive |
|----------|---------|
| Linux x64 | `indexion-linux-x64.tar.gz` |
| macOS ARM64 | `indexion-darwin-arm64.tar.gz` |
| Windows x64 | `indexion-windows-x64.zip` |

Each archive contains:
- `indexion` binary
- `kgfs/` directory (60+ language specifications)

Extract and move to your preferred location:

```bash
tar -xzf indexion-darwin-arm64.tar.gz
mv indexion-darwin-arm64/indexion ~/.local/bin/
mv indexion-darwin-arm64/kgfs ~/.indexion/
```

### From Source

```bash
git clone https://github.com/trkbt10/indexion.git
cd indexion
moon build --target native --release
# Binary: _build/native/release/build/cmd/indexion/indexion.exe
```

### KGF Specs Location

indexion searches for KGF specs in this order:
1. `--kgfs-dir` CLI option
2. `INDEXION_KGFS_DIR` environment variable
3. `~/.indexion/kgfs/`
4. `kgfs/` in project directory

### Requirements

- MoonBit toolchain (for building from source)
- No runtime dependencies

## License

Apache License 2.0
