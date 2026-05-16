#!/usr/bin/env node

const fs = require('fs');
const os = require('os');
const path = require('path');

const HOME = os.homedir();
const PIPE_NAME = 'meeting-coach';
const PIPE_DIR = path.join(HOME, '.screenpipe', 'pipes', PIPE_NAME);
const OUTPUT_DIR = process.env.MEETING_COACH_OUTPUT_DIR || path.join(PIPE_DIR, 'output');
const ENV_FILE = path.join(PIPE_DIR, '.env');
const DEFAULT_PROMPT_CORE = path.join(
  HOME,
  'projects',
  'egt',
  'prompts',
  'ビジネス会話添削prompt.md'
);
const DEFAULT_SELF_DESCRIPTION = '黒い眼鏡、黒い服、センターパートの男性';
const API_BASE =
  process.env.SCREENPIPE_LOCAL_API_URL ||
  process.env.SCREENPIPE_API_BASE_URL ||
  'http://localhost:3030';
const GEMINI_UPLOAD_BASE = 'https://generativelanguage.googleapis.com/upload/v1beta';
const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com/v1beta';

function parseArgs(argv) {
  const args = {
    meetingId: null,
    since: process.env.MEETING_COACH_SINCE || '12h ago',
    force: process.env.MEETING_COACH_FORCE === '1',
    dryRun: false,
    video:
      process.env.MEETING_COACH_VIDEO === '0' || process.env.MEETING_COACH_VIDEO === 'false'
        ? false
        : true,
    requireVideo:
      process.env.MEETING_COACH_REQUIRE_VIDEO === '1' ||
      process.env.MEETING_COACH_REQUIRE_VIDEO === 'true',
    fps: Number(process.env.MEETING_COACH_VIDEO_FPS || '1'),
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--meeting-id') args.meetingId = Number(argv[++i]);
    else if (arg === '--since') args.since = argv[++i];
    else if (arg === '--force') args.force = true;
    else if (arg === '--dry-run') args.dryRun = true;
    else if (arg === '--no-video') args.video = false;
    else if (arg === '--video') args.video = true;
    else if (arg === '--require-video') args.requireVideo = true;
    else if (arg === '--allow-text-only') args.requireVideo = false;
    else if (arg === '--fps') args.fps = Number(argv[++i]);
    else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    }
  }

  return args;
}

function printHelp() {
  console.log(`Usage: screenpipe-meeting-coach [options]

Options:
  --meeting-id <id>  Analyze a specific screenpipe meeting
  --since <range>    Lookback for auto-selecting the latest ended meeting (default: 12h ago)
  --force            Reprocess a meeting even if it was already handled
  --no-video         Skip screen video export and Gemini video upload
  --video            Force video export when GEMINI_API_KEY exists
  --require-video    Fail instead of falling back when video export/upload fails
  --allow-text-only  Allow transcript-only fallback even if MEETING_COACH_REQUIRE_VIDEO=1
  --fps <number>     Export FPS for screen video (default: 1)
  --dry-run          Build bundle and prompt, but do not call Gemini

Secrets:
  Put GEMINI_API_KEY in ${ENV_FILE}
`);
}

