#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const HOME = os.homedir();
const CONFIG_DIR = path.join(process.env.XDG_CONFIG_HOME || path.join(HOME, '.config'), 'oura-morning-report');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.env');
const SCREENPIPE_CONFIG_FILE = path.join(HOME, '.screenpipe', 'work-state', 'config.env');
const STATE_ROOT = process.env.PERSONAL_DATA_STATE_DIR ||
  path.join(process.env.XDG_STATE_HOME || path.join(HOME, '.local', 'state'), 'personal-data');
const STATE_DIR = path.join(STATE_ROOT, 'oura');
const RAW_DIR = path.join(STATE_DIR, 'raw');
const REPORT_DIR = path.join(STATE_DIR, 'morning-reports');
const EVENTS_FILE = path.join(STATE_DIR, 'events.jsonl');
const LAUNCH_LABEL = 'com.user.oura-morning-report';
const LAUNCH_AGENT_FILE = path.join(HOME, 'Library', 'LaunchAgents', `${LAUNCH_LABEL}.plist`);
const OURA_BASE_URL = 'https://api.ouraring.com/v2';

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readEnvFile(file) {
  const values = {};
  if (!fs.existsSync(file)) return values;

  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;

    const idx = line.indexOf('=');
    if (idx === -1) continue;

    const key = line.slice(0, idx).trim();
    const value = line.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

const localConfig = readEnvFile(CONFIG_FILE);
const screenpipeConfig = readEnvFile(SCREENPIPE_CONFIG_FILE);

function configValue(key, fallback = undefined) {
  return process.env[key] || localConfig[key] || fallback;
}

function slackWebhookUrl() {
  return (
    process.env.OURA_SLACK_WEBHOOK_URL ||
    localConfig.OURA_SLACK_WEBHOOK_URL ||
    process.env.SLACK_WEBHOOK_URL ||
    localConfig.SLACK_WEBHOOK_URL ||
    process.env.BREAK_SLACK_WEBHOOK_URL ||
    screenpipeConfig.BREAK_SLACK_WEBHOOK_URL ||
    screenpipeConfig.SLACK_WEBHOOK_URL ||
    null
  );
}

function pad(num) {
  return String(num).padStart(2, '0');
}

function localDateString(date = new Date()) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseLocalDate(dateString) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateString);
  if (!match) throw new Error(`日付は YYYY-MM-DD 形式で指定してください: ${dateString}`);
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function addDays(dateString, days) {
  const date = parseLocalDate(dateString);
  date.setDate(date.getDate() + days);
  return localDateString(date);
}

function compactTimestamp(date = new Date()) {
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    '-',
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join('');
}

function safeJsonWrite(file, data) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
}

function appendJsonl(file, event) {
  ensureDir(path.dirname(file));
  fs.appendFileSync(file, `${JSON.stringify(event)}\n`, { mode: 0o600 });
}

