import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const reviewId = "49b1d0cc-e9cb-4b19-9063-57a85d7dd8e5";
const videoId = "1211943875";
const endpoint = `https://api.vimeo.com/videos/${videoId}/private_comments?review_id=${reviewId}`;
const posts = [];
let rateLimitedOnce = false;

Object.defineProperty(globalThis, "window", { value: globalThis, configurable: true });
Object.defineProperty(globalThis, "location", {
  value: { href: `https://vimeo.com/reviews/${reviewId}/videos/${videoId}` },
  configurable: true,
});
Object.defineProperty(globalThis, "performance", {
  value: {
    getEntriesByType() {
      return [
        {
          name: `${endpoint}&version_uri=%2Fvideos%2F${videoId}%2Fversions%2F1`,
        },
      ];
    },
  },
  configurable: true,
});

globalThis.fetch = async (input, init = {}) => {
  const url = typeof input === "string" ? input : input.url;
  const method = String(init.method || input?.method || "GET").toUpperCase();
  if (method === "GET") {
    assert.match(url, /version_uri=/);
    assert.equal(new Headers(init.headers).get("authorization"), "Bearer test-only");
    return Response.json({
      data: [{ time_code: 4.01, text: "画像" }],
      pagination: { next: null },
    });
  }
  if (!init.body) return new Response("missing body", { status: 400 });
  const body = JSON.parse(init.body);
  posts.push(body);
  if (body.time_code === 18 && !rateLimitedOnce) {
    rateLimitedOnce = true;
    return new Response("rate limited", {
      status: 429,
      headers: { "retry-after": "0.001" },
    });
  }
  return Response.json({ time_code: body.time_code }, { status: 201 });
};

const runtimePath = new URL("../scripts/runtime.js", import.meta.url);
const runtime = await readFile(runtimePath, "utf8");
const config = {
  reviewId,
  videoId,
  intervalMs: 1,
  maxRetries: 3,
  requireExistingCheck: true,
  items: [
    { seconds: 4, text: "画像" },
    { seconds: 18, text: "画像" },
    { seconds: 39, text: "別コメント" },
  ],
};
const snippet = runtime.replace("__VIMEO_REVIEW_CONFIG__", JSON.stringify(config));
(0, eval)(snippet);

const emptyResponse = await window.fetch(endpoint, { method: "POST" });
assert.equal(emptyResponse.status, 400);
assert.equal(window.__vimeoReviewCommentsBatch.status, "armed");

const template = {
  review_link_id: reviewId,
  richtext: JSON.stringify({ type: "doc", content: [] }),
  time_code: 0,
};
const firstResponse = await window.fetch(endpoint, {
  method: "POST",
  headers: {
    authorization: "Bearer test-only",
    "content-type": "application/json",
  },
  body: JSON.stringify(template),
});
assert.equal(firstResponse.status, 201);
await window.__vimeoReviewCommentsBatch.promise;

const summary = window.__vimeoReviewCommentsBatch.summary();
assert.deepEqual(summary, {
  status: "complete",
  inputCount: 3,
  pending: 0,
  posted: 2,
  skippedExisting: 1,
  failed: 0,
  error: null,
  last: {
    seconds: 39,
    text: "別コメント",
    attempt: 1,
    status: 201,
    ok: true,
  },
});
assert.deepEqual(
  posts.map(({ time_code, richtext }) => ({
    time_code,
    text: JSON.parse(richtext).content[0].content[0].text,
  })),
  [
    { time_code: 18, text: "画像" },
    { time_code: 18, text: "画像" },
    { time_code: 39, text: "別コメント" },
  ],
);

console.log("runtime test passed");
