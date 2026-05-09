---
schedule: every 1h
enabled: true
preset:
- screenpipe-cloud
connections:
- slack
title: フォーカスワーク深掘り
description: 直近1時間の作業と進捗をSlackに投稿する
icon: 🕐
history: false
---

直近1時間の作業内容を確認し、Slackに短い作業レポートを投稿してください。

# 目的

このPipeの主目的は、直近1時間で「何に時間を使い、何が進んだか」を可視化することです。

副目的として、集中からそれた可能性がある時間を軽く検知し、次の1時間で戻るべき作業を明確にします。

このレポートは、ユーザーを監視して責めるためのものではありません。作業の流れを外から見える形にし、次の行動を決めやすくするための作業メモです。

# マルチ端末での前提

ScreenpipeのローカルAPIは、このPipeが動いている端末の記録だけを見ます。

デスクトップとノートPCを行き来して作業する場合は、それぞれの端末でScreenpipeとこのPipeを動かしてください。

Slack投稿には必ず端末名を入れ、どの端末上の1時間レポートなのか分かるようにしてください。

`~/.screenpipe/work-state/breaks.jsonl` に休憩ログがある場合は、直近1時間に含まれる休憩時間を作業時間から除外してください。

# 基本方針

- まず `/activity-summary` を使う。
- `/activity-summary` だけで作業内容が曖昧な場合のみ、追加で `/search` を最大1回だけ使う。
- API呼び出しは、Screenpipe API 2回 + Slack投稿 1回まで。
- アプリ名だけで判断しない。ウィンドウ名、URL、表示テキスト、時間のまとまりから判断する。
- 推測しすぎない。根拠が弱い場合は「判定弱め」と書く。
- Slackには秘密情報、個人情報、DM本文の詳細、APIキー、パスワード、認証情報を出さない。
- 投稿は短く、10行以内に収める。
- アプリ内通知やテスト通知を送らない。
- Slack投稿文を作成しただけでは完了ではない。必ずSlack webhookへPOSTし、成功を確認してから終了する。

# レポートの考え方

まず見るべきものは「集中からそれたか」ではなく、次の3つです。

1. 何に時間を使ったか
2. 何が進んだか
3. 次に戻るべき作業は何か

直近1時間を、細かい操作ログではなく「作業単位」でまとめてください。

重視する観点:

- 主な作業対象は何だったか
- 実際に進んだこと、決まったこと、作ったものは何か
- 集中して進んでいた時間はあったか
- コミュニケーションや調査に偏っていたか
- 集中からそれた可能性がある時間はあったか
- 次に戻るべき具体的な作業は何か

# 集中メモの考え方

集中メモでは、以下を簡潔に書いてください。

- 集中して進んでいそうなら、その根拠を書く
- 集中からそれた可能性が目立つなら、短く指摘する
- 判断できない場合は「判定弱め」と書く

集中からそれた可能性は、主目的ではなく補足情報として扱ってください。脱線の有無を無理に探さないでください。

# 集中からそれたと見なす補助基準

集中からそれているとは、単に特定のアプリを開いたことではありません。

以下のような状態を、集中からそれた可能性として扱ってください。

- 仕事や学習の対象が見えず、画面遷移だけが細かく続いている
- 娯楽、SNS、ニュース、動画、性的コンテンツなどが時間を占めている
- YouTube、YouTube Shorts、関連動画、おすすめ動画に流れている
- 直近の作業対象と関係が薄いブラウジングが続いている
- 明確な成果物、調査対象、会話目的が読み取れない

YouTubeは強い脱線シグナルとして扱ってください。

ただし、仕事や学習に関係する動画、技術解説、講座、調査目的の閲覧に見える場合は、脱線扱いしないでください。

# Slack投稿フォーマット

Slackには次の形式で投稿してください。

```text
*フォーカスワーク深掘り: 直近1時間*
• 端末: ...
• 休憩: ...
• 時間の使い道: ...
• 進んだこと: ...
• 作業対象: ...
• 集中メモ: ...
• 次にやること: ...
```

書き方:

- 各行は短く具体的にする。
- 「端末」は、ステップ1で取得した端末名を書く。
- 「休憩」は、直近1時間に含まれる休憩時間を書く。休憩がなければ「なし」と書く。
- 「時間の使い道」は、主要な作業を時間の大きい順にまとめる。
- 「進んだこと」は、成果・決定・完了・作成・設定変更などを書く。
- 「集中メモ」は、脱線がなければ「目立った脱線なし」または集中していた根拠を書く。
- 「次にやること」は、できるだけ具体的な行動として書く。
- 詳細なスクリーン内容や会話本文をそのまま転載しない。

# ステップ1: アクティビティ概要

直近1時間のアプリ、ウィンドウ、URL、代表テキストを確認する。

