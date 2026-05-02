# fixtures/story/nankin-no-kirisuto

`indexion story` コマンドの主要テストフィクスチャ。
小説執筆における **n:m の素材 ↔ 本文の乖離** を検出する能力を検証するためのテストケース。

## このフィクスチャは何か

芥川龍之介「南京の基督」（1920年、青空文庫所収のパブリックドメイン）の本文を `prose/` に置き、
その作品を執筆したと **仮想する** 著者が事前に書いたであろう創作素材（プロット、設定、調査メモ、場面ノート）を `sources/` に配置している。

`sources/` の内容は **すべて創作物** （フィクションのフィクション）で、
実際に芥川がこのような素材を残したわけではない。
「もし作家がこういう素材から書き始めたなら」というシミュレーションを、
n:m 乖離検出の現実的なベンチマークとして提供する。

## 構成

```
fixtures/story/nankin-no-kirisuto/
├── README.md                       ← 本ファイル
├── sources/                        ← 仮想的な執筆素材（n 側）
│   ├── plot/
│   │   ├── 01-outline.md           初稿プロット（四幕構成、テーマ＝信仰の救済）
│   │   └── 02-revision.md          改稿プロット（五幕構成、テーマ＝皮肉の構造）
│   ├── references/
│   │   ├── characters.md           登場人物覚書（金花、外国人、父、朋輩、旅行家）
│   │   ├── settings.md             舞台設定（1910年代南京、奇望街、秦淮河、金花の部屋、夢の場面）
│   │   └── research-notes.md       調査メモ（カトリック史、楊梅瘡治療、地理、通貨、参考作品）
│   └── scene-notes/
│       ├── opening-scene.md        冒頭場面のノート
│       ├── encounter-scene.md      邂逅場面のノート
│       └── morning-after-scene.md  翌朝場面のノート
└── prose/                          ← 本文（m 側）
    ├── 01-chapter.txt              金花の境遇・信仰・病・拒絶（原作 第一節 前半）
    ├── 02-chapter.txt              外国人の来訪と邂逅（原作 第一節 後半）
    ├── 03-chapter.txt              夢・奇蹟の朝（原作 第二節）
    └── 04-chapter.txt              翌年春の後日譚（原作 第三節）
```

### 章割りの根拠

原文は「一」「二」「三」の三節構成。フィクスチャでは四章に分けるため、
最も長い「一」を **金花の信仰と病（拒絶までの内面）** と **外国人の来訪以降（外的事件）** で分割した。
分割点は「金花はうす暗いランプの火に……」の段落冒頭で、
場面転換（独白から事件へ）として自然なブレーク。

## 出典と権利

- 底本：青空文庫「南京の基督」（芥川龍之介、初出『中央公論』大正九年七月、原作1920年）
  - URL: https://www.aozora.gr.jp/cards/000879/files/105_15146.html
- 著作権：芥川龍之介は1927年没。日本・米国いずれにおいてもパブリックドメイン。
- 本文の処理：青空文庫テキストからルビ（《...》）と編集記号（［＃...］）を除去して `prose/` に格納。
  本文の文字列は変更していない。

## 想定する `indexion story` の使い方

コマンド仕様は未確定。下記はプレースホルダ。

```bash
# n:m 乖離レポートを出す（想定）
moon run cmd/indexion --target native -- story diverge \
  --sources fixtures/story/nankin-no-kirisuto/sources \
  --prose fixtures/story/nankin-no-kirisuto/prose

# プロット v1 ↔ v2 の差分が本文にどう反映されたかを照合（想定）
moon run cmd/indexion --target native -- story conflict \
  --plot-v1 fixtures/story/nankin-no-kirisuto/sources/plot/01-outline.md \
  --plot-v2 fixtures/story/nankin-no-kirisuto/sources/plot/02-revision.md \
  --prose fixtures/story/nankin-no-kirisuto/prose

# 本文に登場する固有名詞・物品が素材のいずれにも出てこない（drift / out-of-source）を検出（想定）
moon run cmd/indexion --target native -- story drift \
  --sources fixtures/story/nankin-no-kirisuto/sources \
  --prose fixtures/story/nankin-no-kirisuto/prose
```

## 規模

- `sources/` 合計：約 9.5 KB / 8 ファイル（日本語、約 6,500 文字）
- `prose/` 合計：約 30 KB / 4 ファイル（日本語、約 10,100 文字）
- n:m 語彙乖離を検出するに足る素材量を確保している。

## Seeded test cases

ツールが正しく動いていれば検出すべき **既知の乖離** を意図的に埋め込んでいる。
グランドトゥルース台帳：

### A. プロット側にあって本文に無いもの（under-coverage / plot-only）

| ID | 素材 | 本文 | 説明 |
|----|------|------|------|
| A-1 | `sources/plot/02-revision.md` 第三幕で **銀の十字架** と明記 | `prose/02-chapter.txt`〜`03-chapter.txt` では **真鍮の十字架**（「真鍮の十字架」「小さな真鍮の十字架」） | プロット改稿で素材を「銀」に統一したのに、本文は v1 同様「真鍮」のまま。素材の素材指定が反映されていない。 |
| A-2 | `sources/plot/02-revision.md` 第四幕で **白い鳩**（聖霊の象徴）が窓辺に止まる | `prose/03-chapter.txt` には鳩は登場しない | 改稿で導入した象徴的物体が本文に反映されていない。 |
| A-3 | `sources/references/characters.md` で父は **籐の杖** に頼って歩く、`02-revision.md` 第一幕でも杖を見せる予定 | `prose/01-chapter.txt` で父は「もう腰も立たない」と語られるのみで、杖は登場しない（杖は別人物——人力車夫を打つ通行人の手に出てくる） | キャラ属性のうち杖が本文に書かれていない。 |

