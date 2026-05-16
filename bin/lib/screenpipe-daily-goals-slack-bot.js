#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const HOME = os.homedir();
const MCP_ENV_FILE = process.env.SLACK_MCP_ENV_FILE || path.join(HOME, '.config', 'mcp', 'slack.env');
const WORK_ENV_FILE = path.join(HOME, '.screenpipe', 'work-state', 'config.env');
const GOALS_BIN = path.resolve(__dirname, '..', 'screenpipe-daily-goals');

function readEnvFile(file) {
  const env = {};
  if (!fs.existsSync(file)) return env;

  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    const value = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    env[key] = value;
  }
  return env;
}

const fileEnv = {
  ...readEnvFile(MCP_ENV_FILE),
  ...readEnvFile(WORK_ENV_FILE),
};

function envValue(name) {
  return process.env[name] || fileEnv[name] || '';
}

const SLACK_BOT_TOKEN = envValue('SLACK_BOT_TOKEN');
const SLACK_APP_TOKEN = envValue('SLACK_APP_TOKEN');

if (!SLACK_BOT_TOKEN) {
  console.error(`SLACK_BOT_TOKEN is not set. Configure ${MCP_ENV_FILE}.`);
  process.exit(1);
}

if (!SLACK_APP_TOKEN) {
  console.error(`SLACK_APP_TOKEN is not set. Enable Slack Socket Mode and add it to ${MCP_ENV_FILE}.`);
  process.exit(1);
}

async function slackApi(method, body = {}) {
  const res = await fetch(`https://slack.com/api/${method}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SLACK_BOT_TOKEN}`,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: JSON.stringify(body),
  });

  const data = await res.json();
  if (!data.ok) {
    throw new Error(`${method} failed: ${data.error || 'unknown_error'}`);
  }
  return data;
}

