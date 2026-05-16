#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const STATE_DIR = path.join(HOME, '.screenpipe', 'work-state');
const GOALS_DIR = path.join(STATE_DIR, 'daily-goals');
const CONFIG_FILE = path.join(STATE_DIR, 'config.env');

const KNOWN_COMMANDS = new Set([
  'add',
  'cancel',
  'clear',
  'context',
  'done',
  'e',
  'edit',
  'help',
  'json',
  'l',
  'list',
  'n',
  'new',
  'set',
  'status',
  'undo',
]);

function ensureStateDir() {
  fs.mkdirSync(GOALS_DIR, { recursive: true });
}

function localDateKey(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join('-');
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

function goalFile(date = localDateKey()) {
  return path.join(GOALS_DIR, `${date}.json`);
}

function markdownFile(date = localDateKey()) {
  return path.join(GOALS_DIR, `${date}.md`);
}

function markdownFileForName(name) {
  const raw = String(name || '').trim();
  if (!raw) return markdownFile();
  if (path.isAbsolute(raw)) return raw;
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return markdownFile(raw);
  if (/^\d{4}-\d{2}-\d{2}\.md$/.test(raw)) return path.join(GOALS_DIR, raw);
  return path.join(GOALS_DIR, raw.endsWith('.md') ? raw : `${raw}.md`);
}

function blankGoals(date = localDateKey()) {
  return {
    version: 1,
    date,
    device: deviceName(),
    created_at: localIso(),
    updated_at: localIso(),
    goals: [],
  };
}

function goalsToMarkdown(data) {
  const lines = [
    `# 今日やること: ${data.date}`,
    '',
  ];

  if (data.goals.length === 0) {
    lines.push('- [ ] ');
  } else {
    for (const goal of data.goals) {
      if (goal.status === 'canceled') continue;
      const mark = goal.status === 'done' ? 'x' : ' ';
      lines.push(`- [${mark}] ${goal.text}`);
    }
  }

  lines.push('');
  return lines.join('\n');
}

function parseMarkdownGoals(markdown, date = localDateKey(), existing = blankGoals(date)) {
  const data = {
    ...blankGoals(date),
    created_at: existing.created_at || localIso(),
    device: existing.device || deviceName(),
    goals: [],
  };
  const byText = new Map();
  for (const goal of existing.goals || []) {
    if (!goal.text) continue;
    if (!byText.has(goal.text)) byText.set(goal.text, goal);
  }

  for (const rawLine of markdown.split(/\r?\n/)) {
    const line = rawLine.trim();
    let match = line.match(/^[-*]\s+\[([ xX])\]\s*(.+?)\s*$/);
    let status = 'planned';
    let text = '';

    if (match) {
      status = match[1].toLowerCase() === 'x' ? 'done' : 'planned';
      text = match[2].trim();
    } else {
      match = line.match(/^[-*]\s+(.+?)\s*$/);
      if (match) text = match[1].trim();
    }

    if (!text) continue;
    if (text.startsWith('#')) continue;

    const prior = byText.get(text);
    const now = localIso();
    data.goals.push({
      id: String(data.goals.length + 1),
      text,
      status,
      created_at: prior?.created_at || now,
      updated_at: prior?.updated_at || now,
      device: prior?.device || deviceName(),
      ...(status === 'done' ? { done_at: prior?.done_at || now } : {}),
    });
  }

  return data;
}

function syncMarkdown(data) {
  ensureStateDir();
  const file = markdownFile(data.date);
  fs.writeFileSync(file, goalsToMarkdown(data), { mode: 0o600 });
}

function dateFromMarkdownFile(file) {
  const base = path.basename(file);
  const match = base.match(/^(\d{4}-\d{2}-\d{2})\.md$/);
  return match?.[1] || localDateKey();
}

function syncMarkdownToJson(file) {
  const date = dateFromMarkdownFile(file);
  const existing = readGoals(date);
  const markdown = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const data = parseMarkdownGoals(markdown, date, existing);
  return writeGoals(data, { syncMarkdownFile: false });
}

function readGoals(date = localDateKey()) {
  const file = goalFile(date);
  const mdFile = markdownFile(date);
  const hasJson = fs.existsSync(file);
  const hasMarkdown = fs.existsSync(mdFile);

  let data = blankGoals(date);
  if (hasJson) {
    try {
      const json = JSON.parse(fs.readFileSync(file, 'utf8'));
      data = {
        ...blankGoals(date),
        ...json,
        date,
        goals: Array.isArray(json.goals) ? json.goals : [],
      };
    } catch {
      data = blankGoals(date);
    }
  }

  if (hasMarkdown) {
    const jsonMtime = hasJson ? fs.statSync(file).mtimeMs : 0;
    const mdMtime = fs.statSync(mdFile).mtimeMs;
    if (!hasJson || mdMtime > jsonMtime) {
      data = parseMarkdownGoals(fs.readFileSync(mdFile, 'utf8'), date, data);
      writeGoals(data, { syncMarkdownFile: false });
    }
  }

  return data;
}

function writeGoals(data, options = {}) {
  ensureStateDir();
  const next = {
    ...data,
    version: 1,
    updated_at: localIso(),
  };
  const file = goalFile(next.date);
  const tmp = `${file}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(tmp, file);
  if (options.syncMarkdownFile !== false) syncMarkdown(next);
  return next;
}

function parseGoalLine(line) {
  let value = line
    .trim()
    .replace(/^\s*[-*・•]\s+/, '')
    .replace(/^\s*\d+[\.)、]\s+/, '')
    .trim();
  const checked = value.match(/^\[([ xX])\]\s+(.+)$/);
  if (checked) {
    return {
      text: checked[2].trim(),
      status: checked[1].toLowerCase() === 'x' ? 'done' : 'planned',
    };
  }
  return { text: value, status: 'planned' };
}

function parseGoalSpecs(text) {
  return text
    .split(/\r?\n/)
    .map(parseGoalLine)
    .filter((goal) => goal.text);
}

function nextGoalId(data) {
  const nums = data.goals
    .map((goal) => Number(goal.id))
    .filter((id) => Number.isInteger(id) && id > 0);
  return String((nums.length ? Math.max(...nums) : 0) + 1);
}

function newGoal(data, text, status = 'planned') {
  const now = localIso();
  return {
    id: nextGoalId(data),
    text,
    status,
    created_at: now,
    updated_at: now,
    ...(status === 'done' ? { done_at: now } : {}),
    device: deviceName(),
  };
}

function formatGoal(goal) {
  const mark = goal.status === 'done' ? 'x' : goal.status === 'canceled' ? '-' : ' ';
  const suffix = goal.status === 'done'
    ? ' done'
    : goal.status === 'canceled'
      ? ' canceled'
      : '';
  return `[${mark}] ${goal.id}. ${goal.text}${suffix}`;
}

function summaryCounts(goals) {
  const counts = { planned: 0, done: 0, canceled: 0, total: goals.length };
  for (const goal of goals) {
    if (goal.status === 'done') counts.done += 1;
    else if (goal.status === 'canceled') counts.canceled += 1;
    else counts.planned += 1;
  }
  return counts;
}

function printStatus(data) {
  const counts = summaryCounts(data.goals);
  console.log(`今日の宣言タスク: ${data.date}`);
  if (data.goals.length === 0) {
    console.log('まだ宣言タスクはありません。');
    console.log(`追加: today set $'タスク1\\nタスク2'`);
    return;
  }

  for (const goal of data.goals) console.log(formatGoal(goal));
  console.log(`合計: ${counts.total} / done: ${counts.done} / remaining: ${counts.planned}`);
  console.log(`保存先: ${goalFile(data.date)}`);
  console.log(`編集: ${markdownFile(data.date)}`);
}

function listMarkdownFiles() {
  ensureStateDir();
  return fs
    .readdirSync(GOALS_DIR)
    .filter((name) => /^\d{4}-\d{2}-\d{2}\.md$/.test(name))
    .sort()
    .reverse();
}

function readStdin() {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      resolve('');
      return;
    }

    let body = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      body += chunk;
    });
    process.stdin.on('end', () => resolve(body.trim()));
  });
}

function messageFromArgsAndStdin(args, stdin) {
  const fromArgs = args.join(' ').trim();
  return [fromArgs, stdin].filter(Boolean).join('\n').trim();
}

function findGoal(data, query) {
  const needle = String(query || '').trim();
  if (!needle) throw new Error('対象タスクを指定してください。例: today done 1');

  const byId = data.goals.find((goal) => String(goal.id) === needle);
  if (byId) return byId;

  const lowered = needle.toLowerCase();
  const matches = data.goals.filter((goal) => goal.text.toLowerCase().includes(lowered));
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    throw new Error(`複数のタスクに一致しました: ${matches.map((goal) => goal.id).join(', ')}`);
  }
  throw new Error(`一致するタスクが見つかりません: ${needle}`);
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
    process.env.DAILY_GOALS_SLACK_WEBHOOK_URL ||
    process.env.WORK_SLACK_WEBHOOK_URL ||
    process.env.SLACK_WEBHOOK_URL ||
    config.DAILY_GOALS_SLACK_WEBHOOK_URL ||
    config.WORK_SLACK_WEBHOOK_URL ||
    config.SLACK_WEBHOOK_URL ||
    (await webhookFromScreenpipe(config))
  );
}

async function postSlack(text) {
  const config = readConfig();
  if ((process.env.DAILY_GOALS_SLACK_ENABLED || config.DAILY_GOALS_SLACK_ENABLED) === 'false') {
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

function slackGoalLines(goals) {
  return goals
    .filter((goal) => goal.status !== 'canceled')
    .slice(0, 12)
    .map((goal) => `• ${goal.id}. ${goal.text}`);
}

async function notifySet(data, actionLabel) {
  const lines = [
    `*今日やること: ${data.date}*`,
    `• 端末: ${data.device}`,
    ...slackGoalLines(data.goals),
  ];
  if (data.goals.length > 12) lines.push(`• 他 ${data.goals.length - 12} 件`);

  const slack = await postSlack(lines.join('\n'));
  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
  if (slack.reason === 'missing_webhook') {
    console.log(`${actionLabel}。Slack通知は未設定です。`);
  }
}

async function notifyDone(data, goal, done) {
  const slack = await postSlack([
    done ? '*今日のタスクを完了にしました*' : '*今日のタスクを未完了に戻しました*',
    `• ${goal.id}. ${goal.text}`,
    `• 残り: ${summaryCounts(data.goals).planned}`,
  ].join('\n'));

  if (slack.error) {
    console.error(slack.error);
    process.exitCode = 2;
  }
}

function contextJson(data) {
  const counts = summaryCounts(data.goals);
  return {
    date: data.date,
    device: data.device,
    file: goalFile(data.date),
    markdown_file: markdownFile(data.date),
    counts,
    goals: data.goals.map((goal) => ({
      id: goal.id,
      text: goal.text,
      manual_status: goal.status,
      created_at: goal.created_at,
      updated_at: goal.updated_at,
      done_at: goal.done_at || null,
      canceled_at: goal.canceled_at || null,
      note: goal.note || null,
    })),
  };
}

async function setGoals(args, stdin) {
  const text = messageFromArgsAndStdin(args, stdin);
  const items = parseGoalSpecs(text);
  if (items.length === 0) throw new Error('宣言タスクが空です。');

  let data = blankGoals();
  data.goals = [];
  for (const item of items) data.goals.push(newGoal(data, item.text, item.status));
  data = writeGoals(data);
  printStatus(data);
  await notifySet(data, '今日やることを記録しました');
}

async function addGoals(args, stdin) {
  const text = messageFromArgsAndStdin(args, stdin);
  const items = parseGoalSpecs(text);
  if (items.length === 0) throw new Error('追加するタスクが空です。');

  let data = readGoals();
  for (const item of items) data.goals.push(newGoal(data, item.text, item.status));
  data = writeGoals(data);
  printStatus(data);
  await notifySet(data, '今日やることを追加しました');
}

async function markDone(args, done) {
  let data = readGoals();
  const goal = findGoal(data, args.join(' '));
  goal.status = done ? 'done' : 'planned';
  goal.updated_at = localIso();
  if (done) goal.done_at = localIso();
  else delete goal.done_at;
  data = writeGoals(data);
  printStatus(data);
  await notifyDone(data, goal, done);
}

function cancelGoal(args) {
  let data = readGoals();
  const goal = findGoal(data, args.join(' '));
  goal.status = 'canceled';
  goal.updated_at = localIso();
  goal.canceled_at = localIso();
  data = writeGoals(data);
  printStatus(data);
}

function clearGoals() {
  const data = writeGoals(blankGoals());
  printStatus(data);
}

function printHelp() {
  console.log(`使い方:
  today new | today n           今日のタスクをMarkdownで新規作成/編集
  today edit | today e [date]   既存のタスクMarkdownを選んで編集
  today                         今日の宣言タスクを表示
  today list | today l          タスクMarkdownの日付一覧
  today set $'A\\nB'             今日やることを置き換え
  today add A                   今日やることを追加
  today done 1                  タスクを完了にする
  today undo 1                  完了を取り消す
  today cancel 1                タスクを対象外にする
  today json                    日次レポート用JSONを出力

保存先: ${GOALS_DIR}
Markdown形式:
  - [ ] 未完了タスク
  - [x] 完了タスク`);
}

function editorCommand() {
  return process.env.VISUAL || process.env.EDITOR || 'vim';
}

function commandExists(command) {
  const result = require('child_process').spawnSync('sh', ['-lc', `command -v ${JSON.stringify(command)} >/dev/null 2>&1`]);
  return result.status === 0;
}

function selectorCommand() {
  if (process.env.TODAY_SELECT_CMD) return process.env.TODAY_SELECT_CMD;
  if (process.env.SELECTCMD) return process.env.SELECTCMD;
  if (process.env.MEMO_SELECT_CMD) return process.env.MEMO_SELECT_CMD;
  if (commandExists('peco')) return 'peco';
  if (commandExists('fzf')) return 'fzf';
  return null;
}

function runSelector(files) {
  const selector = selectorCommand();
  if (!selector) {
    return files.length > 0 ? [files[0]] : [];
  }

  const result = require('child_process').spawnSync('sh', ['-lc', selector], {
    input: `${files.join('\n')}\n`,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${selector} exited with status ${result.status}`);
  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function openEditor(files) {
  const editor = editorCommand();
  const parts = editor.match(/(?:[^\s"]+|"[^"]*")+/g) || [editor];
  const command = parts[0].replace(/^"|"$/g, '');
  const args = parts.slice(1).map((part) => part.replace(/^"|"$/g, ''));
  const targets = Array.isArray(files) ? files : [files];
  const result = require('child_process').spawnSync(command, [...args, ...targets], {
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${editor} exited with status ${result.status}`);
  }
}

function editMarkdownFiles(files) {
  for (const file of files) {
    if (!fs.existsSync(file)) {
      fs.writeFileSync(file, goalsToMarkdown(blankGoals(dateFromMarkdownFile(file))), { mode: 0o600 });
    }
  }
  openEditor(files);
  for (const file of files) {
    syncMarkdownToJson(file);
  }
  printStatus(readGoals(dateFromMarkdownFile(files[0])));
}

function newGoals() {
  ensureStateDir();
  const date = localDateKey();
  const mdFile = markdownFile(date);
  let data = readGoals(date);

  if (data.goals.length === 0 && !fs.existsSync(mdFile)) {
    data = writeGoals(blankGoals(date));
  } else if (!fs.existsSync(mdFile)) {
    syncMarkdown(data);
  }

  editMarkdownFiles([mdFile]);
}

function editGoals(args = []) {
  ensureStateDir();
  if (args.length > 0) {
    editMarkdownFiles(args.map(markdownFileForName));
    return;
  }

  const files = listMarkdownFiles();
  if (files.length === 0) {
    newGoals();
    return;
  }

  const selected = runSelector(files);
  if (selected.length === 0) throw new Error('No files selected');
  editMarkdownFiles(selected.map(markdownFileForName));
}

async function main() {
  const bin = path.basename(process.argv[1]);
  let args = process.argv.slice(2);
  let command = args[0] || 'status';

  if (bin === 'today-done') {
    command = 'done';
  } else if (bin === 'today-status') {
    command = 'status';
  } else if (bin === 'screenpipe-daily-goals' && !KNOWN_COMMANDS.has(command)) {
    command = 'status';
  } else if (bin === 'today' && args.length > 0 && !KNOWN_COMMANDS.has(command)) {
    command = 'set';
  }

  if (KNOWN_COMMANDS.has(args[0])) args = args.slice(1);

  const stdin = await readStdin();

  if (command === 'help') return printHelp();
  if (command === 'new' || command === 'n') return newGoals();
  if (command === 'edit' || command === 'e') return editGoals(args);
  if (command === 'status') return printStatus(readGoals());
  if (command === 'list' || command === 'l') {
    const files = listMarkdownFiles();
    if (files.length === 0) console.log('まだタスクMarkdownはありません。');
    else for (const file of files) console.log(file);
    return;
  }
  if (command === 'json' || command === 'context') {
    console.log(JSON.stringify(contextJson(readGoals()), null, 2));
    return;
  }
  if (command === 'set') return setGoals(args, stdin);
  if (command === 'add') return addGoals(args, stdin);
  if (command === 'done') return markDone(args, true);
  if (command === 'undo') return markDone(args, false);
  if (command === 'cancel') return cancelGoal(args);
  if (command === 'clear') return clearGoals();

  printHelp();
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