function readJsonl(file) {
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

function numberOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function chooseByDay(items, day) {
  return (items || []).find((item) => item?.day === day) || null;
}

function latestBy(items, getValue) {
  return [...(items || [])]
    .filter(Boolean)
    .sort((a, b) => {
      const av = getValue(a);
      const bv = getValue(b);
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      return av > bv ? -1 : av < bv ? 1 : 0;
    })[0] || null;
}

function pickMainSleep(sleeps, day, now = new Date()) {
  const sameDay = (sleeps || []).filter((sleep) => sleep?.day === day);
  const candidates = sameDay.length > 0 ? sameDay : (sleeps || []);

  const longSleep = latestBy(
    candidates.filter((sleep) => sleep?.type === 'long_sleep'),
    (sleep) => sleep.bedtime_end || sleep.day
  );
  if (longSleep) return longSleep;

  const ended = candidates.filter((sleep) => {
    const end = Date.parse(sleep?.bedtime_end || '');
    return Number.isFinite(end) && end <= now.getTime();
  });

  return latestBy(ended, (sleep) => sleep.total_sleep_duration || sleep.time_in_bed || 0);
}

function normalizeContributors(contributors = {}) {
  return Object.fromEntries(
    Object.entries(contributors || {}).map(([key, value]) => [key, numberOrNull(value)])
  );
}

function normalizeReport({ reportDate, fetchedAt, raw }) {
  const dailySleepItems = raw.daily_sleep?.data || [];
  const sleepItems = raw.sleep?.data || [];
  const readinessItems = raw.daily_readiness?.data || [];
  const spo2Items = raw.daily_spo2?.data || [];
  const activityItems = raw.daily_activity?.data || [];

  const dailySleep =
    chooseByDay(dailySleepItems, reportDate) ||
    latestBy(dailySleepItems, (item) => item.day);

  const day = dailySleep?.day || reportDate;
  const sleep = pickMainSleep(sleepItems, day);
  const readiness = chooseByDay(readinessItems, day) || latestBy(readinessItems, (item) => item.day);
  const spo2 = chooseByDay(spo2Items, day) || latestBy(spo2Items, (item) => item.day);
  const previousActivityDay = addDays(day, -1);
  const previousActivity = chooseByDay(activityItems, previousActivityDay);

  if (!dailySleep && !sleep) {
    return {
      available: false,
      reason: 'sleep_data_not_found',
      report_date: reportDate,
      fetched_at: fetchedAt,
    };
  }

  return {
    available: true,
    type: 'oura_morning_report',
    report_date: day,
    fetched_at: fetchedAt,
    source: {
      api: 'oura',
      api_base_url: OURA_BASE_URL,
    },
    identity: {
      sleep_id: sleep?.id || null,
      daily_sleep_id: dailySleep?.id || null,
      readiness_id: readiness?.id || null,
      spo2_id: spo2?.id || null,
    },
    sleep: {
      bedtime_start: sleep?.bedtime_start || null,
      bedtime_end: sleep?.bedtime_end || null,
      type: sleep?.type || null,
      time_in_bed_seconds: numberOrNull(sleep?.time_in_bed),
      total_sleep_seconds: numberOrNull(sleep?.total_sleep_duration),
      awake_seconds: numberOrNull(sleep?.awake_time),
      deep_sleep_seconds: numberOrNull(sleep?.deep_sleep_duration),
      light_sleep_seconds: numberOrNull(sleep?.light_sleep_duration),
      rem_sleep_seconds: numberOrNull(sleep?.rem_sleep_duration),
      efficiency: numberOrNull(sleep?.efficiency),
      latency_seconds: numberOrNull(sleep?.latency),
      restless_periods: numberOrNull(sleep?.restless_periods),
      average_heart_rate: numberOrNull(sleep?.average_heart_rate),
      lowest_heart_rate: numberOrNull(sleep?.lowest_heart_rate),
      average_hrv: numberOrNull(sleep?.average_hrv),
      average_breath: numberOrNull(sleep?.average_breath),
      readiness_score_delta: numberOrNull(sleep?.readiness_score_delta),
      sleep_score_delta: numberOrNull(sleep?.sleep_score_delta),
      low_battery_alert: Boolean(sleep?.low_battery_alert),
    },
    daily_sleep: {
      score: numberOrNull(dailySleep?.score),
      timestamp: dailySleep?.timestamp || null,
      contributors: normalizeContributors(dailySleep?.contributors),
    },
    readiness: {
      score: numberOrNull(readiness?.score),
      timestamp: readiness?.timestamp || null,
      temperature_deviation: numberOrNull(readiness?.temperature_deviation),
      temperature_trend_deviation: numberOrNull(readiness?.temperature_trend_deviation),
      contributors: normalizeContributors(readiness?.contributors),
    },
    spo2: {
      average_percentage: numberOrNull(spo2?.spo2_percentage?.average),
      breathing_disturbance_index: numberOrNull(spo2?.breathing_disturbance_index),
    },
    previous_activity: previousActivity ? {
      day: previousActivity.day,
      score: numberOrNull(previousActivity.score),
      steps: numberOrNull(previousActivity.steps),
      active_calories: numberOrNull(previousActivity.active_calories),
      total_calories: numberOrNull(previousActivity.total_calories),
    } : null,
  };
}

async function ouraGet(apiKey, pathname, params, options = {}) {
  const url = new URL(`${OURA_BASE_URL}${pathname}`);
  for (const [key, value] of Object.entries(params || {})) {
    if (value != null) url.searchParams.set(key, value);
  }

  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
  });

  if (options.optional && (res.status === 403 || res.status === 404)) {
    return { data: [], unavailable: true, status: res.status };
  }

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Oura API ${pathname} failed: ${res.status} ${body.slice(0, 300)}`);
  }

  return res.json();
}

async function fetchOuraData(reportDate) {
  const apiKey = configValue('OURA_API_KEY');
  if (!apiKey) {
    throw new Error(`OURA_API_KEY が未設定です。${CONFIG_FILE} に設定してください。`);
  }

  const startDate = addDays(reportDate, -2);
  const endDate = addDays(reportDate, 1);
  const params = { start_date: startDate, end_date: endDate };

  const [
    dailySleep,
    sleep,
    readiness,
    spo2,
    activity,
  ] = await Promise.all([
    ouraGet(apiKey, '/usercollection/daily_sleep', params),
    ouraGet(apiKey, '/usercollection/sleep', params),
    ouraGet(apiKey, '/usercollection/daily_readiness', params),
    ouraGet(apiKey, '/usercollection/daily_spo2', params, { optional: true }),
    ouraGet(apiKey, '/usercollection/daily_activity', params, { optional: true }),
  ]);

  return {
    fetched_at: new Date().toISOString(),
    query: {
      report_date: reportDate,
      start_date: startDate,
      end_date: endDate,
    },
    daily_sleep: dailySleep,
    sleep,
    daily_readiness: readiness,
    daily_spo2: spo2,
    daily_activity: activity,
  };
}

function value(value, suffix = '') {
  if (value == null || value === '') return '-';
  return `${value}${suffix}`;
}

function rounded(value, digits = 1) {
  if (value == null || !Number.isFinite(value)) return null;
  return Number(value).toFixed(digits).replace(/\.0$/, '');
}

function percent(value) {
  if (value == null || !Number.isFinite(value)) return '-';
  return `${rounded(value, 1)}%`;
}

function signed(value, suffix = '') {
  if (value == null || !Number.isFinite(value)) return '-';
  const sign = value > 0 ? '+' : '';
  return `${sign}${rounded(value, 2)}${suffix}`;
}

function duration(seconds) {
  if (seconds == null || !Number.isFinite(seconds)) return '-';
  const totalMinutes = Math.max(0, Math.round(seconds / 60));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) return `${hours}時間${minutes}分`;
  if (hours > 0) return `${hours}時間`;
  return `${minutes}分`;
}

function clock(isoString) {
  if (!isoString) return '-';
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return '-';
  return new Intl.DateTimeFormat('ja-JP', {
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(date);
}

function formatReport(report) {
  const s = report.sleep || {};
  const ds = report.daily_sleep || {};
  const r = report.readiness || {};
  const sp = report.spo2 || {};
  const sc = ds.contributors || {};
  const rc = r.contributors || {};
  const activity = report.previous_activity;
  const includeActivity = configValue('OURA_REPORT_INCLUDE_ACTIVITY', 'true') !== 'false';

  const lines = [
    `*Oura 朝レポート: ${report.report_date}*`,
    `• 睡眠: ${clock(s.bedtime_start)}-${clock(s.bedtime_end)} / 実睡眠 ${duration(s.total_sleep_seconds)} / ベッド ${duration(s.time_in_bed_seconds)}`,
    `• スコア: 睡眠 ${value(ds.score)} / レディネス ${value(r.score)}`,
    `• 睡眠ステージ: 深い ${duration(s.deep_sleep_seconds)} / REM ${duration(s.rem_sleep_seconds)} / 浅い ${duration(s.light_sleep_seconds)} / 覚醒 ${duration(s.awake_seconds)}`,
    `• 睡眠品質: 効率 ${percent(s.efficiency)} / 入眠 ${duration(s.latency_seconds)} / 中途覚醒 ${value(s.restless_periods, '回')}`,
    `• 心拍・HRV: 平均HR ${value(rounded(s.average_heart_rate), ' bpm')} / 最低HR ${value(s.lowest_heart_rate, ' bpm')} / 平均HRV ${value(s.average_hrv, ' ms')} / 呼吸 ${value(rounded(s.average_breath), '/分')}`,
    `• 体温: 偏差 ${signed(r.temperature_deviation, '℃')} / トレンド ${signed(r.temperature_trend_deviation, '℃')}`,
    `• SpO2: 平均 ${percent(sp.average_percentage)} / BDI ${value(sp.breathing_disturbance_index)}`,
    `• 睡眠寄与: 合計 ${value(sc.total_sleep)} / 深い ${value(sc.deep_sleep)} / REM ${value(sc.rem_sleep)} / 効率 ${value(sc.efficiency)} / 安静 ${value(sc.restfulness)} / タイミング ${value(sc.timing)}`,
    `• レディネス寄与: HRV ${value(rc.hrv_balance)} / 安静時心拍 ${value(rc.resting_heart_rate)} / 回復 ${value(rc.recovery_index)} / 睡眠バランス ${value(rc.sleep_balance)}`,
  ];

  if (includeActivity && activity) {
    lines.push(`• 前日活動: ${activity.day} / スコア ${value(activity.score)} / 歩数 ${value(activity.steps?.toLocaleString())} / 活動cal ${value(activity.active_calories)}`);
  }

  return lines.join('\n');
}

function reportKey(report) {
  return report.identity?.sleep_id || report.identity?.daily_sleep_id || report.report_date;
}

function wasSent(report) {
  const key = reportKey(report);
  return readJsonl(EVENTS_FILE).some((event) =>
    event.type === 'morning_report_sent' &&
    event.report_date === report.report_date &&
    event.report_key === key
  );
}

async function postSlack(text) {
  const webhookUrl = slackWebhookUrl();
  if (!webhookUrl) {
    throw new Error(`Slack webhook が未設定です。${CONFIG_FILE} に OURA_SLACK_WEBHOOK_URL を設定してください。`);
  }

  const res = await fetch(webhookUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ text }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Slack投稿に失敗しました: ${res.status} ${body.slice(0, 200)}`);
  }
}

