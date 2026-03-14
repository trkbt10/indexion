# indexion 開発ガイドライン

## 絶対原則: ハードコーディング禁止

**ハードコーディングは実装に対する冒涜である。絶対に避けろ。**

### 禁止例

```moonbit
// NG: 組織名・パッケージ名のハードコーディング
if parts[0] == "moonbitlang" || parts[0] == "peter-jerry-ye" {
  // ...
}

// NG: ディレクトリ名のハードコーディング
if part == "src" || part == "cmd" || part == "lib" {
  // ...
}

// NG: プレフィックスのハードコーディング
if name.has_prefix("pkg:") || name.has_prefix("npm:") {
  // ...
}
```

### 正しいアプローチ

1. **KGFスペックから情報を取得する**
   - `bare_prefix` → 外部パッケージのプレフィックス（`pkg:`, `npm:` など）
   - `relative_prefixes` → 相対パスのプレフィックス
   - `module_path_style` → モジュールパスのスタイル

2. **グラフの情報を使う**
   - `ModuleNode.file` フィールド → 内部パッケージかどうかの判定
   - 解析対象ファイルから得られた情報を基準にする

3. **設定ファイルから読み取る**
   - `moon.mod.json` → プロジェクト名、依存関係
   - `moon.pkg` → パッケージ依存関係

### 判定ロジックの原則

- 内部/外部の区別: グラフの `file` フィールドの有無で判定
- プレフィックスの削除: KGFの `bare_prefix` を使用
- パスの正規化: 解析対象ファイルのIDをそのまま使用

## KGFスペックの活用

このプロジェクトはKGF（Knowledge Graph Framework）を基盤としている。
言語固有の情報は必ずKGFスペックファイル（`kgfs/*.kgf`）から取得すること。

### KGFスペックの構造

```
=== lex        # トークン定義
=== grammar    # 文法規則
=== semantics  # 意味解析ルール
=== resolver   # モジュール解決設定
  sources:           # ソースファイルの拡張子
  relative_prefixes: # 相対パスのプレフィックス
  bare_prefix:       # 外部パッケージのプレフィックス
  resolve:           # 解決ルール
```

## コード品質

- 冗長なコードより、KGFスペックを拡張する
- 新しい言語対応はKGFスペックの追加で行う
- ロジックの重複を避け、共通化する

## SoT（Single Source of Truth）一覧

新しいコードを書く前に、既存の共通ユーティリティを確認すること。

### `@common`（cmd/indexion/common/args.mbt）

CLIコマンド共通ユーティリティ。新しいCLIユーティリティは必ずここに追加する。

| 関数 | 用途 |
|------|------|
| `get_arg_value(arg, prefix_len)` | `--key=value` からvalue抽出 |
| `parse_double(s)`, `parse_int(s)` | 文字列→数値変換 |
| `parse_output_arg(arg)` | `--output=`/`-o=` 解析 |
| `collect_files(dirs, includes~, excludes~, extensions~)` | ファイル収集+内容読み込み |
| `split_lines(text)` | 改行分割 |
| `format_percent(d)` | 0.0-1.0 → "75%" |
| `truncate(s, max_len)` | 文字列切り詰め |
| `trim_ascii_spaces(s)` | 空白トリム |
| `substring(s, start, end)` | 部分文字列 |
| `split_by_slash(path)` | パス分割 |
| `make_relative_path(path, base)` | 相対パス変換 |
| `normalize_path(path)` | 末尾スラッシュ除去 |
| `is_directory(path)` | ディレクトリ判定 |
| `parent_dir(path)`, `ancestor_dirs(dir)` | 親ディレクトリ走査 |
| `elapsed_ms(start_ms)` | 経過時間計測 |
| `extract_json_string(json, key)` | 簡易JSONパース |
| `extract_json_array(json, key)` | 簡易JSON配列パース |

### `@kgf_features`（src/kgf/features/）

KGFベースの言語非依存機能。言語固有のハードコーディングの代わりに使う。

| 関数 | 用途 |
|------|------|
| `extract_pub_declarations(content, path, registry)` | 公開宣言抽出（`pub fn`等のハードコーディング禁止） |
| `count_pub_declarations(content, path, registry)` | 公開宣言カウント |
| `build_line_func_map(content, path, registry)` | 行番号→関数名マップ |
| `extract_functions(tokens, file)` | 関数抽出 |
| `tokenize_files_with_kgf(files, registry)` | KGFトークン化 |

### その他のSoT

| モジュール | SoT対象 |
|-----------|---------|
| `@pipeline.discover_files` | ファイル探索（.gitignore/.indexionignore対応） |
| `@glob.glob_match` | Globパターンマッチング |
| `@plan_render.GitHubIssue::format` | GitHub Issue フォーマット |

## ドッグフーディング: indexionコマンド

このプロジェクト自身の開発に indexion を使う。
**コードを書いた後は必ずドッグフーディングで重複・課題を検出すること。**

### 類似コード検出（最重要）

```bash
# コマンド間の重複検出（閾値0.9=90%以上の類似）
moon run cmd/indexion --target native -- plan refactor --threshold=0.9 \
  --include='*.mbt' --exclude='*_wbtest.mbt' --exclude='*moon.pkg*' \
  --exclude='*pkg.generated*' cmd/indexion/

# src/ の類似検出
moon run cmd/indexion --target native -- explore --format=list src/
```

`plan refactor` の出力で **Duplicate Code Blocks** セクションに表示される重複は、
`@common` への共通化や KGF ベースへの置換で解消すべき。

### ドキュメンテーション計画

```bash
# カバレッジ確認（簡易）
moon run cmd/indexion --target native -- plan documentation --style=coverage .

# 完全な計画出力
moon run cmd/indexion --target native -- plan documentation .
```

※ ビルド時の警告（unused_package等）は無視してよい。出力の `# trkbt10/indexion` 以降が計画本体。
