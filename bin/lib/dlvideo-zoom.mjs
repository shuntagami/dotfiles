// dlvideo の Zoom クラウド録画アダプタ。
//
// yt-dlp の Zoom extractor はパスコード画面の SPA 化に追従できておらず、
// パスコード付き録画が "Unable to extract data" で失敗する（yt-dlp#16377）。
// そのため Zoom だけは Zoom の内部 API を直接たどって mp4 の URL を得る。
//
// 取得の流れ:
//   1. share / play ページを取得し window.__data__ から meetingId・fileId を読む
//   2. share URL なら share-info API を呼ぶ
//   3. componentName が need-password ならパスコードを検証してから取り直す
//   4. play-info API から mp4 の URL を得る
//
// mp4 の URL はセッション cookie と Referer の両方がないと 403 になる。
// fetch は cookie を保持しないので、リクエスト間で cookie を持ち回り、
// 呼び出し側（ffmpeg）にも同じヘッダを渡せるように返す。

export const ZOOM_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

const MAX_REDIRECTS = 5;
const REDIRECT_STATUS = new Set([301, 302, 303, 307, 308]);
const ZOOM_RECORDING_PATH = /^\/rec(?:ording)?\/(play|share)\/([\w.-]+)/;

// ---------------------------------------------------------------------------
// URL
// ---------------------------------------------------------------------------

/** zoom.us と {sub}.zoom.us（us02web など）の録画 URL を分解する。 */
export function parseZoomRecordingUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return null;

  const hostname = parsed.hostname.toLowerCase();
  const isZoomHost = hostname === "zoom.us" ||
    /^[^.]+\.zoom\.us$/.test(hostname);
  if (!isZoomHost) return null;

  const match = ZOOM_RECORDING_PATH.exec(parsed.pathname);
  if (!match || !match[2]) return null;

  return {
    baseUrl: `${parsed.protocol}//${parsed.host}/`,
    type: match[1],
    id: match[2],
  };
}

export function isZoomRecordingUrl(url) {
  return parseZoomRecordingUrl(url) !== null;
}

// ---------------------------------------------------------------------------
// Cookie を持ち回る fetch
// ---------------------------------------------------------------------------

class CookieJar {
  #cookies = new Map();

  absorb(response) {
    for (const setCookie of response.headers.getSetCookie()) {
      const pair = setCookie.split(";")[0];
      if (!pair) continue;
      const separator = pair.indexOf("=");
      if (separator <= 0) continue;
      const name = pair.slice(0, separator).trim();
      const value = pair.slice(separator + 1).trim();
      if (!name) continue;
      if (value === "" || value === "deleted") {
        this.#cookies.delete(name);
        continue;
      }
      this.#cookies.set(name, value);
    }
  }

  header() {
    return Array.from(this.#cookies, ([name, value]) => `${name}=${value}`)
      .join("; ");
  }
}

/** リダイレクト途中の Set-Cookie も拾うため、リダイレクトは自前で追う。 */
async function fetchWithJar(jar, url, init = {}) {
  const { referer, ...requestInit } = init;
  let currentUrl = url;
  let method = requestInit.method ?? "GET";
  let body = requestInit.body;

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const headers = new Headers(requestInit.headers);
    headers.set("User-Agent", ZOOM_USER_AGENT);
    if (referer) headers.set("Referer", referer);
    const cookieHeader = jar.header();
    if (cookieHeader) headers.set("Cookie", cookieHeader);

    const response = await fetch(currentUrl, {
      ...requestInit,
      method,
      body,
      headers,
      redirect: "manual",
    });
    jar.absorb(response);

    if (!REDIRECT_STATUS.has(response.status)) return response;

    const location = response.headers.get("location");
    if (!location) return response;

    await response.body?.cancel();
    currentUrl = new URL(location, currentUrl).toString();
    if (
      method !== "GET" && response.status !== 307 && response.status !== 308
    ) {
      method = "GET";
      body = undefined;
    }
  }

  throw new Error("Zoom へのリダイレクトが多すぎます");
}