function timeToMinutes(text) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(text);
  if (!match) throw new Error(`時刻は HH:MM 形式で指定してください: ${text}`);
  return Number(match[1]) * 60 + Number(match[2]);
}

function inScheduledWindow(date = new Date()) {
  const start = timeToMinutes(configValue('OURA_REPORT_WINDOW_START', '06:00'));
  const end = timeToMinutes(configValue('OURA_REPORT_WINDOW_END', '12:00'));
  const current = date.getHours() * 60 + date.getMinutes();

  if (start <= end) return current >= start && current <= end;
  return current >= start || current <= end;
}

function parseArgs(argv) {
  const options = {
    command: 'run',
    date: null,
    dryRun: false,
    force: false,
    scheduled: false,
    json: false,
  };

  const args = [...argv];
  if (args[0] && !args[0].startsWith('-')) {
    options.command = args.shift();
  }

  while (args.length > 0) {
    const arg = args.shift();
    if (arg === '--date') options.date = args.shift();
    else if (arg.startsWith('--date=')) options.date = arg.slice('--date='.length);
    else if (arg === '--dry-run') options.dryRun = true;
    else if (arg === '--force') options.force = true;
    else if (arg === '--scheduled') options.scheduled = true;
    else if (arg === '--json') options.json = true;
    else if (arg === '--help' || arg === '-h') options.command = 'help';
    else throw new Error(`不明な引数です: ${arg}`);
  }

  return options;
}

