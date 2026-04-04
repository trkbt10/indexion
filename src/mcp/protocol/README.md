# protocol

## API

- **`from_json_string`** (Function) — Parse a JSON string into a JSON-RPC 2.0 request.
- **`is_notification`** (Function) — Check whether this request is a notification (no id field).
- **`from_json`** (Function) — Parse a Json value into a JSON-RPC 2.0 request.
- **`response_ok`** (Function) — Build a JSON-RPC 2.0 success response.
- **`response_error`** (Function) — Build a JSON-RPC 2.0 error response.
- **`parse_error`** (Variable) — Standard JSON-RPC 2.0 error codes.
- **`JsonRpcRequest`** (Struct) — A parsed JSON-RPC 2.0 request.