// ---------------------------------------------------------------------------
// window.__data__ の読み取り
// ---------------------------------------------------------------------------

const ESCAPE_SEQUENCES = {
  n: "\n",
  r: "\r",
  t: "\t",
  b: "\b",
  f: "\f",
  v: "\v",
  "0": "\0",
};
const IDENTIFIER = /^[A-Za-z_$][\w$]*/;

function isWhitespace(character) {
  return character !== undefined && /\s/.test(character);
}

function skipWhitespace(text, index) {
  let cursor = index;
  while (isWhitespace(text[cursor])) cursor++;
  return cursor;
}

function readQuoted(text, start) {
  const quote = text[start];
  let cursor = start + 1;
  let value = "";

  while (cursor < text.length) {
    const character = text[cursor];
    if (character === "\\") {
      const escaped = text[cursor + 1];
      if (escaped === undefined) break;
      if (escaped === "u") {
        const code = text.slice(cursor + 2, cursor + 6);
        if (/^[0-9a-fA-F]{4}$/.test(code)) {
          value += String.fromCharCode(parseInt(code, 16));
          cursor += 6;
          continue;
        }
      }
      value += ESCAPE_SEQUENCES[escaped] ?? escaped;
      cursor += 2;
      continue;
    }
    if (character === quote) return { value, next: cursor + 1 };
    value += character;
    cursor++;
  }

  throw new Error("Zoom ページのデータ中で文字列が閉じていません");
}

function skipBalanced(text, start) {
  const open = text[start];
  const close = open === "{" ? "}" : "]";
  let depth = 0;
  let cursor = start;

  while (cursor < text.length) {
    const character = text[cursor];
    if (character === '"' || character === "'") {
      cursor = readQuoted(text, cursor).next;
      continue;
    }
    if (character === open) depth++;
    else if (character === close) {
      depth--;
      if (depth === 0) return cursor + 1;
    }
    cursor++;
  }

  throw new Error("Zoom ページのデータ中で括弧が閉じていません");
}

function parseBareValue(raw) {
  if (raw === "true") return true;
  if (raw === "false") return false;
  if (raw === "null" || raw === "undefined") return null;
  if (raw !== "" && /^-?\d+(?:\.\d+)?$/.test(raw)) return Number(raw);
  return raw;
}

/**
 * 録画ページの `window.__data__ = { ... }` からトップレベルのスカラー値だけを取り出す。
 * JSON ではなく JS のオブジェクトリテラル（キーはクォート無し、値はクォート混在）なので
 * JSON.parse は使えない。必要なのは meetingId / fileId などの文字列だけなので、
 * ネストした値は読み飛ばす。
 */
