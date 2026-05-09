---
schedule: every 10m
enabled: true
preset:
- screenpipe-cloud
source_slug: focus-assistant
installed_version: 1
source_hash: 4d2149f31a49426d
featured: false
description: 集中からそれていそうなときだけアプリ内通知を送る
icon: 🎯
title: 集中チェック
history: false
---

直近10分の画面アクティビティを確認し、ユーザーが集中からそれていそうか判断してください。

# ルール
- まず `/activity-summary` を使う。
- `/activity-summary` だけで判断しきれない場合のみ、追加で `/search` を最大1回だけ使う。
- API呼び出しは合計2回まで。
- 質問はしない。
- 通知を送らない場合は、分析や説明を一切出力しない。
- 証拠が弱い、曖昧、または正当な仕事に見える場合は何もしない。
- 誤検知で集中を邪魔しないことを優先する。

# 休憩中の扱い

`~/.screenpipe/work-state/breaks.jsonl` で休憩中と分かる場合は、画面内容に関係なく通知しない。

休憩中は、YouTubeやSNSを見ていても脱線とは扱わない。

# 脱線シグナル

直近10分で、通常は以下のうち2つ以上が揃った場合に脱線候補とする。

- 4個以上の異なるアプリを短時間に行き来している
- 気が散りやすいアプリやサイトが直近の時間を占めている
- 明確な仕事用アプリが優勢ではない
- 作業が細切れで、明確な進捗や作業対象が見えない

# YouTubeの扱い

YouTubeは強い脱線シグナルとして扱う。

以下が見えた場合は特に注意する。

- YouTube
- youtube.com
- youtu.be
- Shorts
- ホーム画面、関連動画、おすすめ動画
- エンタメ、ニュース、音楽、雑談、趣味動画など仕事と関係が薄い動画

YouTubeが直近10分のうち3分以上を占め、かつ明確な仕事目的が見えない場合は、それだけで強い脱線候補とする。

# 集中からそれたと見なしやすい文脈

- YouTube、YouTube Shorts
- X/Twitter
- TikTok
- Instagram
- ニュースサイト
- グラビア、AVなど性欲を刺激するコンテンツ
- 仕事と関係のないブラウジング
- 関係のないチャットやSNS

# ステップ0: 休憩状態の確認

休憩中なら何も出力せずに終了する。

```bun
import * as fs from "fs";

const breaksFile = `${process.env.HOME}/.screenpipe/work-state/breaks.jsonl`;

function isBreakActive() {
  if (!fs.existsSync(breaksFile)) return false;

  const events = fs
    .readFileSync(breaksFile, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);

  let active = false;
  for (const event of events) {
    if (event.type === "break_start") active = true;
    if (event.type === "break_end") active = false;
  }
  return active;
}

if (isBreakActive()) {
  process.exit(0);
}
```

# ステップ1: アクティビティ概要

直近10分のアプリ、ウィンドウ、URLを確認する。

```bun
import * as fs from "fs";

const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
const headers = { Authorization: `Bearer ${KEY}` };

const r = await fetch(
  "http://localhost:3030/activity-summary?start_time=10m%20ago&end_time=now",
  { headers }
);

const data = r.ok ? await r.json() : null;
fs.writeFileSync("/tmp/fa_activity.json", JSON.stringify(data ?? {}, null, 2));

const apps = (data?.apps ?? []).slice(0, 8).map((a) => ({
  name: a.name,
  minutes: a.active_minutes,
}));

const windows = (data?.windows ?? []).slice(0, 12).map((w) => ({
  app: w.app_name ?? w.app,
  title: w.window_name ?? w.name ?? w.title,
  url: w.browser_url,
  minutes: w.active_minutes,
  text: String(w.key_text ?? w.text ?? "").slice(0, 160),
}));

console.log(JSON.stringify({ apps, windows }, null, 2));
```

この結果から、通知するか、確認のためにステップ2へ進むか、何もしないかを判断する。

# ステップ2: 追加確認検索

YouTubeやSNSなどの脱線が疑われるが、アクティビティ概要だけでは確信できない場合のみ実行する。

```bun
const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;

const r = await fetch(
  "http://localhost:3030/search?content_type=accessibility&limit=10&start_time=10m%20ago&end_time=now",
  { headers: { Authorization: `Bearer ${KEY}` } }
);

const data = r.ok ? await r.json() : { data: [] };

const recent = (data.data ?? []).slice(0, 10).map((d) => ({
  app: d.content?.app_name,
  window: d.content?.window_name,
  url: d.content?.browser_url,
  text: String(d.content?.text ?? "").slice(0, 160),
}));

console.log("直近の文脈:", JSON.stringify(recent, null, 2));
```

# ステップ3: 通知を送る

脱線の確信度が高い場合のみ通知する。

```bun
const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;

const r = await fetch("http://localhost:11435/notify", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${KEY}`,
  },
  body: JSON.stringify({
    title: "集中チェック",
    body: "直近10分、YouTubeなどに流れているかもしれません。今のタブを閉じて、次の具体的な作業に戻りましょう。",
    timeout: 5000,
  }),
});

if (!r.ok) {
  console.error(`通知に失敗しました: ${r.status}`);
  process.exit(1);
}

console.log("集中通知を送信しました。");
```

通知リクエストに成功していない場合は、通知したと主張しない。

通知した場合のみ、正確に以下を出力する。

`集中通知を送信しました。`

通知しない場合は何も出力しない。