function loadEnvFile(file) {
  if (!fs.existsSync(file)) return;
  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim().replace(/^export\s+/, '');
    if (!line || line.startsWith('#')) continue;
    const idx = line.indexOf('=');
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim();
    value = value.replace(/^['"]|['"]$/g, '');
    if (!process.env[key]) process.env[key] = value;
  }
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function readTextIfExists(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

function writeJson(file, data) {
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function sanitizeName(value) {
  return String(value || '')
    .replace(/[^\w.-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function localDateSlug(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    '-',
    pad(date.getHours()),
    pad(date.getMinutes()),
  ].join('');
}

function apiHeaders(extra = {}) {
  const headers = { ...extra };
  if (process.env.SCREENPIPE_LOCAL_API_KEY) {
    headers.Authorization = `Bearer ${process.env.SCREENPIPE_LOCAL_API_KEY}`;
  }
  return headers;
}

async function apiGet(pathname, params = {}) {
  const url = new URL(pathname, API_BASE);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }

  const res = await fetch(url, { headers: apiHeaders() });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    if (res.status === 403 && !process.env.SCREENPIPE_LOCAL_API_KEY) {
      throw new Error(
        `screenpipe API auth is enabled. Run from a Screenpipe pipe, or put SCREENPIPE_LOCAL_API_KEY=... in ${ENV_FILE}. Original response: ${body}`
      );
    }
    throw new Error(`screenpipe GET ${url.pathname} failed: HTTP ${res.status} ${body}`);
  }
  return res.json();
}

async function apiPost(pathname, body) {
  const res = await fetch(new URL(pathname, API_BASE), {
    method: 'POST',
    headers: apiHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`screenpipe POST ${pathname} failed: HTTP ${res.status} ${text}`);
  }
  return res.json().catch(() => ({}));
}

async function notify(title, body, actions = []) {
  if (process.env.MEETING_COACH_NOTIFY === '0' || process.env.MEETING_COACH_NOTIFY === 'false') {
    return;
  }
  try {
    await fetch('http://localhost:11435/notify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, body, actions }),
    });
  } catch {
    // Notification server is best-effort. The report still exists on disk.
  }
}

function getMeetingStart(meeting) {
  return meeting.meeting_start || meeting.meetingStart || meeting.start_time;
}

function getMeetingEnd(meeting) {
  return meeting.meeting_end || meeting.meetingEnd || meeting.end_time;
}

function durationMinutes(meeting) {
  const start = Date.parse(getMeetingStart(meeting));
  const end = Date.parse(getMeetingEnd(meeting));
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  return Math.max(0, Math.round((end - start) / 60000));
}

function processedKey(meeting) {
  return `${meeting.id}:${getMeetingEnd(meeting) || ''}`;
}

async function selectMeeting(args, processed) {
  if (args.meetingId) {
    return apiGet(`/meetings/${args.meetingId}`);
  }

  const meetings = await apiGet('/meetings', {
    start_time: args.since,
    end_time: 'now',
    limit: 30,
  });

  const candidates = meetings
    .filter((meeting) => meeting.id && getMeetingStart(meeting) && getMeetingEnd(meeting))
    .filter((meeting) => durationMinutes(meeting) === null || durationMinutes(meeting) >= 2)
    .sort((a, b) => Date.parse(getMeetingEnd(b)) - Date.parse(getMeetingEnd(a)));

  if (!args.force) {
    const fresh = candidates.find((meeting) => !processed[processedKey(meeting)]);
    if (fresh) return fresh;
  }

  return candidates[0] || null;
}

async function fetchTranscript(meeting) {
  try {
    const segments = await apiGet(`/meetings/${meeting.id}/transcript`);
    if (Array.isArray(segments) && segments.length > 0) return segments;
  } catch {
    // Fall back to search below.
  }

  const data = await apiGet('/search', {
    content_type: 'audio',
    start_time: getMeetingStart(meeting),
    end_time: getMeetingEnd(meeting),
    limit: 200,
  });
  return Array.isArray(data.data) ? data.data : [];
}

async function fetchScreenContext(meeting) {
  const data = await apiGet('/search', {
    content_type: 'all',
    start_time: getMeetingStart(meeting),
    end_time: getMeetingEnd(meeting),
    limit: 80,
  });
  return Array.isArray(data.data) ? data.data : [];
}

function segmentText(segment) {
  return (
    segment.transcript ||
    segment.transcription ||
    segment.text ||
    segment.content?.transcript ||
    segment.content?.transcription ||
    segment.content?.text ||
    ''
  ).trim();
}

function segmentSpeaker(segment) {
  return (
    segment.speakerName ||
    segment.speaker_name ||
    segment.content?.speaker_name ||
    segment.content?.speakerName ||
    segment.speaker_id ||
    segment.speakerId ||
    segment.content?.speaker_id ||
    ''
  );
}

function segmentDeviceType(segment) {
  return (
    segment.deviceType ||
    segment.device_type ||
    segment.content?.device_type ||
    segment.content?.deviceType ||
    ''
  );
}

function segmentTime(segment) {
  return (
    segment.capturedAt ||
    segment.captured_at ||
    segment.timestamp ||
    segment.content?.timestamp ||
    segment.content?.captured_at ||
    ''
  );
}

function transcriptMarkdown(segments) {
  return segments
    .map((segment) => {
      const text = segmentText(segment);
      if (!text) return null;
      const time = segmentTime(segment);
      const speaker = segmentSpeaker(segment) || segmentDeviceType(segment) || 'unknown';
      return `- ${time ? `[${time}] ` : ''}${speaker}: ${text}`;
    })
    .filter(Boolean)
    .join('\n');
}

function truncate(value, maxChars) {
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  if (text.length <= maxChars) return text;
  return `${text.slice(0, maxChars)}\n...[truncated ${text.length - maxChars} chars]`;
}

function countMatches(text, patterns) {
  return patterns.reduce((sum, pattern) => sum + (text.match(pattern) || []).length, 0);
}

function buildMetrics(segments) {
  const inputSegments = segments.filter((segment) => segmentDeviceType(segment) === 'input');
  const outputSegments = segments.filter((segment) => segmentDeviceType(segment) === 'output');
  const ownText = inputSegments.map(segmentText).join('\n');
  const allText = segments.map(segmentText).join('\n');
  const ownChars = ownText.length;
  const allChars = allText.length || 1;
  const fillerPatterns = [
    /えっと/g,
    /えー/g,
    /あの/g,
    /その/g,
    /なんか/g,
    /まあ/g,
    /ちょっと/g,
    /\bum+\b/gi,
    /\buh+\b/gi,
    /\blike\b/gi,
    /\byou know\b/gi,
  ];

  const longTurns = inputSegments
    .map((segment) => ({
      time: segmentTime(segment),
      chars: segmentText(segment).length,
      text: segmentText(segment).slice(0, 240),
    }))
    .filter((item) => item.chars >= 300)
    .slice(0, 10);

  return {
    segments_total: segments.length,
    input_segments: inputSegments.length,
    output_segments: outputSegments.length,
    own_talk_ratio_by_chars: Number((ownChars / allChars).toFixed(2)),
    own_chars: ownChars,
    all_chars: allChars,
    filler_count: countMatches(ownText, fillerPatterns),
    question_count: countMatches(ownText, [/？/g, /\?/g]),
    long_turns: longTurns,
  };
}

function extractFrameId(result) {
  return (
    result.frame_id ||
    result.frameId ||
    result.content?.frame_id ||
    result.content?.frameId ||
    result.content?.frame?.id ||
    null
  );
}

async function collectFrameIds(meeting) {
  const data = await apiGet('/search', {
    content_type: 'ocr',
    start_time: getMeetingStart(meeting),
    end_time: getMeetingEnd(meeting),
    limit: Number(process.env.MEETING_COACH_MAX_SEARCH_RESULTS || 10000),
  });
  const seen = new Set();
  const frameIds = [];
  for (const result of data.data || []) {
    const id = Number(extractFrameId(result));
    if (Number.isFinite(id) && !seen.has(id)) {
      seen.add(id);
      frameIds.push(id);
    }
  }
  frameIds.sort((a, b) => a - b);
  const maxFrames = Number(process.env.MEETING_COACH_MAX_FRAMES || 1800);
  if (frameIds.length <= maxFrames) return frameIds;

  const sampled = [];
  const step = frameIds.length / maxFrames;
  for (let i = 0; i < maxFrames; i += 1) sampled.push(frameIds[Math.floor(i * step)]);
  return [...new Set(sampled)];
}

async function exportVideo(meeting, outPath, fps) {
  const frameIds = await collectFrameIds(meeting);
  if (frameIds.length === 0) return null;

  const wsBase = API_BASE.replace(/^http/, 'ws');
  const url = new URL('/frames/export', wsBase);
  url.searchParams.set('fps', String(fps));
  if (process.env.SCREENPIPE_LOCAL_API_KEY) {
    url.searchParams.set('token', process.env.SCREENPIPE_LOCAL_API_KEY);
  }

  ensureDir(path.dirname(outPath));

  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const timeoutMs = Number(process.env.MEETING_COACH_EXPORT_TIMEOUT_MS || 600000);
    const timer = setTimeout(() => {
      try {
        ws.close();
      } catch {
        // ignore
      }
      reject(new Error(`video export timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({ frame_ids: frameIds }));
    });

    ws.addEventListener('message', (event) => {
      let message;
      try {
        message = JSON.parse(String(event.data));
      } catch {
        return;
      }

      if (message.status === 'completed' && message.video_data) {
        clearTimeout(timer);
        fs.writeFileSync(outPath, Buffer.from(message.video_data));
        ws.close();
        resolve({ path: outPath, frame_count: frameIds.length });
      } else if (message.status === 'error') {
        clearTimeout(timer);
        ws.close();
        reject(new Error(message.error || 'video export failed'));
      }
    });

    ws.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('video export websocket error'));
    });
  });
}

async function uploadGeminiFile(filePath, mimeType) {
  const apiKey = process.env.GEMINI_API_KEY;
  const stat = fs.statSync(filePath);
  const start = await fetch(`${GEMINI_UPLOAD_BASE}/files`, {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(stat.size),
      'X-Goog-Upload-Header-Content-Type': mimeType,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ file: { display_name: path.basename(filePath) } }),
  });
  if (!start.ok) {
    throw new Error(`Gemini upload start failed: HTTP ${start.status} ${await start.text()}`);
  }

  const uploadUrl = start.headers.get('x-goog-upload-url');
  if (!uploadUrl) throw new Error('Gemini upload URL missing');

  const finalize = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'Content-Length': String(stat.size),
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    },
    body: fs.createReadStream(filePath),
    duplex: 'half',
  });
  if (!finalize.ok) {
    throw new Error(`Gemini upload finalize failed: HTTP ${finalize.status} ${await finalize.text()}`);
  }

  const uploaded = await finalize.json();
  let file = uploaded.file || uploaded;
  for (let i = 0; i < 30 && file.state && file.state !== 'ACTIVE'; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    const poll = await fetch(`${GEMINI_API_BASE}/${file.name}`, {
      headers: { 'x-goog-api-key': apiKey },
    });
    if (!poll.ok) break;
    file = await poll.json();
  }

  return file;
}

async function callGemini(prompt, videoFile) {
  const apiKey = process.env.GEMINI_API_KEY;
  const model = process.env.GEMINI_MODEL || 'gemini-3-flash-preview';
  const parts = [{ text: prompt }];

  if (videoFile) {
    parts.push({
      file_data: {
        mime_type: videoFile.mimeType || videoFile.mime_type || 'video/mp4',
        file_uri: videoFile.uri,
      },
    });
  }

  const res = await fetch(`${GEMINI_API_BASE}/models/${model}:generateContent`, {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0.2,
      },
    }),
  });

  if (!res.ok) {
    throw new Error(`Gemini generateContent failed: HTTP ${res.status} ${await res.text()}`);
  }

  const json = await res.json();
  const text = (json.candidates || [])
    .flatMap((candidate) => candidate.content?.parts || [])
    .map((part) => part.text || '')
    .join('\n')
    .trim();

  if (!text) throw new Error(`Gemini returned no text: ${JSON.stringify(json).slice(0, 500)}`);
  return text;
}

function buildPrompt(meeting, transcriptMd, context, metrics, videoPath, promptCore, promptCorePath) {
  const title = meeting.title || '(no title)';
  const attendees = meeting.attendees || '(unknown)';
  const selfDescription = process.env.MEETING_COACH_SELF_DESCRIPTION || DEFAULT_SELF_DESCRIPTION;
  return `あなたは会議での話し方を改善するためのコーチです。

次の会議データを分析し、本人が次回すぐ改善できるフィードバックを書いてください。
人格評価ではなく、観察可能な行動と改善案に絞ってください。

以下の「プロンプト核」を最優先の評価思想・出力形式として使ってください。
テンプレート変数は、この実行データで置き換えて解釈してください。

## プロンプト核
source: ${promptCorePath || '(not found)'}

${promptCore || '(プロンプト核ファイルが見つかりません。デフォルトの会議コーチ形式で続行してください。)'}

## 本人識別
- transcript上の「私」は、device_type=input のマイク音声として扱う。
- 動画上の本人は「${selfDescription}」として探す。
- 動画に複数人がいる場合、この特徴に最も一致する人物だけを本人として評価する。
- 確信できない場合は、動画所見を断定せず transcript 根拠を優先する。

## 会議メタデータ
- id: ${meeting.id}
- title: ${title}
- type: business meeting
- expected_output: 会議目的の明確化、結論確定、宿題割当、次回改善行動
- app: ${meeting.meeting_app || ''}
- start: ${getMeetingStart(meeting)}
- end: ${getMeetingEnd(meeting)}
- duration_minutes: ${durationMinutes(meeting)}
- attendees: ${attendees}
- video: ${videoPath || '(not included)'}

## 自動計測
\`\`\`json
${JSON.stringify(metrics, null, 2)}
\`\`\`

## 分析観点
- 自分の発言は長すぎないか
- 相手の発言を受けてから話しているか
- 質問ができているか
- 説明が抽象的すぎないか
- フィラーや曖昧表現が多いか
- 会議の目的に対して前に進める発言ができているか
- 動画がある場合: 表情、視線、姿勢、聞いている態度、画面上の反応も見る

## 出力フォーマット

# Meeting Coach

## まず直す1つ
次回の会議で最優先で直す行動を1つだけ。

## 良かった点
- 具体的に3つまで。

## 改善点
- 具体的に3つまで。
- それぞれ、該当する発言や時間の根拠を付ける。

## 長すぎた/曖昧だった発言
- 原文または要約
- より短い言い換え

## 質問の質
- 使えた質問
- 次回使うべき質問例

## ビジネス会話添削
- プロンプト核の「スコアリング」「フィラー・弱語カウント」「具体的な添削結果」「置換辞書」「DECIDE回し方ログ」「全体的に一言」「明日からの行動3本」を必ず含める。
- 時刻ごとの添削は、transcriptの時刻または動画タイムスタンプに紐づける。
- セリフ例は、そのまま次回の会議で読み上げられる日本語で書く。

## 次回の練習
- 会議前に読む1行
- 会議中に守るルールを3つ

## 根拠
- transcript / video / screen context から見えた根拠。

## Transcript
${truncate(transcriptMd || '(empty)', Number(process.env.MEETING_COACH_MAX_TRANSCRIPT_CHARS || 80000))}

## Screen context
\`\`\`json
${truncate(context, Number(process.env.MEETING_COACH_MAX_CONTEXT_CHARS || 30000))}
\`\`\`
`;
}

async function main() {
  loadEnvFile(ENV_FILE);
  const args = parseArgs(process.argv.slice(2));
  ensureDir(OUTPUT_DIR);

  const processedFile = path.join(OUTPUT_DIR, 'processed.json');
  const processed = readJson(processedFile, {});
  const meeting = await selectMeeting(args, processed);
  if (!meeting) {
    console.log(JSON.stringify({ status: 'no_meeting', message: 'No ended meeting found.' }));
    return;
  }

  const key = processedKey(meeting);
  if (!args.force && processed[key]) {
    console.log(
      JSON.stringify({
        status: 'skipped',
        reason: 'already_processed',
        meeting_id: meeting.id,
        report_path: processed[key].report_path,
      })
    );
    return;
  }

  const slug = `${localDateSlug(new Date(Date.parse(getMeetingEnd(meeting) || Date.now())))}-${meeting.id}-${sanitizeName(meeting.title || meeting.meeting_app || 'meeting')}`;
  const bundlePath = path.join(OUTPUT_DIR, `${slug}-bundle.json`);
  const promptPath = path.join(OUTPUT_DIR, `${slug}-prompt.md`);
  const reportPath = path.join(OUTPUT_DIR, `${slug}-feedback.md`);
  const latestPath = path.join(OUTPUT_DIR, 'latest.md');
  const videoPath = path.join(OUTPUT_DIR, `${slug}.mp4`);

  const transcript = await fetchTranscript(meeting);
  const context = await fetchScreenContext(meeting);
  const transcriptMd = transcriptMarkdown(transcript);
  const metrics = buildMetrics(transcript);
  const promptCorePath = process.env.MEETING_COACH_PROMPT_CORE || DEFAULT_PROMPT_CORE;
  const promptCore = readTextIfExists(promptCorePath);

  let video = null;
  let geminiFile = null;
  if (args.video && process.env.GEMINI_API_KEY && !args.dryRun) {
    try {
      video = await exportVideo(meeting, videoPath, args.fps);
      if (!video) throw new Error('no screen frames were available for video export');
      geminiFile = await uploadGeminiFile(video.path, 'video/mp4');
    } catch (error) {
      if (args.requireVideo) {
        throw new Error(`video analysis required but unavailable: ${error.message}`);
      }
      console.error(`video step skipped: ${error.message}`);
    }
  }

  const prompt = buildPrompt(
    meeting,
    transcriptMd,
    context,
    metrics,
    video?.path,
    promptCore,
    promptCorePath
  );
  const bundle = {
    generated_at: new Date().toISOString(),
    meeting,
    metrics,
    prompt_core_path: promptCorePath,
    self_description: process.env.MEETING_COACH_SELF_DESCRIPTION || DEFAULT_SELF_DESCRIPTION,
    transcript,
    context,
    video,
    gemini_file: geminiFile,
    prompt_path: promptPath,
    report_path: reportPath,
  };

  writeJson(bundlePath, bundle);
  fs.writeFileSync(promptPath, prompt);

  let report = null;
  if (process.env.GEMINI_API_KEY && !args.dryRun) {
    report = await callGemini(prompt, geminiFile);
    fs.writeFileSync(reportPath, `${report.trim()}\n`);
    fs.copyFileSync(reportPath, latestPath);

    processed[key] = {
      meeting_id: meeting.id,
      meeting_end: getMeetingEnd(meeting),
      processed_at: new Date().toISOString(),
      report_path: reportPath,
      bundle_path: bundlePath,
      video_path: video?.path || null,
    };
    writeJson(processedFile, processed);

    await notify('Meeting Coach', `フィードバックを作成しました。\n\n[開く](${reportPath})`);
    console.log(
      JSON.stringify({
        status: 'completed',
        meeting_id: meeting.id,
        report_path: reportPath,
        latest_path: latestPath,
        bundle_path: bundlePath,
        prompt_path: promptPath,
        video_path: video?.path || null,
      })
    );
    return;
  }

  await notify(
    'Meeting Coach',
    `Gemini実行用の入力を作成しました。GEMINI_API_KEYを設定すると自動分析できます。\n\n[prompt](${promptPath})`
  );
  console.log(
    JSON.stringify({
      status: 'needs_ai',
      reason: args.dryRun ? 'dry_run' : 'missing_gemini_api_key',
      meeting_id: meeting.id,
      bundle_path: bundlePath,
      prompt_path: promptPath,
      report_path: reportPath,
      latest_path: latestPath,
      processed_file: processedFile,
      processed_key: key,
    })
  );
}

main().catch(async (error) => {
  await notify('Meeting Coach failed', error.message);
  console.error(error.stack || error.message);
  process.exit(1);
});