export function parseZoomPageData(html, context) {
  const marker = /window\.__data__\s*=\s*\{/.exec(html);
  if (!marker) {
    throw new Error(`Zoom の ${context} ページに録画データが見つかりません`);
  }

  const data = {};
  let cursor = marker.index + marker[0].length;

  while (true) {
    cursor = skipWhitespace(html, cursor);
    const character = html[cursor];

    if (character === undefined) {
      throw new Error(
        `Zoom の ${context} ページの録画データが途中で切れています`,
      );
    }
    if (character === "}") break;
    if (character === ",") {
      cursor++;
      continue;
    }

    let key;
    if (character === '"' || character === "'") {
      const quoted = readQuoted(html, cursor);
      key = quoted.value;
      cursor = quoted.next;
    } else {
      const identifier = IDENTIFIER.exec(html.slice(cursor));
      if (!identifier) {
        throw new Error(`Zoom の ${context} ページの録画データを読めません`);
      }
      key = identifier[0];
      cursor += identifier[0].length;
    }

    cursor = skipWhitespace(html, cursor);
    if (html[cursor] !== ":") {
      throw new Error(
        `Zoom の ${context} ページの録画データの形が想定と違います`,
      );
    }
    cursor = skipWhitespace(html, cursor + 1);

    const valueStart = html[cursor];
    if (valueStart === undefined) {
      throw new Error(
        `Zoom の ${context} ページの録画データが途中で切れています`,
      );
    }
    if (valueStart === "{" || valueStart === "[") {
      cursor = skipBalanced(html, cursor);
      continue;
    }
    if (valueStart === '"' || valueStart === "'") {
      const quoted = readQuoted(html, cursor);
      data[key] = quoted.value;
      cursor = quoted.next;
      continue;
    }

    let end = cursor;
    while (end < html.length && html[end] !== "," && html[end] !== "}") end++;
    data[key] = parseBareValue(html.slice(cursor, end).trim());
    cursor = end;
  }

  return data;
}

function readStringField(data, key) {
  const value = data[key];
  return typeof value === "string" && value !== "" ? value : undefined;
}

// ---------------------------------------------------------------------------
// Zoom API
// ---------------------------------------------------------------------------

async function fetchZoomJson(jar, url, baseUrl, init = {}) {
  const response = await fetchWithJar(jar, url, {
    ...init,
    referer: baseUrl,
    headers: {
      Accept: "application/json, text/plain, */*",
      ...(init.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `Zoom API がエラーを返しました (status ${response.status})`,
    );
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Zoom API の応答が JSON ではありません");
  }
}

function shareInfoUrl(baseUrl, meetingId) {
  const url = new URL(
    `nws/recording/1.0/play/share-info/${encodeURIComponent(meetingId)}`,
    baseUrl,
  );
  url.searchParams.set("originDomain", baseUrl.replace(/\/$/, ""));
  url.searchParams.set("accessLevel", "meeting");
  return url.toString();
}

function playInfoUrl(baseUrl, fileId, isShare) {
  const url = new URL(
    `nws/recording/1.0/play/info/${encodeURIComponent(fileId)}`,
    baseUrl,
  );
  if (isShare) url.searchParams.set("continueMode", "true");
  return url.toString();
}

/** パスコードを検証する。成功すると認証済みの cookie が jar に入る。 */
async function validatePasscode(jar, baseUrl, params) {
  if (!params.password) {
    throw new Error(
      "この Zoom 録画にはパスコードが必要です。--password で渡してください。",
    );
  }
  const endpointType = params.endpointType || "meeting";
  const url = new URL(
    `nws/recording/1.0/validate-${endpointType}-passwd`,
    baseUrl,
  ).toString();
  const body = new URLSearchParams({
    id: params.id,
    passwd: params.password,
    action: params.action || "viewdetailpage",
  });
  const response = await fetchZoomJson(jar, url, baseUrl, {
    method: "POST",
    body: body.toString(),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
  });
  if (!response.status) {
    throw new Error(response.errorMessage || "Zoom のパスコードが違います");
  }
}

function assertPlayable(result) {
  const componentName = result.componentName;
  if (!componentName) return;
  if (componentName === "vanity-url-check") {
    throw new Error(
      result.message ||
        "この Zoom 録画はメール認証が必要で、このツールでは取得できません",
    );
  }
  if (componentName === "need-password") {
    throw new Error(
      "この Zoom 録画にはパスコードが必要です。--password で渡してください。",
    );
  }
  throw new Error(
    result.message || `Zoom がこの録画を再生できません (${componentName})`,
  );
}

function parseFileSizeInMB(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value * 1024 * 1024);
  }
  if (typeof value !== "string") return undefined;
  const match = /(-?\d+(?:\.\d+)?)/.exec(value);
  if (!match || !match[1]) return undefined;
  const megabytes = Number(match[1]);
  return Number.isFinite(megabytes)
    ? Math.round(megabytes * 1024 * 1024)
    : undefined;
}

async function fetchPageText(jar, url, baseUrl) {
  const response = await fetchWithJar(jar, url, { referer: baseUrl });
  if (!response.ok) {
    throw new Error(
      `Zoom の録画ページを開けません (status ${response.status})`,
    );
  }
  return await response.text();
}

// ---------------------------------------------------------------------------
// 解決
// ---------------------------------------------------------------------------

/**
 * 録画 URL から mp4 の URL とメタデータを解決する。
 * 戻り値の referer / cookieHeader / userAgent を ffmpeg の -headers に渡すこと。
 */
export async function resolveZoomRecording(recordingUrl, password) {
  const parsed = parseZoomRecordingUrl(recordingUrl);
  if (!parsed) {
    throw new Error(`Zoom の録画 URL ではありません: ${recordingUrl}`);
  }

  const isShare = parsed.type === "share";
  const jar = new CookieJar();

  let baseUrl = parsed.baseUrl;
  let pageUrl = recordingUrl;
  let pageType = parsed.type;
  let page = await fetchPageText(jar, pageUrl, baseUrl);
  let pageData = parseZoomPageData(page, pageType);
  let shareResult = {};

  if (isShare) {
    const meetingId = readStringField(pageData, "meetingId");
    if (meetingId) {
      let response = await fetchZoomJson(
        jar,
        shareInfoUrl(baseUrl, meetingId),
        baseUrl,
      );
      let result = response.result ?? {};

      if (result.componentName === "need-password") {
        await validatePasscode(jar, baseUrl, {
          endpointType: result.useWhichPasswd ??
            readStringField(pageData, "useWhichPasswd"),
          id: result.meetingId ?? meetingId,
          action: result.action,
          password,
        });
        response = await fetchZoomJson(
          jar,
          shareInfoUrl(baseUrl, meetingId),
          baseUrl,
        );
        result = response.result ?? {};
      }

      shareResult = result;

      const redirectUrl = result.redirectUrl
        ? new URL(result.redirectUrl, baseUrl).toString()
        : null;
      const redirectParts = redirectUrl
        ? parseZoomRecordingUrl(redirectUrl)
        : null;

      if (redirectParts && redirectUrl) {
        baseUrl = redirectParts.baseUrl;
        pageUrl = redirectUrl;
        pageType = redirectParts.type;
        page = await fetchPageText(jar, pageUrl, baseUrl);
        pageData = parseZoomPageData(page, pageType);
      } else {
        assertPlayable(result);
        throw new Error("Zoom が再生ページを返しませんでした");
      }
    }
  }

  const fileId = readStringField(pageData, "fileId") ?? shareResult.fileId;
  if (!fileId) {
    throw new Error("Zoom の録画ページから fileId を取れませんでした");
  }

  let playResponse = await fetchZoomJson(
    jar,
    playInfoUrl(baseUrl, fileId, isShare),
    baseUrl,
  );
  let playResult = playResponse.result ?? {};

  if (playResult.componentName === "need-password") {
    await validatePasscode(jar, baseUrl, {
      endpointType: playResult.useWhichPasswd ??
        readStringField(pageData, "useWhichPasswd"),
      id: playResult.meetingId ?? playResult.fileId ?? fileId,
      action: playResult.action,
      password,
    });
    playResponse = await fetchZoomJson(
      jar,
      playInfoUrl(baseUrl, fileId, isShare),
      baseUrl,
    );
    playResult = playResponse.result ?? {};
  }

  assertPlayable(playResult);
  if (playResponse.errorMessage) throw new Error(playResponse.errorMessage);

  // 画面共有込みの映像を最優先にする
  const mediaUrl = playResult.viewMp4WithshareUrl || playResult.viewMp4Url ||
    playResult.shareMp4Url;
  if (!mediaUrl) {
    throw new Error("Zoom がダウンロードできる録画ファイルを返しませんでした");
  }

  const duration =
    typeof playResult.duration === "number" && playResult.duration > 0
      ? playResult.duration
      : undefined;

  return {
    id: parsed.id,
    title: playResult.meet?.topic?.trim() || parsed.id,
    duration,
    size: parseFileSizeInMB(playResult.recording?.fileSizeInMB),
    mediaUrl,
    referer: baseUrl,
    cookieHeader: jar.header(),
    userAgent: ZOOM_USER_AGENT,
  };
}
