# indexion mcp

Start MCP (Model Context Protocol) server exposing indexion tools.

## Overview

Runs an MCP server that exposes indexion's analysis tools to AI assistants
such as Claude Code, Cursor, and other MCP-compatible editors. Supports
two transport modes: stdio (for editor integration) and HTTP.

## Usage

```bash
indexion mcp [options] [workspace_dir]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--transport=MODE` | Transport mode: `stdio`, `http` | `stdio` |
| `--port=INT` | HTTP server port (http transport only) | `3741` |
| `--host=HOST` | HTTP server host (http transport only) | `127.0.0.1` |
| `--specs-dir=DIR` | KGF specs directory | `kgfs` |

## Transport Modes

- **stdio** -- reads JSON-RPC from stdin, writes to stdout. Standard MCP transport for editor integrations.
- **http** -- serves MCP over HTTP POST `/mcp` endpoint with CORS support.

## Examples

```bash
# stdio mode (for Claude Code, Cursor, etc.)
indexion mcp

# HTTP mode on custom port
indexion mcp --transport=http --port=8080

# Specify workspace directory
indexion mcp /path/to/project
```

## Configuration

Respects `.indexion.toml` settings (`[mcp]` section) with CLI arguments taking precedence.

## API

- **`build_server`** (Function) -- Build an MCP server with all indexion tools registered.
