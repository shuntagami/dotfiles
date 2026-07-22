#!/usr/bin/env node

import { writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import {
  actualFps,
  assetDisplayName,
  collectTrackAssets,
  mapSequenceFrameToRoot,
  parseXmeml,
} from "../src/xmeml.mjs";

function usage() {
  return `Usage:
  premiere-xml-timestamps inspect <xml> [--allow-truncated]
  premiere-xml-timestamps audit <xml> [--allow-truncated]
  premiere-xml-timestamps extract <xml> (--all-tracks | --track <sequence-id:track> [--track ...])
      [--extensions jpg,png,mov,mp4] [--comment TEXT]
      [--format table|comments|json] [--dedupe] [--output PATH] [--allow-truncated]`;
}

function parseCli(argv) {
  const [command, xmlPath, ...rest] = argv;
  if (!command || !xmlPath || !["inspect", "audit", "extract"].includes(command)) {
    throw new Error(usage());
  }
  const trackValues = [];
  const filtered = [];
  for (let index = 0; index < rest.length; index += 1) {
    if (rest[index] === "--track") {
      const value = rest[index + 1];
      if (!value) throw new Error("--track requires sequence-id:track");
      trackValues.push(value);
      index += 1;
    } else {
      filtered.push(rest[index]);
    }
  }
  const { values } = parseArgs({
    args: filtered,
    options: {
      "allow-truncated": { type: "boolean", default: false },
      "all-tracks": { type: "boolean", default: false },
      extensions: { type: "string" },
      comment: { type: "string" },
      dedupe: { type: "boolean", default: false },
      format: { type: "string", default: "table" },
      output: { type: "string" },
    },
    strict: true,
  });
  const tracks = trackValues.map((value) => {
    const match = /^(sequence-[^:]+):(\d+)$/.exec(value);
    if (!match) throw new Error(`invalid-track:${value}`);
    return { sequenceId: match[1], trackIndex: Number(match[2]) };
  });
  return { command, xmlPath, tracks, values };
}

function allTrackSelectors(model) {
  return [...model.sequences.values()].flatMap((sequence) =>
    sequence.videoTracks.map((track) => ({
      sequenceId: sequence.id,
      trackIndex: track.index,
    })),
  );
}

function clock(seconds, decimals = 3) {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secondValue = seconds % 60;
  const secondText = secondValue.toFixed(decimals).padStart(decimals ? 3 + decimals : 2, "0");
  return hours
    ? `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${secondText}`
    : `${String(minutes).padStart(2, "0")}:${secondText}`;
}

function wholeSecondClock(seconds) {
  const rounded = Math.round(seconds);
  const hours = Math.floor(rounded / 3600);
  const minutes = Math.floor((rounded % 3600) / 60);
  const secs = rounded % 60;
  return hours
    ? `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
    : `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

function extensionOf(name) {
  const match = /\.([^.]+)$/.exec(name || "");
  return match ? match[1].toLowerCase() : "";
}

function inspect(model) {
  console.log(`Root: ${model.rootSequenceId}`);
  for (const sequence of model.sequences.values()) {
    console.log(
      `\n${sequence.id}\t${sequence.name}\tduration=${sequence.duration}\ttracks=${sequence.videoTracks.length}`,
    );
    for (const track of sequence.videoTracks) {
      const samples = track.clips
        .slice(0, 6)
        .map((clip) => assetDisplayName(clip))
        .join(" ; ");
      console.log(`  track ${track.index}\tclips=${track.clips.length}\t${samples}`);
    }
  }
}

function audit(model) {
  const imageExtensions = new Set([
    "avif",
    "bmp",
    "gif",
    "heic",
    "jpeg",
    "jpg",
    "png",
    "tif",
    "tiff",
    "webp",
  ]);
  const selectors = allTrackSelectors(model);
  const assets = collectTrackAssets(model, selectors);
  const placements = assets.filter((asset) => asset.clip.nestedSequenceId);
  const retimedPlacements = placements.filter((asset) => asset.clip.timeRemap);
  const unsupportedRetimedPlacements = retimedPlacements.filter(
    (asset) => asset.clip.timeRemap.keyframes.length < 2,
  );
  const variablePlacements = retimedPlacements.filter((asset) => asset.clip.timeRemap.variable);
  const reversePlacements = retimedPlacements.filter((asset) => asset.clip.timeRemap.reverse);
  const transitionRestored = assets.filter(
    (asset) => asset.clip.xmlStart === -1 || asset.clip.xmlEnd === -1,
  );
  const unresolvedBoundaries = assets.filter(
    (asset) => asset.clip.start === -1 || asset.clip.end === -1,
  );
  const imageAssets = assets.filter((asset) =>
    imageExtensions.has(extensionOf(assetDisplayName(asset.clip))),
  );
  let mappedImageClips = 0;
  let mappedImageEvents = 0;
  const unmappedImages = [];
  for (const asset of imageAssets) {
    const mappings = mapSequenceFrameToRoot(model, asset.sequenceId, asset.clip.start);
    if (mappings.length) {
      mappedImageClips += 1;
      mappedImageEvents += mappings.length;
    } else {
      unmappedImages.push(
        `${asset.sequenceId}:${asset.trackIndex}:${assetDisplayName(asset.clip)}`,
      );
    }
  }

  const root = model.sequences.get(model.rootSequenceId);
  const fps = actualFps(root?.rate);
  console.log(`Root: ${model.rootSequenceId}\t${root?.name ?? ""}`);
  console.log(
    `Root rate/duration: ${fps?.toFixed(6) ?? "unknown"} fps / ${
      fps && Number.isFinite(root?.duration) ? clock(root.duration / fps) : "unknown"
    }`,
  );
  console.log(`Sequences: ${model.sequences.size}`);
  console.log(`Video clips: ${assets.length}`);
  console.log(`Nested placements: ${placements.length}`);
  console.log(
    `Retimed nested placements: ${retimedPlacements.length} (variable=${variablePlacements.length}, reverse=${reversePlacements.length}, missing-keyframes=${unsupportedRetimedPlacements.length})`,
  );
  console.log(
    `Transition boundaries: restored=${transitionRestored.length}, unresolved=${unresolvedBoundaries.length}`,
  );
  console.log(
    `Image clips mapped: ${mappedImageClips}/${imageAssets.length} (${mappedImageEvents} root events)`,
  );
  if (unmappedImages.length) {
    console.log(`Unmapped image clips: ${unmappedImages.length}`);
    for (const item of unmappedImages.slice(0, 10)) console.log(`  ${item}`);
    if (unmappedImages.length > 10) console.log(`  ... and ${unmappedImages.length - 10} more`);
  }
}

async function main() {
  const cli = parseCli(process.argv.slice(2));
  const model = await parseXmeml(cli.xmlPath, {
    allowTruncated: cli.values["allow-truncated"],
  });
  for (const warning of model.warnings) console.error(`Warning: ${warning}`);

  if (cli.command === "inspect") {
    inspect(model);
    return;
  }
  if (cli.command === "audit") {
    audit(model);
    return;
  }
  if (!cli.tracks.length && !cli.values["all-tracks"]) {
    throw new Error("extract requires --all-tracks or at least one --track");
  }
  if (!["table", "comments", "json"].includes(cli.values.format)) {
    throw new Error("--format must be table, comments, or json");
  }

  const root = model.sequences.get(model.rootSequenceId);
  const fps = actualFps(root?.rate);
  if (!fps) throw new Error("root-sequence-frame-rate-missing");
  const allowedExtensions = cli.values.extensions
    ? new Set(cli.values.extensions.split(",").map((value) => value.trim().replace(/^\./, "").toLowerCase()))
    : null;

  const output = [];
  const selectors = cli.values["all-tracks"] ? allTrackSelectors(model) : cli.tracks;
  for (const asset of collectTrackAssets(model, selectors)) {
    const name = assetDisplayName(asset.clip);
    if (allowedExtensions && !allowedExtensions.has(extensionOf(name))) continue;
    const mappings = mapSequenceFrameToRoot(model, asset.sequenceId, asset.clip.start);
    for (const mapping of mappings) {
      const seconds = mapping.rootFrame / fps;
      output.push({
        seconds,
        timecode: clock(seconds),
        vimeoTimecode: wholeSecondClock(seconds),
        rootFrame: mapping.rootFrame,
        name,
        filePath: asset.clip.filePath,
        sourceSequenceId: asset.sequenceId,
        sourceSequenceName: asset.sequenceName,
        sourceTrack: asset.trackIndex,
        sourceFrame: asset.clip.start,
        path: mapping.path,
      });
    }
  }
  output.sort((a, b) => a.seconds - b.seconds || a.name.localeCompare(b.name, "ja"));

  let rendered;
  if (cli.values.format === "json") {
    rendered = JSON.stringify(output, null, 2);
  } else if (cli.values.format === "comments") {
    const lines = output.map(
      (item) => `${item.vimeoTimecode} ${cli.values.comment || item.name}`,
    );
    rendered = (cli.values.dedupe ? [...new Set(lines)] : lines).join("\n");
  } else {
    rendered = [
      "timecode\tseconds\tsequence\ttrack\tname",
      ...output.map(
        (item) =>
          `${item.timecode}\t${item.seconds.toFixed(6)}\t${item.sourceSequenceId}\t${item.sourceTrack}\t${item.name}`,
      ),
    ].join("\n");
  }
  if (cli.values.output) {
    await writeFile(cli.values.output, `${rendered}\n`, "utf8");
    console.error(`Wrote: ${cli.values.output}`);
  } else {
    console.log(rendered);
  }
}

try {
  await main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
