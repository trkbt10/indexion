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
