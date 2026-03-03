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
