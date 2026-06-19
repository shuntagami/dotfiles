---
name: youtube-playlist-uploader
description: ローカルフォルダや指定リスト内の動画を YouTube に限定公開でまとめてアップロードし、プレイリストに順番通り整理するときに使う。YouTube Studio のアップロード、ドラフト解除、限定公開設定、プレイリスト追加、並び順検証まで扱う。
---

# YouTube プレイリストアップロード

大量のローカル動画をユーザーの YouTube アカウントへアップロードし、プレイリストとして整理するための手順。

## 基本ルール

- YouTube Studio へのログインが必要なら、ユーザーにログインしてもらってから既存ブラウザセッションで続行する。
- 公開設定の既定は `限定公開` にする。ユーザーが明示しない限り `公開` にはしない。
- 並び順を崩さない。フォルダ指定の場合は、ユーザーが別の順序を指定しない限りファイル名の辞書順で処理する。
- 1 バッチは 12-15 本程度にする。YouTube 側の日次上限に当たりやすいため、Studio に `1 日のアップロード数の上限に達しました` が出たら、到達地点を明記して停止する。
- 各バッチで `index -> videoId -> filename` の対応表を維持する。
- バッチごとにプレイリストの本数と末尾の順番を検証する。
- Cookie、認証ヘッダー、セッショントークンをファイルに保存しない。

## 手順

1. ファイル一覧を作る。
   - `find <folder> -maxdepth 1 -type f` を使い、一般的な動画拡張子（`mp4`, `mov`, `m4v`, `webm`）に絞る。
   - 一覧をソートして連番を付ける。
   - ファイル名に空白や日本語が含まれる場合も、ブラウザのファイルアップロードには絶対パスを渡す。

2. プレイリストを作成または開く。
   - ユーザー指定がなければ、元フォルダ名をプレイリスト名にする。
   - プレイリストの公開設定は限定公開にする。
   - 次の 2 つの URL を保持する。
     - Studio: `https://studio.youtube.com/playlist/<PLAYLIST_ID>/videos`
     - 公開側: `https://www.youtube.com/playlist?list=<PLAYLIST_ID>`

3. YouTube Studio でバッチをアップロードする。
   - `https://studio.youtube.com/playlist/<PLAYLIST_ID>/videos` を開く。
   - `作成` -> `動画をアップロード` -> `ファイルを選択` を押す。
   - 予定順の絶対パスを 12-15 本選択する。
   - `アップロード完了` が出るまで待つ。
   - 日次上限が出た場合は、何本目まで完了したかを報告して停止する。

4. 動画 ID を取得する。
   - 最も確実なのは、Studio の `/youtubei/v1/upload/createvideo?alt=json` レスポンスに含まれる `videoId`。
   - レスポンス本文は `videoId` 抽出に必要な範囲だけ確認する。
   - ID はアップロード順にファイル名と対応させる。
   - 一時的にレスポンス JSON を保存した場合は、抽出後に削除する。

5. 各動画のドラフトを解除し、限定公開にする。
   - 各 `videoId` で `https://studio.youtube.com/video/<VIDEO_ID>/edit` を開く。
   - `ドラフトを編集` を押す。
   - 視聴者設定で `いいえ、子ども向けではありません` を選ぶ。
   - `次へ` を 3 回押す。
   - `限定公開` を選ぶ。
   - `保存` を押す。
   - `この動画はドラフト状態です` が消えていることを確認する。

6. プレイリストに順番通り追加する。
   - `www.youtube.com` 側の公開プレイリスト URL を開く。
   - 現在のブラウザセッションから `/youtubei/v1/browse/edit_playlist?prettyPrint=false` を呼ぶ。
   - `SAPISIDHASH` 認証ヘッダーは現在の Cookie から実行時に生成する。固定値を書き込まない。
   - Body の形:

```js
{
  context: window.ytcfg.get("INNERTUBE_CONTEXT"),
  playlistId: "<PLAYLIST_ID>",
  actions: ids.map((id) => ({ action: "ACTION_ADD_VIDEO", addedVideoId: id })),
  params: "CAE="
}
```

7. プレイリストを検証する。
   - `https://www.youtube.com/playlist?list=<PLAYLIST_ID>` を再読み込みする。
   - `ytd-playlist-video-renderer` から行を抽出する。
   - 次を確認する。
     - 合計本数がアップロード済み本数と一致する。
     - 既存の先頭項目が崩れていない。
     - 追加した末尾の ID とタイトルがバッチ順と一致する。
   - 全ファイルが終わるまで次のバッチを続ける。

## 便利なブラウザ内スニペット

`www.youtube.com` のページコンテキスト内で、現在の Cookie から YouTube 認証ヘッダーを生成する。

```js
async function sha1Hex(s) {
  const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function authHeader(origin) {
  const cookies = {};
  document.cookie.split("; ").filter(Boolean).forEach((c) => {
    const i = c.indexOf("=");
    cookies[c.slice(0, i)] = decodeURIComponent(c.slice(i + 1));
  });
  const sapisid = cookies.SAPISID || cookies.__Secure_3PAPISID || cookies.__Secure_1PAPISID || cookies.APISID;
  if (!sapisid) throw new Error("SAPISID cookie not available");
  const ts = Math.floor(Date.now() / 1000);
  return `SAPISIDHASH ${ts}_${await sha1Hex(`${ts} ${sapisid} ${origin}`)}`;
}
```

動画をプレイリストに追加する。

```js
async function addVideosToPlaylist(playlistId, ids) {
  const authUser = window.ytcfg.get("SESSION_INDEX") ?? 0;
  const headers = {
    "content-type": "application/json",
    "x-origin": "https://www.youtube.com",
    "x-youtube-client-name": "1",
    "x-youtube-client-version": window.ytcfg.get("INNERTUBE_CLIENT_VERSION"),
    "x-goog-authuser": String(authUser),
    "x-goog-visitor-id": window.ytcfg.get("VISITOR_DATA"),
    "x-youtube-bootstrap-logged-in": "true",
    authorization: await authHeader("https://www.youtube.com"),
  };
  const body = {
    context: window.ytcfg.get("INNERTUBE_CONTEXT"),
    playlistId,
    actions: ids.map((id) => ({ action: "ACTION_ADD_VIDEO", addedVideoId: id })),
    params: "CAE=",
  };
  const res = await fetch("/youtubei/v1/browse/edit_playlist?prettyPrint=false", {
    method: "POST",
    credentials: "include",
    headers,
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`edit_playlist failed: ${res.status} ${await res.text()}`);
  return res.json();
}
```

プレイリストの並び順を読み取る。

```js
function readPlaylistRows() {
  return [...document.querySelectorAll("ytd-playlist-video-renderer")].map((row, i) => {
    const a = row.querySelector('a#video-title, a[href*="watch?v="]');
    const id = a ? new URL(a.href, location.href).searchParams.get("v") : null;
    const title = (row.querySelector("#video-title")?.textContent || row.textContent || "")
      .replace(/\s+/g, " ")
      .trim();
    return { pos: i + 1, id, title };
  });
}
```

## 完了報告

ユーザーには次を簡潔に報告する。

- プレイリスト URL
- アップロードした合計本数
- 最終公開設定が `限定公開` であること
- すべてドラフト解除済みか
- プレイリストの順番を検証済みか
