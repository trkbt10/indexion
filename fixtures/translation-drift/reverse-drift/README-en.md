# widget-kit

A small UI widget toolkit for embedded dashboards.

## Installation

```bash
npm install widget-kit
```

## Usage

```js
import { Widget } from "widget-kit";

const w = new Widget({ id: "dash-1", theme: "dark" });
w.mount("#root");
```

## API

### `Widget(options)`

Creates a new widget instance.

| Option | Type   | Default  | Description       |
|--------|--------|----------|-------------------|
| id     | string | required | Unique widget id  |
| theme  | string | "light"  | Visual theme name |

### `widget.mount(selector)`

Mounts the widget into the DOM element matching `selector`.

## License

MIT. See `LICENSE` for details.
