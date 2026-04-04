# types

## API

- **`server_capabilities`** (Function) — Build the capabilities object for the initialize response.
- **`TextContent`** (Struct) — MCP content block — text content only (sufficient for CLI tool results).
- **`enum_prop`** (Function) — Create a string property schema with allowed values.
- **`call_result`** (Function) — Build a tools/call result JSON from content blocks.
- **`text_result`** (Function) — Shorthand: success result with a single text block.
- **`error_result`** (Function) — Shorthand: error result with a single text block.
- **`PropertySchema`** (Struct) — Schema for a single property in a tool's input.
- **`ToolDefinition`** (Struct) — An MCP tool definition exposed by this server.
- **`ServerInfo`** (Struct) — MCP server info for the initialize response.
- **`InputSchema`** (Struct) — JSON Schema for a tool's input parameters.
- **`string_prop`** (Function) — Create a simple string property schema.
- **`initialize_result`** (Function) — Build a complete MCP initialize result.
- **`string_array_prop`** (Function) — Create a string array property schema.
- **`to_json`** (Function) — Serialize an InputSchema to JSON.
- **`bool_prop`** (Function) — Create a boolean property schema.
- **`number_prop`** (Function) — Create a number property schema.
