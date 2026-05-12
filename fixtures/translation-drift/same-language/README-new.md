# widget-kit

A small UI widget toolkit for embedded dashboards.

## Installation

```bash
npm install widget-kit
```

## Usage

```js
import { Widget } from "widget-kit";

const w = new Widget({ id: "dash-1", theme: "dark", locale: "en-US" });
w.mount("#root");
await w.refresh();
```

## API

### `Widget(options)`

Creates a new widget instance.

| Option | Type   | Default  | Description           |
|--------|--------|----------|-----------------------|
| id     | string | required | Unique widget id      |
| theme  | string | "light"  | Visual theme name     |
| locale | string | "en-US"  | BCP-47 locale tag     |

### `widget.mount(selector)`

Mounts the widget into the DOM element matching `selector`.

### `widget.refresh()`

Re-renders the widget asynchronously and resolves once the DOM is stable.

## Configuration

Place a `widget-kit.config.json` at the project root:

```json
{
  "theme": "dark",
  "telemetry": false,
  "endpoints": {
    "metrics": "https://example.com/metrics"
  }
}
```

Environment overrides:

- `WIDGET_KIT_THEME` — overrides `theme`
- `WIDGET_KIT_TELEMETRY` — `"1"` enables telemetry

## License

MIT. See `LICENSE` for details.
