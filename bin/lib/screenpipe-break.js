#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const STATE_DIR = path.join(HOME, '.screenpipe', 'work-state');
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

function readEvents() {
  if (!fs.existsSync(BREAKS_FILE)) return [];
  return fs
    .readFileSync(BREAKS_FILE, 'utf8')
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

function appendEvent(event) {
  ensureStateDir();
  fs.appendFileSync(BREAKS_FILE, `${JSON.stringify(event)}\n`, { mode: 0o600 });
}

function openBreak(events = readEvents()) {
  let current = null;
  for (const event of events) {
    if (event.type === 'break_start') current = event;
    if (event.type === 'break_end') current = null;
  }
  return current;
}

function startOfLocalDay(date = new Date()) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function breakDurationMs(start, end = new Date()) {
  return Math.max(0, end.getTime() - new Date(start.at).getTime());
}

function todayBreakTotalMs(events = readEvents(), now = new Date()) {
  const startOfDay = startOfLocalDay(now).getTime();
  let current = null;
  let total = 0;

  for (const event of events) {
    if (event.type === 'break_start') {
      current = event;
      continue;
    }
    if (event.type === 'break_end' && current) {
      const start = Math.max(new Date(current.at).getTime(), startOfDay);
      const end = Math.max(new Date(event.at).getTime(), start);
      if (end >= startOfDay) total += end - start;
      current = null;
    }
  }

  if (current) {
    const start = Math.max(new Date(current.at).getTime(), startOfDay);
    total += Math.max(0, now.getTime() - start);
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
    process.env.BREAK_SLACK_WEBHOOK_URL ||
    process.env.SLACK_WEBHOOK_URL ||
    config.BREAK_SLACK_WEBHOOK_URL ||
    config.SLACK_WEBHOOK_URL ||
    (await webhookFromScreenpipe(config))
  );
}

async function postSlack(text) {
  const config = readConfig();
  if (config.BREAK_SLACK_ENABLED === 'false') return { skipped: true };

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
  console.log(`Slack通知は未設定です。必要なら ${CONFIG_FILE} に BREAK_SLACK_WEBHOOK_URL を設定してください。`);
}

async function start(args) {
  const events = readEvents();
  const current = openBreak(events);
  if (current) {
    console.log(`すでに休憩中です: ${formatDuration(breakDurationMs(current))}`);
    return;
  }

  const note = messageFromArgs(args);
  const event = {
    type: 'break_start',
    at: localIso(),
    device: deviceName(),
    ...(note ? { note } : {}),
  };
  appendEvent(event);

  const text = [
    `休憩に入ります`,
    `端末: ${event.device}`,
    note ? `メモ: ${note}` : null,
  ]
    .filter(Boolean)
    .join('\n');

  const slack = await postSlack(text);
  console.log(`休憩を開始しました: ${event.at}`);
  if (slack.reason === 'missing_webhook') printSlackHint();
  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
}

async function end(args) {
  const events = readEvents();
  const current = openBreak(events);
  if (!current) {
    console.log('現在は休憩中ではありません。');
    return;
  }

  const note = messageFromArgs(args);
  const now = new Date();
  const duration = breakDurationMs(current, now);
  const event = {
    type: 'break_end',
    at: localIso(now),
    device: deviceName(),
    duration_ms: duration,
    ...(note ? { note } : {}),
  };
  appendEvent(event);

  const text = [
    `戻りました`,
    `端末: ${event.device}`,
    `休憩: ${formatDuration(duration)}`,
    note ? `メモ: ${note}` : null,
  ]
    .filter(Boolean)
    .join('\n');

  const slack = await postSlack(text);
  console.log(`休憩を終了しました: ${formatDuration(duration)}`);
  if (slack.reason === 'missing_webhook') printSlackHint();
  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
}

function status() {
  const events = readEvents();
  const current = openBreak(events);
  if (current) {
    console.log(`休憩中: ${formatDuration(breakDurationMs(current))}`);
    console.log(`開始: ${current.at}`);
  } else {
    console.log('作業中: 現在は休憩中ではありません。');
  }
  console.log(`今日の休憩合計: ${formatDuration(todayBreakTotalMs(events))}`);
  console.log(`ログ: ${BREAKS_FILE}`);
}

async function main() {
  const command = path.basename(process.argv[1]).replace(/^screenpipe-break-?/, '');
  const args = process.argv.slice(2);

  if (command === 'start' || command === 'break-start') return start(args);
  if (command === 'end' || command === 'break-end') return end(args);
  if (command === 'status' || command === 'break-status') return status();

  console.log('使い方: break-start [メモ] | break-end [メモ] | break-status');
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
