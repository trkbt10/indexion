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
```

Binary output: `_build/native/release/build/cmd/indexion/indexion.exe`

### KGF Specs Location

indexion searches for KGF specs in this order:
1. Explicit specs directory CLI option for the command
2. `INDEXION_KGFS_DIR` environment variable
3. `[global].kgfs_dir` in global config
4. `kgfs/` in the target project directory
5. `kgfs/` in the current working directory
6. OS-standard data directory `.../kgfs/` when non-empty

### Claude Code Skills

```bash
claude plugin marketplace add trkbt10/indexion-skills
```

### Requirements

- MoonBit toolchain (for building from source)
- No runtime dependencies
