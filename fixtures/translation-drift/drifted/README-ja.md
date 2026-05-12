# widget-kit

組み込みダッシュボード向けの小さな UI ウィジェットツールキット。

## インストール

```bash
npm install widget-kit
```

## 使い方

```js
import { Widget } from "widget-kit";

const w = new Widget({ id: "dash-1", theme: "dark" });
w.mount("#root");
```

## API

### `Widget(options)`

新しいウィジェットインスタンスを生成します。

| オプション | 型     | デフォルト | 説明                  |
|------------|--------|------------|-----------------------|
| id         | string | 必須       | ウィジェット固有のID  |
| theme      | string | "light"   | テーマ名              |

### `widget.mount(selector)`

`selector` に一致する DOM 要素にウィジェットをマウントします。

## ライセンス

MIT。詳細は `LICENSE` を参照してください。