async function run(options) {
  if (typeof fetch !== 'function') {
    throw new Error('Node.js 18以上が必要です。');
  }

  if (options.scheduled && !inScheduledWindow()) {
    console.log('Oura朝レポートの実行時間帯外なのでスキップしました。');
    return;
  }

  const reportDate = options.date || localDateString();
  const raw = await fetchOuraData(reportDate);
  const rawFile = path.join(RAW_DIR, `${reportDate}-${compactTimestamp()}.json`);
  safeJsonWrite(rawFile, raw);
  safeJsonWrite(path.join(RAW_DIR, 'latest.json'), raw);

  const report = normalizeReport({ reportDate, fetchedAt: raw.fetched_at, raw });
  if (!report.available) {
    console.log('Ouraの睡眠データがまだ見つかりません。次の定期実行で再確認します。');
    return;
  }

  safeJsonWrite(path.join(REPORT_DIR, `${report.report_date}.json`), report);
  safeJsonWrite(path.join(REPORT_DIR, 'latest.json'), report);

  if (options.json) {
    console.log(JSON.stringify(report, null, 2));
    if (options.dryRun) return;
  } else {
    console.log(formatReport(report));
  }

  if (wasSent(report) && !options.force) {
    console.log('この睡眠日のOura朝レポートは既に送信済みです。再送する場合は --force を付けてください。');
    return;
  }

  if (options.dryRun) return;

  await postSlack(formatReport(report));
  appendJsonl(EVENTS_FILE, {
    type: 'morning_report_sent',
    at: new Date().toISOString(),
    report_date: report.report_date,
    report_key: reportKey(report),
    raw_file: rawFile,
    report_file: path.join(REPORT_DIR, `${report.report_date}.json`),
    device: os.hostname(),
  });
  console.log('Oura朝レポートをSlackに送信しました。');
}

