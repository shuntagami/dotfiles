---
schedule: '55 23 * * *'
enabled: true
preset:
- gemini-3.1-pro
connections:
- slack
title: 日次ワークレポート
description: 今日の作業時間、休憩、成果、明日の継続作業をSlackに投稿する
icon: 📅
history: false
---

今日の画面記録、音声記録、休憩ログを確認し、Slackに日次ワークレポートを投稿してください。

# 最重要

このPipeは23:55の日次レポート専用です。

Screenpipe Runnerから `Time range` が渡されても、その範囲は使わないでください。必ず、この端末のローカル時刻における今日の0:00から現在までを対象にしてください。

23:50から23:59以外の時刻に実行された場合は、Slackに投稿せず終了してください。追加直後や手動確認などで予定外実行されることがあるためです。

# 目的

このPipeの目的は、1日の終わりに「何時間働いたか」「何に時間を使ったか」「何が進んだか」「明日何を続けるか」を短く可視化することです。

このレポートは、ユーザーを責めるためのものではありません。翌日の再開を楽にするための作業ログです。

# 前提

- ScreenpipeのローカルAPIは、このPipeが動いている端末の記録だけを見ます。
- 勤務中かどうかは `~/.screenpipe/work-state/work.jsonl` に記録されています。
- 休憩は `~/.screenpipe/work-state/breaks.jsonl` に記録されています。
- iPhoneスクリーンタイムは別のSlack通知で扱います。このPipeでは推測しません。
- Slackには秘密情報、個人情報、DM本文の詳細、APIキー、パスワード、認証情報を出さないでください。

# 基本方針

- 今日の0:00から現在までを対象にする。
- まず `/activity-summary` を使う。
- `/activity-summary` だけで成果や未完了作業が曖昧な場合のみ、追加で `/search` を最大1回だけ使う。
- API呼び出しは、Screenpipe API 2回 + Slack投稿 1回まで。
- 投稿は12行以内に収める。
- アプリ内通知やテスト通知を送らない。
- Slack投稿文を作成しただけでは完了ではない。必ずSlack webhookへPOSTし、成功を確認してから終了する。

# ステップ0: 実行時刻の確認

最初に必ず実行する。23:50から23:59以外なら、Slackに投稿せず終了する。

```bun
const now = new Date();
const shouldRun = now.getHours() === 23 && now.getMinutes() >= 50;

if (!shouldRun) {
  console.log("日次ワークレポートは23:55実行のためスキップしました。");
  process.exit(0);
}
```

# 作業時間の考え方

作業時間は厳密な勤怠ではなく、日次レビュー用の概算です。

以下を分けて書いてください。

- `work-start` / `work-end` で記録された勤務枠
- Screenpipe上で確認できる活動時間
- 休憩時間
- 休憩を除いた実作業時間の概算

作業ログがある場合は、Screenpipeの活動時間ではなく、勤務枠から休憩を除いた時間を「実作業時間」として優先してください。

作業ログがない場合だけ、Screenpipe上の活動時間から休憩を除いた概算を使ってください。

# レポートの観点

今日を、細かい操作ログではなく「作業単位」でまとめてください。

重視する観点:

- 主な作業対象は何だったか
- 何に時間を使ったか
- 完了したこと、進んだこと、決まったことは何か
- 明日に残ったことは何か
- 休憩を除いた実作業時間はどれくらいか
- 集中から大きくそれた時間があったか

# Slack投稿フォーマット

Slackには次の形式で投稿してください。

```text
*日次ワークレポート: YYYY-MM-DD*
• 端末: ...
• 実作業時間: ... / 休憩: ...
• 主な時間の使い道: ...
• 進んだこと: ...
• 作業対象: ...
• 未完了・明日: ...
• 集中メモ: ...
```

書き方:

- 各行は短く具体的にする。
- 「実作業時間」は、活動時間から休憩時間を除いた概算を書く。
- 「主な時間の使い道」は、主要な作業を時間の大きい順にまとめる。
- 「進んだこと」は、成果・決定・完了・作成・設定変更などを書く。
- 「未完了・明日」は、明日再開する具体的な行動として書く。
- iPhoneスクリーンタイムは別通知として扱い、このレポートでは推測しない。

# ステップ1: 今日のアクティビティ概要

今日の0:00から現在までのアプリ、ウィンドウ、URL、代表テキスト、休憩時間を確認する。

