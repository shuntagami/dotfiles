#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const STATE_DIR = path.join(HOME, '.screenpipe', 'work-state');
const WORK_FILE = path.join(STATE_DIR, 'work.jsonl');
const BREAKS_FILE = path.join(STATE_DIR, 'breaks.jsonl');
const CONFIG_FILE = path.join(STATE_DIR, 'config.env');

function ensureStateDir() {
  fs.mkdirSync(STATE_DIR, { recursive: true });
}

function localIso(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  const offsetMinutes = -date.getTimezoneOffset();
  const sign = offsetMinutes >= 0 ? '+' : '-';
  const abs = Math.abs(offsetMinutes);
  const offset = `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
  return [
    date.getFullYear(),
    '-',
    pad(date.getMonth() + 1),
    '-',
    pad(date.getDate()),
    'T',
    pad(date.getHours()),
    ':',
    pad(date.getMinutes()),
    ':',
    pad(date.getSeconds()),
    offset,
  ].join('');
}

function deviceName() {
  return process.env.SCREENPIPE_DEVICE_NAME || process.env.DEVICE_NAME || os.hostname();
}

function readConfig() {
  const config = {};
  if (!fs.existsSync(CONFIG_FILE)) return config;

  for (const rawLine of fs.readFileSync(CONFIG_FILE, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    const value = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    config[key] = value;
  }
  return config;
}

function readEvents(file) {
  if (!fs.existsSync(file)) return [];
  return fs
    .readFileSync(file, 'utf8')
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

function appendEvent(file, event) {
  ensureStateDir();
  fs.appendFileSync(file, `${JSON.stringify(event)}\n`, { mode: 0o600 });
}

function openEvent(events, startType, endType) {
  let current = null;
  for (const event of events) {
    if (event.type === startType) current = event;
    if (event.type === endType) current = null;
  }
  return current;
}

function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function durationMs(event, end = new Date()) {
  return Math.max(0, end.getTime() - new Date(event.at).getTime());
}

function intervals(events, startType, endType, start, end) {
  let current = null;
  const result = [];

  for (const event of events) {
    if (event.type === startType) {
      current = new Date(event.at);
      continue;
    }

    if (event.type === endType && current) {
      const eventEnd = new Date(event.at);
      const overlapStart = new Date(Math.max(current.getTime(), start.getTime()));
      const overlapEnd = new Date(Math.min(eventEnd.getTime(), end.getTime()));
      if (overlapEnd > overlapStart) {
        result.push({ start: overlapStart, end: overlapEnd });
      }
      current = null;
    }
  }

  if (current) {
    const overlapStart = new Date(Math.max(current.getTime(), start.getTime()));
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

function formatDuration(ms) {
  const totalMinutes = Math.max(0, Math.round(ms / 60000));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return `${hours}時間${minutes}分`;
  if (hours > 0) return `${hours}時間`;
  return `${minutes}分`;
}

function todaySummary(now = new Date()) {
  const dayStart = startOfLocalDay(now);
  const workIntervals = intervals(readEvents(WORK_FILE), 'work_start', 'work_end', dayStart, now);
  const breakIntervals = intervals(readEvents(BREAKS_FILE), 'break_start', 'break_end', dayStart, now);
  const grossMs = sumIntervals(workIntervals);
  const breakMs = overlapMs(workIntervals, breakIntervals);
  return {
    grossMs,
    breakMs,
    netMs: Math.max(0, grossMs - breakMs),
  };
}

async function webhookFromScreenpipe(config) {
  const key = process.env.SCREENPIPE_LOCAL_API_KEY || config.SCREENPIPE_LOCAL_API_KEY;
  if (!key) return null;

  try {
    const res = await fetch('http://localhost:3030/connections/slack', {
      headers: { Authorization: `Bearer ${key}` },
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data?.credentials?.webhook_url || null;
  } catch {
    return null;
  }
}

async function slackWebhookUrl() {
  const config = readConfig();
  return (
    process.env.WORK_SLACK_WEBHOOK_URL ||
    process.env.BREAK_SLACK_WEBHOOK_URL ||
    process.env.SLACK_WEBHOOK_URL ||
    config.WORK_SLACK_WEBHOOK_URL ||
    config.BREAK_SLACK_WEBHOOK_URL ||
    config.SLACK_WEBHOOK_URL ||
    (await webhookFromScreenpipe(config))
  );
}

async function postSlack(text) {
  const config = readConfig();
  if ((process.env.WORK_SLACK_ENABLED || config.WORK_SLACK_ENABLED) === 'false') {
    return { skipped: true };
  }

  const webhookUrl = await slackWebhookUrl();
  if (!webhookUrl) return { skipped: true, reason: 'missing_webhook' };

  const res = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });

  if (!res.ok) {
    return { skipped: false, error: `Slack投稿に失敗しました: ${res.status}` };
  }
  return { skipped: false };
}

function messageFromArgs(args) {
  return args.join(' ').trim();
}

function printSlackHint() {
  console.log(`Slack通知は未設定です。必要なら ${CONFIG_FILE} に WORK_SLACK_WEBHOOK_URL を設定してください。`);
}

async function start(args) {
  const events = readEvents(WORK_FILE);
  const current = openEvent(events, 'work_start', 'work_end');
  if (current) {
    console.log(`すでに作業中です: ${formatDuration(durationMs(current))}`);
    console.log(`開始: ${current.at}`);
    return;
  }

  const note = messageFromArgs(args);
  const event = {
    type: 'work_start',
    at: localIso(),
    device: deviceName(),
    ...(note ? { note } : {}),
  };
  appendEvent(WORK_FILE, event);

  const text = [
    '作業を開始します',
    `端末: ${event.device}`,
    note ? `メモ: ${note}` : null,
  ]
    .filter(Boolean)
    .join('\n');

  const slack = await postSlack(text);
  console.log(`作業を開始しました: ${event.at}`);
  if (slack.reason === 'missing_webhook') printSlackHint();
  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
}

function closeOpenBreakIfNeeded(now) {
  const breakEvents = readEvents(BREAKS_FILE);
  const currentBreak = openEvent(breakEvents, 'break_start', 'break_end');
  if (!currentBreak) return null;

  const duration = durationMs(currentBreak, now);
  const event = {
    type: 'break_end',
    at: localIso(now),
    device: deviceName(),
    duration_ms: duration,
    note: 'work-endで自動終了',
  };
  appendEvent(BREAKS_FILE, event);
  return { event, duration };
}

async function end(args) {
  const events = readEvents(WORK_FILE);
  const current = openEvent(events, 'work_start', 'work_end');
  if (!current) {
    if (events.length === 0 || events[events.length - 1]?.type !== 'work_end') {
      const note = messageFromArgs(args);
      appendEvent(WORK_FILE, {
        type: 'work_end',
        at: localIso(),
        device: deviceName(),
        duration_ms: 0,
        marker: true,
        ...(note ? { note } : {}),
      });
      console.log('現在は作業中ではありません。勤務外状態を記録しました。');
      return;
    }

    console.log('現在は作業中ではありません。');
    return;
  }

  const note = messageFromArgs(args);
  const now = new Date();
  const closedBreak = closeOpenBreakIfNeeded(now);
  const duration = durationMs(current, now);
  const event = {
    type: 'work_end',
    at: localIso(now),
    device: deviceName(),
    duration_ms: duration,
    ...(note ? { note } : {}),
  };
  appendEvent(WORK_FILE, event);

  const summary = todaySummary(now);
  const text = [
    '作業を終了します',
    `端末: ${event.device}`,
    `今回: ${formatDuration(duration)}`,
    `今日: 実作業 ${formatDuration(summary.netMs)} / 休憩 ${formatDuration(summary.breakMs)}`,
    closedBreak ? `休憩: 未終了だった休憩を自動終了 (${formatDuration(closedBreak.duration)})` : null,
    note ? `メモ: ${note}` : null,
  ]
    .filter(Boolean)
    .join('\n');

  const slack = await postSlack(text);
  console.log(`作業を終了しました: ${formatDuration(duration)}`);
  if (closedBreak) {
    console.log(`未終了だった休憩を自動終了しました: ${formatDuration(closedBreak.duration)}`);
  }
  console.log(`今日の実作業: ${formatDuration(summary.netMs)} / 休憩: ${formatDuration(summary.breakMs)}`);
  if (slack.reason === 'missing_webhook') printSlackHint();
  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
}

function status() {
  const events = readEvents(WORK_FILE);
  const current = openEvent(events, 'work_start', 'work_end');
  const summary = todaySummary();
  const currentBreak = openEvent(readEvents(BREAKS_FILE), 'break_start', 'break_end');

  if (current) {
    console.log(`作業中: ${formatDuration(durationMs(current))}`);
    console.log(`開始: ${current.at}`);
  } else {
    console.log('勤務外: 現在は作業中ではありません。');
  }

  if (currentBreak) {
    console.log(`休憩中: ${formatDuration(durationMs(currentBreak))}`);
    console.log(`休憩開始: ${currentBreak.at}`);
  }

  console.log(`今日の実作業: ${formatDuration(summary.netMs)}`);
  console.log(`今日の勤務枠: ${formatDuration(summary.grossMs)}`);
  console.log(`今日の休憩: ${formatDuration(summary.breakMs)}`);
  console.log(`作業ログ: ${WORK_FILE}`);
  console.log(`休憩ログ: ${BREAKS_FILE}`);
}

async function main() {
  const command = path.basename(process.argv[1]).replace(/^screenpipe-work-?/, '');
  const args = process.argv.slice(2);

  if (command === 'start' || command === 'work-start') return start(args);
  if (command === 'end' || command === 'work-end') return end(args);
  if (command === 'status' || command === 'work-status') return status();

  console.log('使い方: work-start [メモ] | work-end [メモ] | work-status');
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
