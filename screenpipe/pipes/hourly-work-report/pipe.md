---
schedule: every 1h
enabled: true
preset:
  - gemini-3-8-flash
connections:
  - slack
title: 作業内容
description: 直近1時間の作業と進捗をSlackに投稿する
icon: 🕐
history: false
---

直近1時間の作業内容を確認し、Slackに短い作業レポートを投稿してください。

# 目的

このPipeの主目的は、直近1時間で「何に時間を使い、何が進んだか」を可視化することです。

副目的として、集中からそれた可能性がある時間を軽く検知し、次の1時間で戻るべき作業を明確にします。

このレポートは、ユーザーを監視して責めるためのものではありません。作業の流れを外から見える形にし、次の行動を決めやすくするための作業メモです。

重要なのは、開いていたアプリ名を雑に要約することではありません。画面上の文脈から、どのプロジェクト、どのファイル、どのPR、どのドキュメント、どの会話、どの設定を扱っていたのかをできるだけ復元してください。

# マルチ端末での前提

ScreenpipeのローカルAPIは、このPipeが動いている端末の記録だけを見ます。

デスクトップとノートPCを行き来して作業する場合は、それぞれの端末でScreenpipeとこのPipeを動かしてください。

Slack投稿には必ず端末名を入れ、どの端末上の1時間レポートなのか分かるようにしてください。

`~/.screenpipe/work-state/breaks.jsonl` に休憩ログがある場合は、直近1時間に含まれる休憩時間を作業時間から除外してください。

`~/.screenpipe/work-state/work.jsonl` に作業ログがあり、現在作業中ではないと分かる場合は、Slack投稿せず終了してください。PCが起動しているだけの時間を1時間レポートにしないためです。

# 基本方針

- まず `/activity-summary` を使う。
- その後、必ず `/search` を1回使って、画面テキスト、ウィンドウ名、URL、入力、音声文字起こしの断片を確認する。
- API呼び出しは、Screenpipe API 2回 + Slack投稿 1回まで。
- APIのHTTPエラーを空の活動記録として扱わない。失敗したステップで終了し、エラーを報告する。
- `data_status` が `ok` 以外なら、その状態を実行ログに残して投稿せず終了する。「記録が取れていない」と「作業していない」を混同しない。
- 時間配分には `total_active_minutes` とアプリ・ウィンドウの `minutes` を使う。フレーム数や検索件数から時間を計算しない。記録が短い場合は、その範囲だけを報告する。
- アプリ名だけで判断しない。ウィンドウ名、URL、表示テキスト、入力、会話断片、時間のまとまりから判断する。
- 「Cursorを開いていた」「Slackを見ていた」のようなアプリ利用報告で終わらせない。
- 推測しすぎない。根拠が弱い場合は「成果は読み取れず」「判定弱め」と書く。
- 根拠がない成果、完了、合意、修正、マージ、送信を作らない。
- Slackには秘密情報、個人情報、DM本文の詳細、APIキー、パスワード、認証情報を出さない。
- 投稿は短く、11行以内に収める。
- アプリ内通知やテスト通知を送らない。
- Slack投稿文を作成しただけでは完了ではない。必ずSlack webhookへPOSTし、成功を確認してから終了する。
- ただし、追加の実行指示でドライランを指定された場合は、ステップ3を `SCREENPIPE_HOURLY_DRY_RUN=1` で実行する。投稿文を `output/report.txt` に保存して検証し、Slackへ送らない。

# ステップ0: 勤務状態の確認

最初に必ず実行する。

`~/.screenpipe/work-state/work.jsonl` に作業ログがあり、現在作業中ではない場合は、Slackに投稿せず終了する。

作業ログがまだ存在しない場合は、まだ `work-start` していない状態として勤務外扱いにする。

```bun
import * as fs from "fs";

const workFile = `${process.env.HOME}/.screenpipe/work-state/work.jsonl`;

function currentWorkSession() {
  if (!fs.existsSync(workFile)) return { configured: false, active: false, started_at: null };

  const events = fs
    .readFileSync(workFile, "utf8")
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

  if (events.length === 0) return { configured: false, active: false, started_at: null };

  let current = null;
  for (const event of events) {
    if (event.type === "work_start") current = event;
    if (event.type === "work_end") current = null;
  }

  return {
    configured: true,
    active: Boolean(current),
    started_at: current?.at ?? null,
  };
}

const work = currentWorkSession();
if (!work.active) {
  console.log("勤務外のため1時間レポートをスキップしました。");
  process.exit(0);
}

console.log(JSON.stringify({ work }, null, 2));
```