```bun
import * as fs from "fs";
import { hostname } from "os";

const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
const headers = { Authorization: `Bearer ${KEY}` };
const device = process.env.SCREENPIPE_DEVICE_NAME ?? hostname();
const now = new Date();
const rangeStart = new Date(now.getTime() - 60 * 60 * 1000);

const breaksFile = `${process.env.HOME}/.screenpipe/work-state/breaks.jsonl`;

function readBreakEvents() {
  if (!fs.existsSync(breaksFile)) return [];
  return fs
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
}

function summarizeBreaks(start, end) {
  const events = readBreakEvents();
  let currentStart = null;
  let totalMs = 0;
  const intervals = [];

  for (const event of events) {
    if (event.type === "break_start") {
      currentStart = new Date(event.at);
      continue;
    }

    if (event.type === "break_end" && currentStart) {
      const breakEnd = new Date(event.at);
      const overlapStart = new Date(Math.max(currentStart.getTime(), start.getTime()));
      const overlapEnd = new Date(Math.min(breakEnd.getTime(), end.getTime()));
      if (overlapEnd > overlapStart) {
        totalMs += overlapEnd.getTime() - overlapStart.getTime();
        intervals.push({ start: overlapStart.toISOString(), end: overlapEnd.toISOString() });
      }
      currentStart = null;
    }
  }

  if (currentStart) {
    const overlapStart = new Date(Math.max(currentStart.getTime(), start.getTime()));
    const overlapEnd = end;
    if (overlapEnd > overlapStart) {
      totalMs += overlapEnd.getTime() - overlapStart.getTime();
      intervals.push({ start: overlapStart.toISOString(), end: "ongoing" });
    }
  }

  return {
    minutes: Math.round(totalMs / 60000),
    active: Boolean(currentStart),
    intervals,
  };
}

const breaks = summarizeBreaks(rangeStart, now);

const r = await fetch(
  "http://localhost:3030/activity-summary?start_time=1h%20ago&end_time=now",
  { headers }
);

const data = r.ok ? await r.json() : null;
fs.writeFileSync("/tmp/hourly_work_activity.json", JSON.stringify(data ?? {}, null, 2));

const apps = (data?.apps ?? []).slice(0, 12).map((a) => ({
  name: a.name,
  minutes: a.active_minutes,
}));

const windows = (data?.windows ?? []).slice(0, 24).map((w) => ({
  app: w.app_name ?? w.app,
  title: w.window_name ?? w.name ?? w.title,
  url: w.browser_url,
  minutes: w.active_minutes,
  text: String(w.key_text ?? w.text ?? "").slice(0, 180),
}));

console.log(JSON.stringify({ device, breaks, apps, windows }, null, 2));
```

この結果からSlack投稿の内容を組み立てる。主な作業内容が不明な場合のみステップ2へ進む。

# ステップ2: 追加確認検索

アクティビティ概要だけでは、時間の使い道・進んだこと・集中メモを判断しきれない場合のみ実行する。

```bun
const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;

const r = await fetch(
  "http://localhost:3030/search?content_type=accessibility&limit=12&start_time=1h%20ago&end_time=now",
  { headers: { Authorization: `Bearer ${KEY}` } }
);

const data = r.ok ? await r.json() : { data: [] };

const recent = (data.data ?? []).slice(0, 12).map((d) => ({
  app: d.content?.app_name,
  window: d.content?.window_name,
  url: d.content?.browser_url,
  text: String(d.content?.text ?? "").slice(0, 180),
}));

console.log(JSON.stringify(recent, null, 2));
```

# ステップ3: Slackに投稿する

Slack投稿文を作成し、Screenpipeの接続設定に保存されたSlack webhookへ送信する。

以下のコードを実行する前に、`text` を必ず実際のSlack投稿文に置き換える。プレースホルダーのまま送信してはいけない。

重要:

- `text` を作成しただけで止まらない。
- `cat` でJSONを作るだけで止まらない。
- `http://localhost:11435/notify` へテスト通知を送らない。
- Slack webhookへPOSTするところまで必ず実行する。
- Slackのレスポンスが成功でない場合は、投稿したと主張しない。

```bun
const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
const headers = { Authorization: `Bearer ${KEY}` };

const connRes = await fetch("http://localhost:3030/connections/slack", { headers });
const conn = connRes.ok ? await connRes.json() : null;
const webhookUrl = conn?.credentials?.webhook_url;

if (!webhookUrl) {
  console.error("Slackのwebhook_urlが設定されていません");
  process.exit(1);
}

const text = `未置換_送信禁止`;

if (text.includes("未置換_送信禁止")) {
  console.error("Slackに投稿する前にtextを最終レポート文へ置き換えてください");
  process.exit(1);
}

const postRes = await fetch(webhookUrl, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ text }),
});

if (!postRes.ok) {
  console.error(`Slack投稿に失敗しました: ${postRes.status}`);
  process.exit(1);
}

const postText = await postRes.text();
if (postText.trim() !== "ok") {
  console.error(`Slack投稿の応答が想定外です: ${postText}`);
  process.exit(1);
}

console.log("Slackに1時間レポートを送信しました。");
```

`text` には、ステップ1と必要ならステップ2の結果を踏まえて作った最終投稿文を入れること。

Slack投稿に成功した場合のみ、正確に以下を出力する。

`Slackに1時間レポートを送信しました。`

投稿に失敗した場合は、投稿したと主張しない。
