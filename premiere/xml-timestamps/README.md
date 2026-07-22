# Premiere XML timestamps

Premiere Proから書き出したFinal Cut Pro 7 XML（`xmeml`）にある素材の開始位置を、最上位の書き出しシーケンス上の時刻へ変換するNode.js CLIです。

次のケースを扱います。

- ネストされたシーケンス
- 一つのシーケンスが複数箇所で使われる編集
- Time Remapキーフレームによる固定速度・可変速度・逆再生
- トランジションに接して`start` / `end`が`-1`になったクリップ
- 末尾だけ欠損したXMLの検査・ベストエフォート復旧

## Setup

```sh
cd premiere/xml-timestamps
npm install
```

## XMLを検査する

```sh
node bin/premiere-xml-timestamps.mjs audit ~/Downloads/project.xml
```

末尾が欠損したXMLを検査する場合だけ、`--allow-truncated`を付けます。

```sh
node bin/premiere-xml-timestamps.mjs audit ~/Downloads/project.xml --allow-truncated
```

## 画像素材の時刻を抽出する

全シーケンス・全ビデオトラックから、最上位シーケンスへ到達できる画像を抽出します。

```sh
node bin/premiere-xml-timestamps.mjs extract ~/Downloads/project.xml \
  --all-tracks \
  --extensions jpg,jpeg,png \
  --format table
```

Vimeoコメントへ渡しやすい形式も出力できます。

```sh
node bin/premiere-xml-timestamps.mjs extract ~/Downloads/project.xml \
  --all-tracks \
  --extensions jpg,jpeg,png \
  --format comments \
  --comment 画像 \
  --dedupe \
  --output ~/Downloads/timestamps.txt
```

素材トラックが分かっている場合は、背景やロゴなどを避けるため対象を限定できます。

```sh
node bin/premiere-xml-timestamps.mjs extract ~/Downloads/project.xml \
  --track sequence-2:8 \
  --extensions jpg,jpeg,png \
  --format json
```

`inspect`でシーケンスID、トラック番号、クリップ例を確認できます。

```sh
node bin/premiere-xml-timestamps.mjs inspect ~/Downloads/project.xml
```

## 注意点

- XMLと最終MP4が同じ編集版か、両方の尺を照合してください。別バージョンなら正確に変換できません。
- `--all-tracks`は背景・ロゴなども含みます。素材専用トラックがある案件では`--track`の方が確実です。
- `--allow-truncated`は検査用です。本番ではPremiereから完全なXMLを再書き出してください。
- コメント形式は最終時刻を秒単位に丸めます。同じ秒に複数素材がある場合、素材名付きのtableまたはJSONで区別できます。
- `--dedupe`は、時刻とコメントが同一の行を初出順のまま1行へまとめます。

## Test

```sh
npm test
```
