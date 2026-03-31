#!/bin/bash
set -euo pipefail

# indexion installer
# Usage: curl -fsSL https://raw.githubusercontent.com/trkbt10/indexion/main/install.sh | bash

REPO="trkbt10/indexion"
INSTALL_DIR="${INDEXION_INSTALL_DIR:-$HOME/.indexion}"

# OS-standard data directory for kgfs (matches platform.mbt SoT)
get_data_dir() {
    case "$(uname -s)" in
        Darwin*)
            echo "$HOME/Library/Application Support/Indexion"
            ;;
        Linux*)
            echo "${XDG_DATA_HOME:-$HOME/.local/share}/indexion"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/Indexion"
            ;;
        *)
            echo "${XDG_DATA_HOME:-$HOME/.local/share}/indexion"
            ;;
    esac
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[info]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

detect_platform() {
    local os
    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *) error "Unsupported OS: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)
            if [[ "$os" == "darwin" ]]; then
                echo "darwin-arm64"  # Rosetta compatible
            else
                echo "${os}-x64"
            fi
            ;;
        arm64|aarch64)
            if [[ "$os" == "darwin" ]]; then
                echo "darwin-arm64"
            else
                error "${os} arm64 not yet supported"
            fi
            ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

get_latest_version() {
    local url="https://api.github.com/repos/$REPO/releases/latest"
    if command -v curl &> /dev/null; then
        curl -fsSL "$url" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    elif command -v wget &> /dev/null; then
        wget -qO- "$url" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
    else
        error "curl or wget required"
    fi
}

download() {
    local url="$1" output="$2"
    info "Downloading $url"
    if command -v curl &> /dev/null; then
        curl -fsSL -o "$output" "$url"
    else
        wget -qO "$output" "$url"
    fi
}

verify_checksum() {
    local file="$1" checksum_url="$2"
    info "Verifying checksum..."

    local tmp_checksum="${file}.sha256.expected"
    download "$checksum_url" "$tmp_checksum"
    local expected=$(awk '{print $1}' "$tmp_checksum")
    rm -f "$tmp_checksum"

    local actual
    if command -v sha256sum &> /dev/null; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        warn "Cannot verify: sha256sum/shasum not found"
        return
    fi

    if [[ "$expected" != "$actual" ]]; then
        error "Checksum mismatch"
    fi
    info "Checksum OK"
}

main() {
    info "Detecting platform..."
    local platform=$(detect_platform)
    info "Platform: $platform"

    info "Fetching latest version..."
    local version=$(get_latest_version)
    [[ -z "$version" ]] && error "Failed to get version"
    info "Version: $version"

    local asset="indexion-${platform}"
    local is_windows=false
    local archive_ext="tar.gz"
    local bin_name="indexion"
    if [[ "$platform" == windows-* ]]; then
        is_windows=true
        archive_ext="zip"
        bin_name="indexion.exe"
    fi

    local url="https://github.com/$REPO/releases/download/$version/${asset}.${archive_ext}"
    local checksum_url="${url}.sha256"

    local tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    download "$url" "$tmp_dir/archive.${archive_ext}"
    verify_checksum "$tmp_dir/archive.${archive_ext}" "$checksum_url"

    info "Extracting..."
    if [[ "$is_windows" == true ]]; then
        unzip -qo "$tmp_dir/archive.zip" -d "$tmp_dir"
    else
        tar -xzf "$tmp_dir/archive.tar.gz" -C "$tmp_dir"
    fi

    info "Installing to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/bin"

    cp "$tmp_dir/$asset/$bin_name" "$INSTALL_DIR/bin/$bin_name"
    if [[ "$is_windows" != true ]]; then
        chmod +x "$INSTALL_DIR/bin/$bin_name"
    fi

    local data_dir=$(get_data_dir)
    mkdir -p "$data_dir"

    if [[ -d "$tmp_dir/$asset/kgfs" ]]; then
        rm -rf "$data_dir/kgfs"
        cp -r "$tmp_dir/$asset/kgfs" "$data_dir/kgfs"
        info "KGF specs installed to $data_dir/kgfs"
    fi

    if [[ -d "$tmp_dir/$asset/wiki" ]]; then
        rm -rf "$data_dir/wiki"
        cp -r "$tmp_dir/$asset/wiki" "$data_dir/wiki"
        info "Wiki frontend installed to $data_dir/wiki"
    fi

    if [[ ":$PATH:" != *":$INSTALL_DIR/bin:"* ]]; then
        warn "$INSTALL_DIR/bin is not in PATH"
        echo ""
        echo "Add to your shell profile:"
        echo "  export PATH=\"\$HOME/.indexion/bin:\$PATH\""
        echo ""
    fi

    info "Installed indexion $version"
    echo "Run 'indexion --help' to get started"
}

main "$@"