# レポートの考え方

まず見るべきものは「集中からそれたか」ではなく、次の3つです。

1. 何に時間を使ったか
2. 何が進んだか
3. 次に戻るべき作業は何か

直近1時間を、細かい操作ログではなく「作業単位」でまとめてください。

内部では、まず直近1時間を2から5個の作業ブロックに分けてください。Slackには内部分析をそのまま出さず、要約して投稿してください。

重視する観点:

- 主な作業対象は何だったか
- 実際に進んだこと、決まったこと、作ったものは何か
- どのファイル、ページ、PR、Issue、ドキュメント、顧客、講座、設定を扱っていたか
- 集中して進んでいた時間はあったか
- コミュニケーションや調査に偏っていたか
- 集中からそれた可能性がある時間はあったか
- 次に戻るべき具体的な作業は何か

成果の判定基準:

- `進んだこと` は、画面上のテキスト、ウィンドウ名、URL、入力、音声文字起こしなどから根拠があるものだけを書く。
- 「原因特定」「完了」「合意形成」「レビュー完了」「マージ」などは、根拠が見える場合だけ使う。
- 根拠が弱い場合は、成果を盛らずに「画面上は...の確認・編集が中心。明確な完了は読み取れず」と書く。
- 単に複数アプリを開いていたことを「連携」「調整」「品質管理」などに言い換えない。

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
*作業内容: 直近1時間*
• 端末: ...
• 休憩: ...
• 作業対象: ...
• 時間の使い道: ...
• 進んだこと: ...
• 根拠: ...
• 集中メモ: ...
• 次にやること: ...
```

書き方:

- 各行は短く具体的にする。
- 「端末」は、ステップ1で取得した端末名を書く。
- 「休憩」は、直近1時間に含まれる休憩時間を書く。休憩がなければ「なし」と書く。
- 「作業対象」は、プロジェクト名、リポジトリ名、ドキュメント名、PR名、会話テーマなど、画面から読み取れる具体名を書く。
- 「時間の使い道」は、主要な作業を時間の大きい順にまとめる。可能なら `約25分: ... / 約15分: ...` のように書く。
- 「進んだこと」は、成果・決定・完了・作成・設定変更などを書く。
- 「根拠」は、判断に使った画面上の短い手がかりを書く。例: `window title: ... / URL: ... / 表示語: ...`。秘密情報や会話本文は出さない。
- 「集中メモ」は、脱線がなければ「目立った脱線なし」または集中していた根拠を書く。
- 「次にやること」は、直近の文脈から自然に戻るべき具体的な行動を書く。分からない場合は「直近で開いていた作業対象に戻る」と書く。
- 詳細なスクリーン内容や会話本文をそのまま転載しない。

# ステップ1: アクティビティ概要

直近1時間のアプリ、ウィンドウ、URL、代表テキスト、音声文字起こしを確認する。

```bun
import * as fs from "fs";
import { hostname } from "os";

const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
if (!KEY) throw new Error("SCREENPIPE_LOCAL_API_KEY が設定されていません");
const API = process.env.SCREENPIPE_LOCAL_API_URL || "http://localhost:3030";
const headers = { Authorization: `Bearer ${KEY}`, "X-Screenpipe-Client": "api" };
const device = process.env.SCREENPIPE_DEVICE_NAME ?? hostname();
const now = new Date();
const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

const workFile = `${process.env.HOME}/.screenpipe/work-state/work.jsonl`;
const breaksFile = `${process.env.HOME}/.screenpipe/work-state/breaks.jsonl`;

function currentWorkSession() {
  if (!fs.existsSync(workFile)) return { configured: false, active: false, started_at: null };

  const events = fs
    .readFileSync(workFile, "utf8")
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

  if (events.length === 0) return { configured: false, active: false, started_at: null };

  let current = null;
  for (const event of events) {
    if (event.type === "work_start") current = event;
    if (event.type === "work_end") current = null;
  }

  return {
    configured: true,
    active: Boolean(current),
    started_at: current?.at ?? null,
  };
}

