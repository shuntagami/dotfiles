(() => {
  "use strict";

  const config = __VIMEO_REVIEW_CONFIG__;
  const stateKey = "__vimeoReviewCommentsBatch";
  const endpointPath = `/videos/${config.videoId}/private_comments`;
  const originalFetch = window.fetch.bind(window);
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  if (["armed", "checking", "running"].includes(window[stateKey]?.status)) {
    throw new Error("vimeo-review-comments is already armed or running");
  }

  const state = {
    version: 1,
    status: "armed",
    inputCount: config.items.length,
    pending: config.items.length,
    posted: 0,
    skippedExisting: 0,
    failed: 0,
    results: [],
    error: null,
    startedAt: null,
    finishedAt: null,
    summary() {
      return {
        status: this.status,
        inputCount: this.inputCount,
        pending: this.pending,
        posted: this.posted,
        skippedExisting: this.skippedExisting,
        failed: this.failed,
        error: this.error,
        last: this.results.at(-1) ?? null,
      };
    },
  };
  window[stateKey] = state;

  function isTargetRequest(input, init) {
    const rawUrl = typeof input === "string" ? input : input?.url;
    if (!rawUrl) return false;
    const url = new URL(rawUrl, location.href);
    const method = String(init?.method || input?.method || "GET").toUpperCase();
    return (
      method === "POST" &&
      url.hostname === "api.vimeo.com" &&
      url.pathname === endpointPath &&
      url.searchParams.get("review_id") === config.reviewId &&
      !url.pathname.endsWith("/replies")
    );
  }

  async function readBody(input, init) {
    const body = init?.body;
    if (typeof body === "string") return body;
    if (body instanceof Blob) return body.text();
    if (body instanceof URLSearchParams) return body.toString();
    if (body != null) return null;
    if (typeof Request !== "undefined" && input instanceof Request) {
      try {
        return await input.clone().text();
      } catch {
        return null;
      }
    }
    return null;
  }

  function parseTemplate(rawBody) {
    if (!rawBody) return null;
    try {
      const body = JSON.parse(rawBody);
      if (
        typeof body.richtext !== "string" ||
        !Object.hasOwn(body, "time_code") ||
        body.review_link_id !== config.reviewId
      ) {
        return null;
      }
      return body;
    } catch {
      return null;
    }
  }

  function richtextFor(text) {
    return JSON.stringify({
      type: "doc",
      content: [
        {
          type: "paragraph",
          content: text ? [{ type: "text", text }] : [],
        },
      ],
    });
  }

  function textFromRichtext(raw) {
    try {
      const root = typeof raw === "string" ? JSON.parse(raw) : raw;
      const values = [];
      const visit = (node) => {
        if (!node || typeof node !== "object") return;
        if (typeof node.text === "string") values.push(node.text);
        if (Array.isArray(node.content)) node.content.forEach(visit);
      };
      visit(root);
      return values.join("");
    } catch {
      return "";
    }
  }

  function commentKey(comment) {
    const time = Math.round(Number(comment?.time_code));
    if (!Number.isFinite(time)) return null;
    const text = String(comment?.text || textFromRichtext(comment?.richtext) || "").trim();
    return `${time}\u0000${text}`;
  }

  function requestHeaders(input, init) {
    if (init?.headers) return new Headers(init.headers);
    if (typeof Request !== "undefined" && input instanceof Request) {
      return new Headers(input.headers);
    }
    return new Headers();
  }

  function credentialsFor(input, init) {
    return init?.credentials || input?.credentials || "include";
  }

  function existingCommentsUrl(postUrl) {
    const resourceUrls = performance
      .getEntriesByType("resource")
      .map((entry) => entry.name)
      .filter((name) => {
        try {
          const url = new URL(name);
          return (
            url.hostname === "api.vimeo.com" &&
            url.pathname === endpointPath &&
            url.searchParams.get("review_id") === config.reviewId &&
            url.searchParams.has("version_uri")
          );
        } catch {
          return false;
        }
      });
    const selected = resourceUrls.at(-1) || postUrl;
    const url = new URL(selected, location.href);
    url.searchParams.set("per_page", "100");
    url.searchParams.set("page", "1");
    return url.toString();
  }

  function commentsFromResponse(payload) {
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload?.data)) return payload.data;
    if (Array.isArray(payload?.comments)) return payload.comments;
    return null;
  }

  async function loadExistingComments(postUrl, input, init) {
    const headers = requestHeaders(input, init);
    headers.delete("content-length");
    const seenPages = new Set();
    const comments = [];
    let nextUrl = existingCommentsUrl(postUrl);

    for (let page = 0; nextUrl && page < 20; page += 1) {
      if (seenPages.has(nextUrl)) break;
      seenPages.add(nextUrl);
      const response = await originalFetch(nextUrl, {
        method: "GET",
        credentials: credentialsFor(input, init),
        headers,
      });
      if (!response.ok) {
        throw new Error(`existing-comments-check-failed:${response.status}`);
      }
      const payload = await response.json();
      const pageComments = commentsFromResponse(payload);
      if (!pageComments) throw new Error("existing-comments-check-failed:unexpected-response");
      comments.push(...pageComments);
      const candidate = payload?.paging?.next || payload?.pagination?.next || null;
      nextUrl = candidate ? new URL(candidate, "https://api.vimeo.com").toString() : null;
    }
    return comments;
  }

  function retryDelayMs(response, attempt) {
    const retryAfter = response.headers.get("retry-after");
    if (retryAfter) {
      const seconds = Number(retryAfter);
      if (Number.isFinite(seconds) && seconds > 0) return seconds * 1000;
      const date = Date.parse(retryAfter);
      if (Number.isFinite(date)) return Math.max(1000, date - Date.now());
    }
    if (response.status === 429) return 60000;
    return Math.min(30000, 2000 * 2 ** Math.max(0, attempt - 1));
  }

  async function postOne(input, init, template, item) {
    const body = {
      ...template,
      review_link_id: config.reviewId,
      time_code: item.seconds,
      richtext: richtextFor(item.text),
    };
    if (Object.hasOwn(body, "text")) body.text = item.text;

    let lastError = null;
    for (let attempt = 1; attempt <= config.maxRetries; attempt += 1) {
      try {
        const response = await originalFetch(input, {
          ...init,
          method: "POST",
          body: JSON.stringify(body),
        });
        const result = {
          seconds: item.seconds,
          text: item.text,
          attempt,
          status: response.status,
          ok: response.ok,
        };
        state.results.push(result);
        if (response.ok) {
          state.posted += 1;
          state.pending -= 1;
          return response;
        }
        lastError = new Error(`post-failed:${response.status}`);
        if (response.status !== 429 && response.status < 500) throw lastError;
        if (attempt < config.maxRetries) await sleep(retryDelayMs(response, attempt));
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        if (/post-failed:4(?!29)/.test(lastError.message)) throw lastError;
        if (attempt < config.maxRetries) {
          await sleep(Math.min(30000, 2000 * 2 ** Math.max(0, attempt - 1)));
        }
      }
    }
    throw lastError || new Error("post-failed:unknown");
  }

  window.fetch = async function vimeoReviewCommentsFetch(input, init = {}) {
    if (!isTargetRequest(input, init) || state.status !== "armed") {
      return originalFetch(input, init);
    }

    const rawBody = await readBody(input, init);
    const template = parseTemplate(rawBody);
    if (!template) {
      console.warn("vimeo-review-comments ignored a POST without a valid comment body");
      return originalFetch(input, init);
    }

    state.status = "checking";
    state.startedAt = new Date().toISOString();
    const postUrl = typeof input === "string" ? input : input.url;
    let firstResponseResolve;
    let firstResponseReject;
    const firstResponse = new Promise((resolve, reject) => {
      firstResponseResolve = resolve;
      firstResponseReject = reject;
    });

    state.promise = (async () => {
      const existing = await loadExistingComments(postUrl, input, init);
      const existingKeys = new Set(existing.map(commentKey).filter(Boolean));
      const queue = [];
      for (const item of config.items) {
        const key = `${item.seconds}\u0000${item.text.trim()}`;
        if (existingKeys.has(key)) {
          state.skippedExisting += 1;
          state.pending -= 1;
          state.results.push({ ...item, status: "existing", ok: true });
        } else {
          queue.push(item);
        }
      }

      if (!queue.length) {
        state.status = "complete";
        state.finishedAt = new Date().toISOString();
        firstResponseResolve(
          new Response(JSON.stringify({ time_code: template.time_code }), {
            status: 201,
            headers: { "content-type": "application/json" },
          }),
        );
        return;
      }

      state.status = "running";
      for (let index = 0; index < queue.length; index += 1) {
        const response = await postOne(input, init, template, queue[index]);
        if (index === 0) firstResponseResolve(response);
        if (index + 1 < queue.length) await sleep(config.intervalMs);
      }
      state.status = "complete";
      state.finishedAt = new Date().toISOString();
      console.table(state.results);
    })().catch((error) => {
      state.status = "failed";
      state.failed += 1;
      state.error = error instanceof Error ? error.message : String(error);
      state.finishedAt = new Date().toISOString();
      firstResponseReject(error);
      console.error("vimeo-review-comments failed", state.summary());
    });

    return firstResponse;
  };

  console.log("vimeo-review-comments armed", config.items.length);
})();

//# sourceURL=vimeo-review-comments-batch.js