### B. 本文側にあって素材に無いもの（drift / prose-only）

| ID | 本文 | 素材 | 説明 |
|----|------|------|------|
| B-1 | `prose/01-chapter.txt`、`prose/02-chapter.txt`、`prose/03-chapter.txt` で **翡翠の耳環** が再三登場（前年春に旅行家から贈られた、邂逅場面・夢の場面でも輝く） | `sources/references/characters.md` の金花の服装欄、`sources/scene-notes/opening-scene.md` のいずれにも記載なし。`opening-scene.md` には保留メモ（「耳環は出すかどうか保留」）のみある | 素材で保留にした小道具を本文では確定的に使ってしまっている。素材→本文の追跡で取りこぼされる典型例。 |
| B-2 | `prose/01-chapter.txt`〜`03-chapter.txt` の通奏低音として **西瓜の種** が反復（金花が噛む、客がつまむ、卓に散らばる） | どの素材ファイルにも「西瓜」「種」の語は **一度も出てこない** | 本文だけに存在する反復モチーフ。素材が描き落としているケース。 |
| B-3 | `prose/02-chapter.txt` で金花が外国人の顔を見て「画舫に乗つてゐた人」「孔子様の廟へ写真機を向けてゐた人」「利渉橋の側で人力車夫を打つてゐた人」と過去の目撃の記憶を辿る描写 | `sources/scene-notes/encounter-scene.md` には「画舫や孔子廟での目撃の記憶を辿る形で間接化する」という方針はあるが、**利渉橋・人力車夫・籐の杖** といった具体は素材になく本文で初出 | 場面ノートの抽象的な指示に対して本文が新規に細部を発明している例。 |

### C. v1 ↔ v2 の対立で本文がどちらかに従う（conflict resolution）

| ID | v1 | v2 | 本文 | 説明 |
|----|------|------|------|------|
| C-1 | `01-outline.md` は **四幕構成** | `02-revision.md` は **五幕構成**（夢の場面を独立幕に） | 原作は **三節構成**、本フィクスチャは四章に分割。いずれの素材とも一致しない | 構成数が素材の双方と食い違う。本文側で独自の章立てを採用した形跡。 |
| C-2 | `01-outline.md` のテーマ＝**信仰の救済** | `02-revision.md` のテーマ＝**皮肉の構造** | 本文は両方の要素を含むが、第三章の祈祷場面の比重が大きく、構造的には v1 寄り | 改稿で皮肉に振ろうとしたが、本文では信仰描写の分量が勝っている。テーマ比重の v1 ↔ v2 対立で本文は v1 を採った。 |
| C-3 | `01-outline.md` は山茶の姉の挿話を **入れる** | `02-revision.md` は山茶の姉の挿話を **削除する** | 本文 `prose/01-chapter.txt` には山茶の姉の挿話が **入っている**（「私の姉さんもあなたのやうに……御客はそれは可哀さうよ。おかげで目までつぶれたつて云ふわ」） | 改稿の削除指示が本文に反映されず、v1 が維持されている。 |

### D. キャラクターシートと本文の矛盾／欠落（character-sheet drift）

| ID | キャラシート | 本文 | 説明 |
|----|------|------|------|
| D-1 | `sources/references/characters.md` で外国人の年齢を **約三十歳** | `prose/02-chapter.txt` で「客の年頃は **三十五六**」 | キャラシートと本文の年齢が一致しない。 |
| D-2 | `sources/references/characters.md` で旅行家は **二十代後半か三十代前半** で「文人風、葉巻を好む」と設定 | `prose/04-chapter.txt` で旅行家は葉巻を吸う描写はある（一致）が、年齢に関する明記は本文に **無い** | 年齢属性が本文に入らないケース（プロパティ未消化）。 |
| D-3 | `sources/references/characters.md` で外国人の正体を「George Murry、英字新聞通信員、上海路透電報局の知人。後に悪性梅毒で発狂する」と設定 | `prose/04-chapter.txt` の旅行家の独白がほぼ完全にこの設定を反映 | これは **正常一致** の対照例。 |

### 検出が成功している状態とは

- A-1〜A-3 を **plot-only（under-coverage）** として列挙できる。
- B-1〜B-3 を **prose-only（drift / out-of-source）** として列挙できる。
- C-1〜C-3 を **v1↔v2 conflict** として、prose がどちらに沿ったかを判定できる。
- D-1〜D-2 を **character contradiction / omission** として、シートと本文の属性差分を出せる。
- D-3 のような **正常一致** を誤検出しない（false positive を避ける）。

これらが indexion story の最低限のテスト水準。

## 注意

- 本フィクスチャ内のファイルのみが本タスクの対象。リポジトリ内の他のファイルは変更しない。
- `sources/` のメモ類は架空の創作物であり、研究文献として引用してはならない。
- 「南京の基督」本文は青空文庫の編集を経たパブリックドメインテキストであり、出典明記の上で利用している。