function plistEscape(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function installLaunchAgent() {
  ensureDir(STATE_DIR);
  ensureDir(path.dirname(LAUNCH_AGENT_FILE));

  const interval = Number(configValue('OURA_REPORT_START_INTERVAL_SECONDS', '1800'));
  const binPath = path.resolve(__dirname, '..', 'oura-morning-report');
  const command = `${binPath} --scheduled`;
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCH_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>${plistEscape(command)}</string>
  </array>
  <key>StartInterval</key>
  <integer>${Number.isFinite(interval) && interval > 0 ? interval : 1800}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${plistEscape(path.join(STATE_DIR, 'launchd.out.log'))}</string>
  <key>StandardErrorPath</key>
  <string>${plistEscape(path.join(STATE_DIR, 'launchd.err.log'))}</string>
</dict>
</plist>
`;

  fs.writeFileSync(LAUNCH_AGENT_FILE, plist, { mode: 0o644 });
  const domain = `gui/${process.getuid()}`;
  spawnSync('launchctl', ['bootout', domain, LAUNCH_AGENT_FILE], { stdio: 'ignore' });
  const bootstrap = spawnSync('launchctl', ['bootstrap', domain, LAUNCH_AGENT_FILE], { encoding: 'utf8' });
  if (bootstrap.status !== 0) {
    const fallback = spawnSync('launchctl', ['load', LAUNCH_AGENT_FILE], { encoding: 'utf8' });
    if (fallback.status !== 0) {
      throw new Error(`LaunchAgentの読み込みに失敗しました: ${bootstrap.stderr || fallback.stderr}`);
    }
  }
  console.log(`LaunchAgentを設定しました: ${LAUNCH_AGENT_FILE}`);
}

function uninstallLaunchAgent() {
  const domain = `gui/${process.getuid()}`;
  spawnSync('launchctl', ['bootout', domain, LAUNCH_AGENT_FILE], { stdio: 'ignore' });
  spawnSync('launchctl', ['unload', LAUNCH_AGENT_FILE], { stdio: 'ignore' });
  if (fs.existsSync(LAUNCH_AGENT_FILE)) fs.unlinkSync(LAUNCH_AGENT_FILE);
  console.log(`LaunchAgentを削除しました: ${LAUNCH_AGENT_FILE}`);
}

function status() {
  const events = readJsonl(EVENTS_FILE).filter((event) => event.type === 'morning_report_sent');
  const last = events[events.length - 1];

  console.log(`設定: ${CONFIG_FILE}`);
  console.log(`データ保存先: ${STATE_DIR}`);
  console.log(`OURA_API_KEY: ${configValue('OURA_API_KEY') ? '設定済み' : '未設定'}`);
  console.log(`Slack webhook: ${slackWebhookUrl() ? '設定済み' : '未設定'}`);
  console.log(`実行時間帯: ${configValue('OURA_REPORT_WINDOW_START', '06:00')}-${configValue('OURA_REPORT_WINDOW_END', '12:00')}`);
  console.log(`LaunchAgent: ${fs.existsSync(LAUNCH_AGENT_FILE) ? LAUNCH_AGENT_FILE : '未設定'}`);
  if (last) {
    console.log(`最終送信: ${last.report_date} at ${last.at}`);
  } else {
    console.log('最終送信: なし');
  }
}

function help() {
  console.log(`使い方:
  oura-morning-report [--dry-run] [--force] [--date YYYY-MM-DD] [--json]
  oura-morning-report status
  oura-morning-report install
  oura-morning-report uninstall

設定:
  ${CONFIG_FILE}

必要な環境変数:
  OURA_API_KEY
  OURA_SLACK_WEBHOOK_URL

任意:
  OURA_REPORT_WINDOW_START=06:00
  OURA_REPORT_WINDOW_END=12:00
  OURA_REPORT_START_INTERVAL_SECONDS=1800
  OURA_REPORT_INCLUDE_ACTIVITY=true
`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.command === 'help') return help();
  if (options.command === 'status') return status();
  if (options.command === 'install') return installLaunchAgent();
  if (options.command === 'uninstall') return uninstallLaunchAgent();
  if (options.command !== 'run') throw new Error(`不明なコマンドです: ${options.command}`);
  return run(options);
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
