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

// NG: 関数名パターンのハードコーディング
if name.has_prefix("get_") || name == "new" || name == "default" {
  // ...
}

// NG: マジックナンバーの閾値
if file_count > 200 { ... }  // → 名前付き定数 or 構造体パラメータに

// NG: 言語名・ファイルパスのハードコーディング
buf.write_string("```moonbit\n")  // → 言語非依存に
let dir = "/tmp/indexion_par_"     // → @config.get_global_cache_dir() SoTを使う
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
| `find_json_key_position(chars, key)` | JSON key位置検索（上記2関数の共通基盤） |
| `split_display_name(name)` | `"pkg:path"` → `("pkg", "path")` 分割 |
| `get_dirname_prefix(name)` | display_name の `:` 前部分 |
| `get_relative_part(name)` | display_name の `:` 後部分 |

### `@config`（src/config/app.mbt）

OS標準ディレクトリ解決。新しいOS別パスが必要な場合は `resolve_os_dir` を使う。

| 関数 | 用途 |
|------|------|
| `resolve_os_dir(macos, xdg_env, linux, win_env, win_sub)` | OS別ディレクトリ解決の共通基盤 |
| `get_global_config_dir()` | 設定ディレクトリ |
| `get_global_data_dir()` | データディレクトリ |
| `get_global_cache_dir()` | キャッシュディレクトリ |

### `@config`（src/config/paths.mbt）

パス操作ユーティリティ。新しいパス操作関数は必ずここに追加する。

| 関数 | 用途 |
|------|------|
| `find_last_char(text, target)` | 最後の文字位置検索（SoT） |
| `basename(path)`, `extension(path)` | ファイル名・拡張子抽出 |
| `relative_to(base, path)` | 相対パス計算 |

### `@kgf_features`（src/kgf/features/）

KGFベースの言語非依存機能。言語固有のハードコーディングの代わりに使う。

| 関数 | 用途 |
|------|------|
| `extract_pub_declarations(content, path, registry)` | 公開宣言抽出（`pub fn`等のハードコーディング禁止） |
| `count_pub_declarations(content, path, registry)` | 公開宣言カウント |
| `build_line_func_map(content, path, registry)` | 行番号→関数名マップ |
| `extract_functions(tokens, file)` | 関数抽出 |
| `tokenize_files_with_kgf(files, registry)` | KGFトークン化 |

### `@batch`（src/pipeline/comparison/）

バッチ比較エンジン。全コマンド（explore, refactor, solid）が使う比較のSoT。

| 関数 | 用途 |
|------|------|
| `compare(files, config)` | 戦略ディスパッチ（hybrid/tfidf/apted/tsed） |
| `compare_hybrid(files, threshold)` | 動的ハイブリッド（TF-IDF+APTED自動選択） |
| `compare_with_prefilter(files, threshold, score_fn)` | TF-IDF事前フィルタ付き汎用比較 |
| `compare_tfidf(files, threshold)` | TF-IDF語彙類似度 |
| `compare_apted(files, threshold)` | APTEDツリー構造類似度 |

サブパッケージ:
- `candidates/` — 候補ペア生成（brute_force, tfidf_prefilter）
- `tree_extract/` — ファイル→ASTツリー変換

### `@parallel`（src/parallel/）

fork ベースの並列処理。ネイティブターゲット専用。

| 関数 | 用途 |
|------|------|
| `run_parallel(tasks)` | 複数タスクをforkで並列実行 |
| `available()` | fork利用可能かどうか |
| `cpu_count()` | CPUコア数 |

### その他のSoT

| モジュール | SoT対象 |
|-----------|---------|
| `@pipeline.discover_files` | ファイル探索（.gitignore/.indexionignore対応） |
| `@glob.glob_match` | Globパターンマッチング |
| `@plan_render.GitHubIssue::format` | GitHub Issue フォーマット |

## ドッグフーディング: indexionコマンド

このプロジェクト自身の開発に indexion を使う。
**コードを書いた後は必ずドッグフーディングで重複・課題を検出すること。**
**コミット前に必ず以下のサイクルを回し、検出された問題を修正してからコミットする。**

### 1. 重複検出（最重要）

```bash
# コマンド間の重複検出（ファイルレベル + 関数レベル）
moon run cmd/indexion --target native -- plan refactor --threshold=0.9 \
  --include='*.mbt' --exclude='*_wbtest.mbt' --exclude='*moon.pkg*' \
  --exclude='*pkg.generated*' cmd/indexion/

# src/ の重複検出
moon run cmd/indexion --target native -- plan refactor --threshold=0.9 \
  --include='*.mbt' --exclude='*_wbtest.mbt' --exclude='*moon.pkg*' \
  --exclude='*pkg.generated*' src/
```

**確認すべきセクション:**
- **Duplicate Code Blocks** — 行レベルの重複 → `@common` への共通化
- **Function-Level Duplicates** — 関数レベルの構造重複 → SoT抽出
- **Same-file duplicates** — 同一ファイル内の重複 → パラメータ化で統合

### 2. ドキュメンテーションカバレッジ

```bash
moon run cmd/indexion --target native -- plan documentation --style=coverage .
```

### 3. パッケージREADME生成

```bash
# 新規パッケージのREADMEのみ生成（既存は上書きしない）
moon run cmd/indexion --target native -- doc readme --per-package src/ cmd/indexion/
```

**注意:** `doc readme --per-package` は既存READMEをスキップする。
手書きREADMEの方が品質が高い場合は手書きを維持すること。

### 4. reconcile（ドキュメント整合性）

```bash
moon run cmd/indexion --target native -- plan reconcile .
```

※ ビルド時の警告（unused_package等）は無視してよい。
