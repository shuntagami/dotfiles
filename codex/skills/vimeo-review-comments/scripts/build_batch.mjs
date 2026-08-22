#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";

const reviewPathPattern =
  /^\/reviews\/(?<reviewId>[0-9a-fA-F-]+)\/videos\/(?<videoId>[0-9]+)\/?$/;
const timestampPattern =
  /^\s*(?:(?<hours>\d{1,3}):)?(?<minutes>\d{1,2}):(?<seconds>\d{2})\s+(?<text>.+?)\s*$/;
const configPlaceholder = "__VIMEO_REVIEW_CONFIG__";

function fail(message) {
  console.error(`build_batch.mjs: ${message}`);
  process.exitCode = 2;
}

function parseReviewUrl(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl.trim());
  } catch {
    throw new Error("URL must be a valid Vimeo Review URL");
  }
  if (
    url.protocol !== "https:" ||
    !["vimeo.com", "www.vimeo.com"].includes(url.hostname.toLowerCase())
  ) {
    throw new Error("URL must be an https://vimeo.com Review URL");
  }
  const match = reviewPathPattern.exec(url.pathname);
  if (!match) throw new Error("URL must match /reviews/<review-id>/videos/<video-id>");
  return match.groups;
}

function parseComments(contents) {
  const items = [];
  const seen = new Set();
  for (const [index, line] of contents.split(/\r?\n/).entries()) {
    const lineNumber = index + 1;
    const stripped = line.trim();
    if (!stripped || stripped.startsWith("#")) continue;
    const match = timestampPattern.exec(line);
    if (!match) {
      throw new Error(
        `line ${lineNumber}: expected 'MM:SS comment' or 'HH:MM:SS comment'`,
      );
    }
    const hours = Number(match.groups.hours || 0);
    const minutes = Number(match.groups.minutes);
    const seconds = Number(match.groups.seconds);
    if (minutes >= 60 || seconds >= 60) {
      throw new Error(`line ${lineNumber}: minutes and seconds must be below 60`);
    }
    const text = match.groups.text.trim();
    if (!text) throw new Error(`line ${lineNumber}: comment text is empty`);
    const totalSeconds = hours * 3600 + minutes * 60 + seconds;
    const key = `${totalSeconds}\u0000${text}`;
    if (seen.has(key)) continue;
    seen.add(key);
    items.push({ seconds: totalSeconds, text, sourceLine: lineNumber });
  }
  if (!items.length) throw new Error("no comments found");
  items.sort((a, b) => a.seconds - b.seconds || a.sourceLine - b.sourceLine);
  return items;
}

function formatTimestamp(totalSeconds) {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const two = (value) => String(value).padStart(2, "0");
  return hours
    ? `${two(hours)}:${two(minutes)}:${two(seconds)}`
    : `${two(minutes)}:${two(seconds)}`;
}

async function readStdin() {
  process.stdin.setEncoding("utf8");
  let contents = "";
  for await (const chunk of process.stdin) contents += chunk;
  return contents;
}

async function main() {
  const { values } = parseArgs({
    options: {
      url: { type: "string" },
      input: { type: "string" },
      output: { type: "string" },
      "interval-ms": { type: "string", default: "7500" },
      "max-retries": { type: "string", default: "8" },
    },
    strict: true,
  });
  if (!values.url) throw new Error("--url is required");

  const intervalMs = Number(values["interval-ms"]);
  const maxRetries = Number(values["max-retries"]);
  if (!Number.isInteger(intervalMs) || intervalMs < 7000) {
    throw new Error("--interval-ms must be an integer of at least 7000");
  }
  if (!Number.isInteger(maxRetries) || maxRetries < 1 || maxRetries > 20) {
    throw new Error("--max-retries must be an integer between 1 and 20");
  }

  const { reviewId, videoId } = parseReviewUrl(values.url);
  const contents = values.input
    ? await readFile(values.input, "utf8")
    : await readStdin();
  const parsedItems = parseComments(contents);
  const items = parsedItems.map(({ seconds, text }) => ({ seconds, text }));
  const config = {
    reviewId,
    videoId,
    intervalMs,
    maxRetries,
    requireExistingCheck: true,
    items,
  };

  const runtimeUrl = new URL("runtime.js", import.meta.url);
  const runtime = await readFile(runtimeUrl, "utf8");
  if (runtime.split(configPlaceholder).length !== 2) {
    throw new Error("runtime.js must contain exactly one config placeholder");
  }
  const snippet = runtime.replace(configPlaceholder, JSON.stringify(config));
  if (values.output) await writeFile(values.output, snippet, "utf8");
  else process.stdout.write(snippet);

  const summary = items
    .map(({ seconds, text }) => `${formatTimestamp(seconds)} ${text}`)
    .join(", ");
  console.error(`Prepared ${items.length} comments for video ${videoId}: ${summary}`);
}

try {
  await main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
