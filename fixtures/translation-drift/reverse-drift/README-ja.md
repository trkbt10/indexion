# widget-kit

組み込みダッシュボード向けの小さな UI ウィジェットツールキット。

## インストール

```bash
npm install widget-kit
```

## 使い方

```js
import { Widget } from "widget-kit";

const w = new Widget({ id: "dash-1", theme: "dark", locale: "ja-JP" });
w.mount("#root");
await w.refresh();
```

## API

### `Widget(options)`

新しいウィジェットインスタンスを生成します。

| オプション | 型     | デフォルト | 説明                  |
|------------|--------|------------|-----------------------|
| id         | string | 必須       | ウィジェット固有のID  |
| theme      | string | "light"   | テーマ名              |
| locale     | string | "ja-JP"   | BCP-47 ロケールタグ   |

### `widget.mount(selector)`

`selector` に一致する DOM 要素にウィジェットをマウントします。

### `widget.refresh()`

非同期で再描画し、DOM が安定した時点で解決します。

## トラブルシューティング

- `WIDGET_KIT_DEBUG=1` で詳細ログ出力
- `widget-kit-debug.log` にイベント履歴が記録される
- `npm run diagnose` で環境チェック

## ライセンス

MIT。
