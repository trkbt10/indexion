## Installation

### Quick Install (Linux/macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/trkbt10/indexion/main/install.sh | bash
```

On Linux, installs binary and KGF specs to `~/.local/share/indexion/` with a symlink at `~/.local/bin/indexion`.
On macOS, installs to `~/.indexion/` with KGF specs in `~/Library/Application Support/Indexion/`.

If `~/.local/bin` (Linux) or `~/.indexion/bin` (macOS) is not in PATH, add to your shell profile:

```bash
# Linux (usually already in PATH)
export PATH="$HOME/.local/bin:$PATH"

# macOS
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

The resolved spec set is **layered**: a base set, plus any overlays applied on
top of it. A spec whose `language:` header matches one already loaded replaces
it — matched by language name, not by filename or category directory.

**Base set.** indexion searches for the base set in this order:
1. `INDEXION_KGFS_DIR` environment variable
2. `[global].kgfs_dir` in global config
3. `kgfs/` in the target project directory (walking up to the project root)
4. `kgfs/` in the current working directory
5. OS-standard data directory `.../kgfs/` when non-empty

**Project-local overlay.** If the analysed project has a `.indexion/kgfs/`
directory, it is layered on top of the base set. That is the way to patch one
spec without copying the installed set:

```
my-project/
├── .indexion/
│   └── kgfs/
│       └── programming/
│           └── rust.kgf   ← replaces the installed rust spec
└── src/
```

The directory may mirror the installed layout (`programming/`, `dsl/`, …) or be
flat — only the `language:` header decides what a file replaces. Every spec the
overlay does not redefine keeps coming from the base set.

**Explicit chain.** `--specs-dir` is repeatable. The first occurrence is the
base set and each later one is an overlay layered on top of it:

```bash
# Single value: use this directory as the whole spec set (as before).
indexion search "query" src/ --specs-dir=/opt/kgfs

# Chain: /opt/kgfs as the base, ./team-kgfs layered over it.
indexion search "query" src/ --specs-dir=/opt/kgfs --specs-dir=./team-kgfs
```

Passing `--specs-dir` at all replaces the whole chain: auto-detection and the
implicit `.indexion/kgfs/` overlay are not added on top. The same option is
spelled `--kgf-dir` on `indexion kgf` and `--specs` on `indexion digest`.

**Seeing which file won.** `indexion kgf list` prints the layers it resolved and
the origin of every spec, naming the file each overlay replaced:

```bash
indexion kgf list
```

`indexion kgf check` with no spec name validates the whole resolved set, so a
project can check its overlay together with the specs it layers over.

### Claude Code Skills

```bash
claude plugin marketplace add trkbt10/indexion-skills
```

### Requirements

- MoonBit toolchain (for building from source)
- No runtime dependencies