const work = currentWorkSession();
if (!work.active) {
  process.exit(0);
}

const workStart = work.started_at ? new Date(work.started_at) : null;
const rangeStart = workStart && workStart > oneHourAgo ? workStart : oneHourAgo;

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

const start = encodeURIComponent(rangeStart.toISOString());
const end = encodeURIComponent(now.toISOString());

const r = await fetch(
  `${API}/activity-summary?start_time=${start}&end_time=${end}&include_memories=false&include_snippets=false`,
  { headers, signal: AbortSignal.timeout(30000) }
);

if (!r.ok) throw new Error(`activity-summary 取得失敗: HTTP ${r.status}`);
const data = await r.json();
if (data.data_status !== "ok") {
  throw new Error(`活動記録を確認できないため投稿しません: data_status=${data.data_status}`);
}
const range = { start: rangeStart.toISOString(), end: now.toISOString() };
fs.mkdirSync("output", { recursive: true });
fs.writeFileSync("output/hourly-work-context.json", JSON.stringify({ range, data }, null, 2), { mode: 0o600 });

const apps = (data?.apps ?? []).slice(0, 12).map((a) => ({
  name: a.name,
  minutes: a.minutes,
}));

const windows = (data?.windows ?? []).slice(0, 24).map((w) => ({
  app: w.app_name ?? w.app,
  title: w.window_name ?? w.name ?? w.title,
  url: w.browser_url,
  minutes: w.minutes,
  text: String(w.key_text ?? w.text ?? "").slice(0, 180),
}));

const keyTexts = (data?.key_texts ?? data?.keyTexts ?? []).slice(0, 24).map((t) => ({
  app: t.app_name ?? t.app,
  window: t.window_name ?? t.window,
  url: t.browser_url,
  text: String(t.text ?? t.key_text ?? "").replace(/\s+/g, " ").slice(0, 220),
}));

const audio = (
  data?.audio_summary?.top_transcriptions ??
  data?.audioSummary?.topTranscriptions ??
  []
).slice(0, 8).map((a) => ({
  speaker: a.speaker_name ?? (typeof a.speaker === "string" ? a.speaker : a.speaker?.name),
  timestamp: a.timestamp,
  text: String(a.transcription ?? a.text ?? "").replace(/\s+/g, " ").slice(0, 220),
}));

console.log(JSON.stringify({
  device,
  range,
  data_status: data.data_status,
  total_active_minutes: data.total_active_minutes,
  work,
  breaks,
  apps,
  windows,
  keyTexts,
  audio,
}, null, 2));
```

この結果は時間配分の把握に使う。Slack投稿はまだ作らず、必ずステップ2へ進む。

# ステップ2: 詳細確認検索

アクティビティ概要だけで判断せず、直近1時間の実際の画面文脈を確認する。

```bun
import * as fs from "fs";

const KEY = process.env.SCREENPIPE_LOCAL_API_KEY;
if (!KEY) throw new Error("SCREENPIPE_LOCAL_API_KEY が設定されていません");
const API = process.env.SCREENPIPE_LOCAL_API_URL || "http://localhost:3030";
const { range } = JSON.parse(fs.readFileSync("output/hourly-work-context.json", "utf8"));
const params = new URLSearchParams({
  content_type: "all",
  limit: "20",
  start_time: range.start,
  end_time: range.end,
  max_content_length: "500",
  fields: "type,content.timestamp,content.app_name,content.window_name,content.browser_url,content.text,content.transcription,content.text_content,content.input_text",
});

const r = await fetch(`${API}/search?${params}`, {
  headers: { Authorization: `Bearer ${KEY}`, "X-Screenpipe-Client": "api" },
  signal: AbortSignal.timeout(30000),
});
if (!r.ok) throw new Error(`search 取得失敗: HTTP ${r.status}`);
const data = await r.json();
if (!Array.isArray(data.data)) throw new Error("search の応答に data 配列がありません");