async function openSocket() {
  const data = await fetch('https://slack.com/api/apps.connections.open', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SLACK_APP_TOKEN}`,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: '{}',
  }).then((res) => res.json());

  if (!data.ok || !data.url) {
    throw new Error(`apps.connections.open failed: ${data.error || 'missing_url'}`);
  }
  return data.url;
}

function stripBotMention(text, botUserId) {
  return String(text || '')
    .replace(new RegExp(`<@${botUserId}>`, 'g'), '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .trim();
}

function runGoals(args, input = '') {
  const result = spawnSync(GOALS_BIN, args, {
    input,
    encoding: 'utf8',
    env: {
      ...process.env,
      DAILY_GOALS_SLACK_ENABLED: 'false',
    },
  });

  const out = [result.stdout, result.stderr].filter(Boolean).join('\n').trim();
  if (result.status !== 0) {
    throw new Error(out || `screenpipe-daily-goals failed: ${result.status}`);
  }
  return out || '完了しました。';
}

function removeFirstWord(text) {
  return text.replace(/^\S+\s*/, '').trim();
}

function parseGoalCommand(rawText) {
  const text = rawText.trim();
  const lower = text.toLowerCase();

  if (!text || lower === 'help' || lower === 'today help' || text === 'ヘルプ') {
    return { args: ['help'] };
  }

  if (lower === 'today new' || lower === 'today n' || lower === 'today edit' || lower === 'today e') {
    return {
      reply: [
        '`today new` / `today edit` はローカルCLI専用です。',
        'Slackでは次の形式で送ってください:',
        'today',
        '- [ ] タスク1',
        '- [x] 完了済みタスク',
      ].join('\n'),
    };
  }

  if (
    lower === 'today' ||
    lower === 'today status' ||
    lower === 'today list' ||
    lower === 'status' ||
    text === '確認' ||
    text === '一覧'
  ) {
    return { args: ['status'] };
  }

  if (lower === 'json' || lower === 'today json') return { args: ['context'] };

  if (lower.startsWith('today add ')) {
    return { args: ['add'], input: text.replace(/^today\s+add\s+/i, '') };
  }
  if (lower.startsWith('add ') || text.startsWith('追加 ')) {
    return { args: ['add'], input: removeFirstWord(text) };
  }

  if (lower.startsWith('today done ')) {
    return { args: ['done', text.replace(/^today\s+done\s+/i, '').trim()] };
  }
  if (lower.startsWith('done ') || text.startsWith('完了 ')) {
    return { args: ['done', removeFirstWord(text)] };
  }

  if (lower.startsWith('today undo ')) {
    return { args: ['undo', text.replace(/^today\s+undo\s+/i, '').trim()] };
  }
  if (lower.startsWith('undo ') || text.startsWith('未完了 ')) {
    return { args: ['undo', removeFirstWord(text)] };
  }

  if (lower.startsWith('today cancel ')) {
    return { args: ['cancel', text.replace(/^today\s+cancel\s+/i, '').trim()] };
  }
  if (lower.startsWith('cancel ') || text.startsWith('対象外 ')) {
    return { args: ['cancel', removeFirstWord(text)] };
  }

  if (lower === 'today clear' || lower === 'clear' || text === 'クリア') {
    return { args: ['clear'] };
  }

  if (/^today\s+set\s+/i.test(text)) {
    return { args: ['set'], input: text.replace(/^today\s+set\s+/i, '') };
  }
  if (lower.startsWith('today\n') || lower.startsWith('today ')) {
    return { args: ['set'], input: text.replace(/^today\s*/i, '').trim() };
  }
  if (text.startsWith('今日やること')) {
    return { args: ['set'], input: text.replace(/^今日やること[:：]?\s*/, '').trim() };
  }

  return null;
}

function shouldHandleEvent(event, botUserId) {
  if (!event) return false;
  if (event.type !== 'message' && event.type !== 'app_mention') return false;
  if (event.bot_id || event.subtype) return false;
  if (event.channel_type === 'im') return true;
  return String(event.text || '').includes(`<@${botUserId}>`) || event.type === 'app_mention';
}

async function handleSlackEvent(event, botUserId) {
  if (!shouldHandleEvent(event, botUserId)) return;

  const text = stripBotMention(event.text, botUserId);
  const parsed = parseGoalCommand(text);
  if (!parsed) {
    await slackApi('chat.postMessage', {
      channel: event.channel,
      thread_ts: event.thread_ts || event.ts,
      text: [
        '今日の宣言タスクだけ扱えます。',
        '例:',
        'today',
        'today set',
        '- タスク1',
        '- タスク2',
        'today done 1',
      ].join('\n'),
    });
    return;
  }

  if (parsed.reply) {
    await slackApi('chat.postMessage', {
      channel: event.channel,
      thread_ts: event.thread_ts || event.ts,
      text: parsed.reply,
    });
    return;
  }

  let reply;
  try {
    reply = runGoals(parsed.args, parsed.input || '');
  } catch (error) {
    reply = error?.message || String(error);
  }

  await slackApi('chat.postMessage', {
    channel: event.channel,
    thread_ts: event.thread_ts || event.ts,
    text: `\`\`\`\n${reply.slice(0, 3500)}\n\`\`\``,
  });
}

function connect(url, botUserId) {
  const ws = new WebSocket(url);

  ws.addEventListener('open', () => {
    console.log('screenpipe daily goals slack bot connected');
  });

  ws.addEventListener('message', (message) => {
    void (async () => {
      const envelope = JSON.parse(message.data);
      if (envelope.envelope_id) {
        ws.send(JSON.stringify({ envelope_id: envelope.envelope_id }));
      }

      if (envelope.type === 'disconnect') {
        ws.close();
        return;
      }

      const event = envelope.payload?.event;
      if (event) await handleSlackEvent(event, botUserId);
    })().catch((error) => {
      console.error(error?.message || error);
    });
  });

  ws.addEventListener('close', () => {
    console.error('screenpipe daily goals slack bot disconnected; reconnecting in 5s');
    setTimeout(() => {
      openSocket()
        .then((nextUrl) => connect(nextUrl, botUserId))
        .catch((error) => {
          console.error(error?.message || error);
          process.exit(1);
        });
    }, 5000);
  });

  ws.addEventListener('error', (event) => {
    console.error('screenpipe daily goals slack bot websocket error', event.message || '');
  });
}

async function main() {
  const auth = await slackApi('auth.test');
  const botUserId = auth.user_id;
  if (!botUserId) throw new Error('auth.test did not return bot user_id');
  const url = await openSocket();
  connect(url, botUserId);
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