```bun
import * as fs from "fs";
import { hostname } from "os";

const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
const headers = { Authorization: `Bearer ${KEY}` };
const device = process.env.SCREENPIPE_DEVICE_NAME ?? hostname();
const now = new Date();
const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
const date = [
  now.getFullYear(),
  String(now.getMonth() + 1).padStart(2, "0"),
  String(now.getDate()).padStart(2, "0"),
].join("-");

const workFile = `${process.env.HOME}/.screenpipe/work-state/work.jsonl`;
const breaksFile = `${process.env.HOME}/.screenpipe/work-state/breaks.jsonl`;

function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs
    .readFileSync(file, "utf8")
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

function readBreakEvents() {
  return readJsonl(breaksFile);
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

function intervals(events, startType, endType, start, end) {
  let currentStart = null;
  const result = [];

  for (const event of events) {
    if (event.type === startType) {
      currentStart = new Date(event.at);
      continue;
    }

    if (event.type === endType && currentStart) {
      const eventEnd = new Date(event.at);
      const overlapStart = new Date(Math.max(currentStart.getTime(), start.getTime()));
      const overlapEnd = new Date(Math.min(eventEnd.getTime(), end.getTime()));
      if (overlapEnd > overlapStart) {
        result.push({ start: overlapStart, end: overlapEnd });
      }
      currentStart = null;
    }
  }

  if (currentStart) {
    const overlapStart = new Date(Math.max(currentStart.getTime(), start.getTime()));
    const overlapEnd = end;
    if (overlapEnd > overlapStart) {
      result.push({ start: overlapStart, end: overlapEnd });
    }
  }

  return result;
}

function sumIntervals(list) {
  return list.reduce((sum, interval) => sum + Math.max(0, interval.end - interval.start), 0);
}

function overlapMs(left, right) {
  let total = 0;
  for (const a of left) {
    for (const b of right) {
      const start = Math.max(a.start.getTime(), b.start.getTime());
      const end = Math.min(a.end.getTime(), b.end.getTime());
      if (end > start) total += end - start;
    }
  }
  return total;
}

function summarizeWork(start, end) {
  const workEvents = readJsonl(workFile);
  const workIntervals = intervals(workEvents, "work_start", "work_end", start, end);
  const breakIntervals = intervals(readBreakEvents(), "break_start", "break_end", start, end);
  const grossMs = sumIntervals(workIntervals);
  const breakMs = overlapMs(workIntervals, breakIntervals);

  return {
    configured: workEvents.length > 0,
    gross_minutes: Math.round(grossMs / 60000),
    break_minutes: Math.round(breakMs / 60000),
    net_minutes: Math.round(Math.max(0, grossMs - breakMs) / 60000),
    intervals: workIntervals.map((interval) => ({
      start: interval.start.toISOString(),
      end: interval.end.toISOString(),
    })),
  };
}

const breaks = summarizeBreaks(dayStart, now);
const work = summarizeWork(dayStart, now);
const start = encodeURIComponent(dayStart.toISOString());
const end = encodeURIComponent(now.toISOString());

const r = await fetch(
  `http://localhost:3030/activity-summary?start_time=${start}&end_time=${end}`,
  { headers }
);

const data = r.ok ? await r.json() : null;
fs.writeFileSync("/tmp/daily_work_activity.json", JSON.stringify(data ?? {}, null, 2));

const apps = (data?.apps ?? []).slice(0, 16).map((a) => ({
  name: a.name,
  minutes: a.active_minutes ?? a.minutes,
}));

const windows = (data?.windows ?? []).slice(0, 32).map((w) => ({
  app: w.app_name ?? w.app,
  title: w.window_name ?? w.name ?? w.title,
  url: w.browser_url,
  minutes: w.active_minutes ?? w.minutes,
  text: String(w.key_text ?? w.text ?? "").slice(0, 180),
}));

console.log(JSON.stringify({ date, device, work, breaks, apps, windows }, null, 2));
```

この結果からSlack投稿の内容を組み立てる。成果や未完了作業が不明な場合のみステップ2へ進む。

# ステップ2: 追加確認検索

アクティビティ概要だけでは、進んだこと・未完了・明日の作業を判断しきれない場合のみ実行する。

```bun
const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
const now = new Date();
const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
const start = encodeURIComponent(dayStart.toISOString());
const end = encodeURIComponent(now.toISOString());

const r = await fetch(
  `http://localhost:3030/search?content_type=accessibility&limit=20&start_time=${start}&end_time=${end}`,
  { headers: { Authorization: `Bearer ${KEY}` } }
);

const data = r.ok ? await r.json() : { data: [] };

const recent = (data.data ?? []).slice(0, 20).map((d) => ({
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

console.log("Slackに日次ワークレポートを送信しました。");
```

`text` には、ステップ1と必要ならステップ2の結果を踏まえて作った最終投稿文を入れること。

Slack投稿に成功した場合のみ、正確に以下を出力する。

`Slackに日次ワークレポートを送信しました。`

投稿に失敗した場合は、投稿したと主張しない。