const recent = data.data.slice(0, 20).map((d) => {
  // fields 指定時は content.timestamp などがフラットなキーで返る。
  const content = d.content ?? Object.fromEntries(
    Object.entries(d).filter(([key]) => key.startsWith("content.")).map(([key, value]) => [key.slice(8), value])
  );
  const text = String(
    content.text ?? content.transcription ?? content.text_content ?? content.input_text ?? ""
  ).replace(/\s+/g, " ");
  return {
    type: d.type,
    timestamp: content.timestamp,
    app: content.app_name,
    window: content.window_name,
    url: content.browser_url,
    text: text.slice(0, 360),
  };
}).sort((a, b) => {
  const at = Date.parse(a.timestamp ?? "");
  const bt = Date.parse(b.timestamp ?? "");
  return Number.isNaN(at) || Number.isNaN(bt) ? 0 : at - bt;
});

console.log(JSON.stringify(recent, null, 2));
```

この結果を使って、内部的に次を行う。

1. 直近1時間を2から5個の作業ブロックに分ける。
2. 各ブロックについて、作業対象、根拠、推定時間、成果の有無を判定する。
3. Slack投稿では、確度の高い内容を優先して短くまとめる。

根拠がある書き方の例:

- `launch-consulting` のPRレビューとマージ作業
- `pipe.md` のSlack投稿手順修正
- `iPhone スクリーンタイム通知` ショートカット設定確認
- `ELE` の監査ドキュメント編集

根拠が弱い書き方の例:

- チーム連携
- 品質管理
- ドキュメント作業
- 調査

根拠が弱い表現を使う場合は、必ず何の画面からそう判断したかを `根拠` に書く。

# ステップ3: Slackに投稿する

ステップ1・2を踏まえた最終投稿文を `output/report.txt` に保存してから、以下を実行する。ファイルには投稿本文だけを書き、コードフェンスや説明を付けない。

Webhookは、既存の作業通知と同じ `~/.screenpipe/work-state/config.env` の `SLACK_WEBHOOK_URL` を利用する。時間レポート専用の `HOURLY_WORK_SLACK_WEBHOOK_URL` がある場合はそちらを優先する。どちらも同名の環境変数で上書きできる。

現在の `/connections/slack` は接続状態を返すAPIであり、Webhookの取得には使わない。送信先が未設定ならエラーで終了する。

重要:

- 通常実行では、本文やJSONを作るだけで止まらず、WebhookへPOSTするところまで実行する。
- ドライランでは `SCREENPIPE_HOURLY_DRY_RUN=1` をこのコードの実行環境に設定する。
- ドライランの完了をSlack送信成功と表現しない。
- 投稿に失敗した場合は、投稿したと主張しない。
- アプリ内通知やテスト通知を送らない。

```bun
import * as fs from "fs";

const text = fs.readFileSync("output/report.txt", "utf8").trim();
if (!text || text.includes("未置換_送信禁止") || text.split(/\r?\n/).length > 11) {
  throw new Error("Slack投稿文が空、未置換、または11行を超えています");
}

if (process.env.SCREENPIPE_HOURLY_DRY_RUN === "1") {
  console.log("ドライラン完了: output/report.txt に保存しました。Slackには送信していません。");
  process.exit(0);
}

const configFile = `${process.env.HOME}/.screenpipe/work-state/config.env`;
const config = {};
if (fs.existsSync(configFile)) {
  for (const rawLine of fs.readFileSync(configFile, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const idx = line.indexOf("=");
    if (idx === -1) continue;
    config[line.slice(0, idx).trim()] = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, "");
  }
}
const webhookUrl = process.env.HOURLY_WORK_SLACK_WEBHOOK_URL || config.HOURLY_WORK_SLACK_WEBHOOK_URL
  || process.env.SLACK_WEBHOOK_URL || config.SLACK_WEBHOOK_URL;
if (!webhookUrl) throw new Error("作業通知用の SLACK_WEBHOOK_URL が設定されていません");

const postRes = await fetch(webhookUrl, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ text }),
  signal: AbortSignal.timeout(15000),
});
if (!postRes.ok) throw new Error(`Slack投稿に失敗しました: HTTP ${postRes.status}`);
if ((await postRes.text()).trim() !== "ok") {
  throw new Error("Slack投稿の応答が想定外です");
}

console.log("Slackに1時間レポートを送信しました。");
```

通常実行でSlack投稿に成功した場合のみ、正確に `Slackに1時間レポートを送信しました。` と出力する。

ドライランの場合は `ドライラン完了: output/report.txt に保存しました。Slackには送信していません。` と出力する。
