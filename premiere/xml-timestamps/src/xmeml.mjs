import { createReadStream } from "node:fs";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";
import { SaxesParser } from "saxes";

function numberOrNull(value) {
  const number = Number(String(value ?? "").trim());
  return Number.isFinite(number) ? number : null;
}

function booleanValue(value) {
  return /^(true|1)$/i.test(String(value ?? "").trim());
}

function nearestFrame(stack, predicate) {
  for (let index = stack.length - 1; index >= 0; index -= 1) {
    if (predicate(stack[index])) return stack[index];
  }
  return null;
}

function directParent(stack) {
  return stack.at(-1) ?? null;
}

function resolveTransitionBoundaries(track) {
  for (let index = 0; index < track.items.length; index += 1) {
    const item = track.items[index];
    if (item.type !== "clip") continue;
    const clip = item.clip;
    if (clip.start === -1) {
      const previous = track.items[index - 1];
      if (previous?.type === "transition" && Number.isFinite(previous.transition.start)) {
        clip.xmlStart = clip.start;
        clip.start = previous.transition.start;
      }
    }
    if (clip.end === -1) {
      const next = track.items[index + 1];
      if (next?.type === "transition" && Number.isFinite(next.transition.end)) {
        clip.xmlEnd = clip.end;
        clip.end = next.transition.end;
      }
    }
  }
}

function displayPath(pathUrl) {
  if (!pathUrl) return null;
  try {
    const path = fileURLToPath(pathUrl);
    return path;
  } catch {
    try {
      return decodeURIComponent(pathUrl.replace(/^file:\/\/localhost\/?/i, "/"));
    } catch {
      return pathUrl;
    }
  }
}

export async function parseXmeml(path, { allowTruncated = false } = {}) {
  const sequences = new Map();
  const stack = [];
  const warnings = [];
  let rootSequenceId = null;
  let parseError = null;
  let stopped = false;

  const parser = new SaxesParser({ xmlns: false });

  parser.on("opentag", (tag) => {
    const parent = directParent(stack);
    const frame = { name: tag.name, text: "" };

    if (tag.name === "sequence") {
      frame.sequence = {
        id: String(tag.attributes.id ?? ""),
        name: null,
        duration: null,
        rate: { timebase: null, ntsc: false },
        videoTracks: [],
      };
      const parentClip = nearestFrame(
        stack,
        (candidate) => candidate.clipItemBoundary,
      )?.clip;
      if (parentClip && frame.sequence.id) parentClip.nestedSequenceId = frame.sequence.id;
    } else if (
      tag.name === "track" &&
      parent?.name === "video" &&
      stack.at(-2)?.name === "media" &&
      stack.at(-3)?.sequence
    ) {
      const sequence = stack.at(-3).sequence;
      frame.track = {
        index: sequence.videoTracks.length + 1,
        clips: [],
        items: [],
      };
      sequence.videoTracks.push(frame.track);
    } else if (tag.name === "clipitem") {
      // Keep a boundary for every clipitem, including audio clips that we do not
      // collect. Without it, files and effects inside an audio clip can leak into
      // the nearest enclosing video/nested-sequence clip.
      frame.clipItemBoundary = true;
      if (parent?.track) {
        frame.clip = {
          id: String(tag.attributes.id ?? ""),
          name: null,
          enabled: true,
          duration: null,
          start: null,
          end: null,
          in: null,
          out: null,
          rate: { timebase: null, ntsc: false },
          nestedSequenceId: null,
          fileName: null,
          filePath: null,
          timeRemap: null,
          graphicEffects: [],
        };
        parent.track.clips.push(frame.clip);
        parent.track.items.push({ type: "clip", clip: frame.clip });
      }
    } else if (tag.name === "transitionitem" && parent?.track) {
      frame.transition = { start: null, end: null, alignment: null };
      parent.track.items.push({ type: "transition", transition: frame.transition });
    } else if (tag.name === "rate") {
      const owner = parent?.sequence ?? parent?.clip ?? null;
      frame.rateOwner = owner;
    } else if (tag.name === "file") {
      frame.file = { name: null, pathUrl: null };
    } else if (tag.name === "effect") {
      const ownerBoundary = nearestFrame(
        stack,
        (candidate) => candidate.clipItemBoundary || candidate.transition,
      );
      frame.effect = { id: null, name: null, parameters: new Map() };
      frame.effectOwnerClip = ownerBoundary?.clip ?? null;
    } else if (tag.name === "parameter") {
      const effectFrame = nearestFrame(stack, (candidate) => candidate.effect);
      if (effectFrame) {
        frame.parameter = { id: null, name: null, value: null, keyframes: [] };
      }
    } else if (tag.name === "keyframe") {
      const parameterFrame = nearestFrame(stack, (candidate) => candidate.parameter);
      if (parameterFrame) frame.keyframe = { when: null, value: null };
    }

    stack.push(frame);
  });

  parser.on("text", (text) => {
    const frame = stack.at(-1);
    if (frame) frame.text += text;
  });

  parser.on("cdata", (text) => {
    const frame = stack.at(-1);
    if (frame) frame.text += text;
  });

  parser.on("closetag", (closedTag) => {
    const frame = stack.pop();
    if (!frame) return;
    const tagName = typeof closedTag === "string" ? closedTag : closedTag.name;
    if (frame.name !== tagName) {
      warnings.push(`mismatched-tag:${frame.name}:${tagName}`);
    }
    const text = frame.text.trim();
    const parent = directParent(stack);

    if (frame.keyframe) {
      const parameterFrame = nearestFrame(stack, (candidate) => candidate.parameter);
      if (parameterFrame) parameterFrame.parameter.keyframes.push(frame.keyframe);
    } else if (frame.parameter) {
      const effectFrame = nearestFrame(stack, (candidate) => candidate.effect);
      if (effectFrame && frame.parameter.id) {
        effectFrame.effect.parameters.set(frame.parameter.id, frame.parameter);
      }
    } else if (frame.effect) {
      const clip = frame.effectOwnerClip;
      if (clip && frame.effect.id === "timeremap") {
        const speed = frame.effect.parameters.get("speed");
        const variable = frame.effect.parameters.get("variablespeed");
        const reverse = frame.effect.parameters.get("reverse");
        const graph = frame.effect.parameters.get("graphdict");
        clip.timeRemap = {
          speed: numberOrNull(speed?.value),
          variable: booleanValue(variable?.value),
          reverse: booleanValue(reverse?.value),
          keyframes: (graph?.keyframes ?? []).filter(
            (keyframe) => keyframe.when != null && keyframe.value != null,
          ),
        };
      } else if (clip && frame.effect.id === "GraphicAndType") {
        clip.graphicEffects.push(frame.effect);
      }
    } else if (frame.file) {
      const clipFrame = nearestFrame(
        stack,
        (candidate) => candidate.clipItemBoundary,
      );
      if (clipFrame?.clip && !clipFrame.clip.filePath) {
        clipFrame.clip.fileName = frame.file.name;
        clipFrame.clip.filePath = displayPath(frame.file.pathUrl);
      }
    } else if (frame.track) {
      resolveTransitionBoundaries(frame.track);
    } else if (frame.sequence) {
      const sequence = frame.sequence;
      if (sequence.id && (sequence.name || sequence.videoTracks.length)) {
        sequences.set(sequence.id, sequence);
        const parentSequence = nearestFrame(stack, (candidate) => candidate.sequence);
        if (!parentSequence && !rootSequenceId) rootSequenceId = sequence.id;
      }
    }

    if (parent?.sequence) {
      if (tagName === "name") parent.sequence.name = text;
      else if (tagName === "duration") parent.sequence.duration = numberOrNull(text);
    }
    if (parent?.clip) {
      if (tagName === "name") parent.clip.name = text;
      else if (tagName === "enabled") parent.clip.enabled = !/^false$/i.test(text);
      else if (["duration", "start", "end", "in", "out"].includes(tagName)) {
        parent.clip[tagName] = numberOrNull(text);
      }
    }
    if (parent?.transition) {
      if (tagName === "start" || tagName === "end") {
        parent.transition[tagName] = numberOrNull(text);
      } else if (tagName === "alignment") {
        parent.transition.alignment = text;
      }
    }
    if (parent?.rateOwner) {
      if (tagName === "timebase") parent.rateOwner.rate.timebase = numberOrNull(text);
      else if (tagName === "ntsc") parent.rateOwner.rate.ntsc = booleanValue(text);
    }
    if (parent?.file) {
      if (tagName === "name") parent.file.name = text;
      else if (tagName === "pathurl") parent.file.pathUrl = text;
    }
    if (parent?.effect) {
      if (tagName === "effectid") parent.effect.id = text;
      else if (tagName === "name") parent.effect.name = text;
    }
    if (parent?.parameter) {
      if (tagName === "parameterid") parent.parameter.id = text;
      else if (tagName === "name") parent.parameter.name = text;
      else if (tagName === "value") parent.parameter.value = text;
    }
    if (parent?.keyframe) {
      if (tagName === "when") parent.keyframe.when = numberOrNull(text);
      else if (tagName === "value") parent.keyframe.value = numberOrNull(text);
    }
  });

  parser.on("error", (error) => {
    parseError = error;
  });

  const stream = createReadStream(path, { encoding: "utf8" });
  try {
    for await (const chunk of stream) {
      if (stopped) break;
      try {
        parser.write(chunk);
      } catch (error) {
        parseError = error;
        stopped = true;
        stream.destroy();
      }
    }
    if (!stopped) {
      try {
        parser.close();
      } catch (error) {
        parseError = error;
      }
    }
  } catch (error) {
    if (!parseError) parseError = error;
  }

  if (parseError) {
    const message = `xml-parse-error:${parseError.message}`;
    if (!allowTruncated) throw new Error(message);
    warnings.push(message);
  }
  if (allowTruncated) {
    for (const frame of stack) {
      const sequence = frame.sequence;
      if (!sequence?.id || (!sequence.name && !sequence.videoTracks.length)) continue;
      sequences.set(sequence.id, sequence);
      if (!rootSequenceId) rootSequenceId = sequence.id;
    }
  }
  for (const sequence of sequences.values()) {
    for (const track of sequence.videoTracks) resolveTransitionBoundaries(track);
  }
  if (!rootSequenceId || !sequences.size) throw new Error("no-sequence-found");

  return { rootSequenceId, sequences, warnings };
}

export function actualFps(rate) {
  const timebase = Number(rate?.timebase);
  if (!Number.isFinite(timebase) || timebase <= 0) return null;
  return rate.ntsc ? (timebase * 1000) / 1001 : timebase;
}

function visibleWhen(clip, when) {
  const lower = Number.isFinite(clip.in) ? clip.in : 0;
  const upper = Number.isFinite(clip.out)
    ? clip.out
    : lower + Math.max(0, (clip.end ?? 0) - (clip.start ?? 0));
  return when >= lower - 1e-6 && when < upper - 1e-6;
}

function mapThroughPlacement(clip, childFrame) {
  if (!Number.isFinite(clip.start) || !Number.isFinite(clip.end)) return [];
  const keyframes = clip.timeRemap?.keyframes ?? [];
  const mapped = [];

  if (keyframes.length >= 2) {
    for (let index = 0; index + 1 < keyframes.length; index += 1) {
      const first = keyframes[index];
      const second = keyframes[index + 1];
      const minValue = Math.min(first.value, second.value);
      const maxValue = Math.max(first.value, second.value);
      if (childFrame < minValue - 1e-6 || childFrame > maxValue + 1e-6) continue;
      if (Math.abs(second.value - first.value) < 1e-9) continue;
      const ratio = (childFrame - first.value) / (second.value - first.value);
      const when = first.when + ratio * (second.when - first.when);
      if (!visibleWhen(clip, when)) continue;
      const parentFrame = clip.start + (when - (clip.in ?? 0));
      if (parentFrame >= clip.start - 1e-6 && parentFrame < clip.end - 1e-6) {
        mapped.push({ parentFrame, when, speedMapped: true });
      }
    }
  } else {
    const when = childFrame;
    if (visibleWhen(clip, when)) {
      const parentFrame = clip.start + (when - (clip.in ?? 0));
      if (parentFrame >= clip.start - 1e-6 && parentFrame < clip.end - 1e-6) {
        mapped.push({ parentFrame, when, speedMapped: false });
      }
    }
  }

  const unique = new Map();
  for (const result of mapped) unique.set(result.parentFrame.toFixed(6), result);
  return [...unique.values()];
}

export function buildPlacementIndex(model) {
  const parents = new Map();
  for (const sequence of model.sequences.values()) {
    for (const track of sequence.videoTracks) {
      for (const clip of track.clips) {
        if (!clip.nestedSequenceId) continue;
        const placements = parents.get(clip.nestedSequenceId) ?? [];
        placements.push({ parentSequenceId: sequence.id, trackIndex: track.index, clip });
        parents.set(clip.nestedSequenceId, placements);
      }
    }
  }
  return parents;
}

export function mapSequenceFrameToRoot(model, sequenceId, frame) {
  const parents = buildPlacementIndex(model);

  function recurse(currentSequenceId, currentFrame, visited) {
    if (currentSequenceId === model.rootSequenceId) {
      return [{ rootFrame: currentFrame, path: [] }];
    }
    if (visited.has(currentSequenceId)) return [];
    const nextVisited = new Set(visited);
    nextVisited.add(currentSequenceId);
    const results = [];
    for (const placement of parents.get(currentSequenceId) ?? []) {
      for (const mapped of mapThroughPlacement(placement.clip, currentFrame)) {
        for (const parentResult of recurse(
          placement.parentSequenceId,
          mapped.parentFrame,
          nextVisited,
        )) {
          results.push({
            rootFrame: parentResult.rootFrame,
            path: [
              {
                parentSequenceId: placement.parentSequenceId,
                clipId: placement.clip.id,
                clipName: placement.clip.name,
                speed: placement.clip.timeRemap?.speed ?? 100,
                sourceFrame: currentFrame,
                parentFrame: mapped.parentFrame,
              },
              ...parentResult.path,
            ],
          });
        }
      }
    }
    return results;
  }

  return recurse(sequenceId, frame, new Set());
}

export function collectTrackAssets(model, selectors) {
  const assets = [];
  for (const selector of selectors) {
    const sequence = model.sequences.get(selector.sequenceId);
    if (!sequence) throw new Error(`unknown-sequence:${selector.sequenceId}`);
    const track = sequence.videoTracks[selector.trackIndex - 1];
    if (!track) throw new Error(`unknown-track:${selector.sequenceId}:${selector.trackIndex}`);
    for (const clip of track.clips) {
      if (!clip.enabled || !Number.isFinite(clip.start)) continue;
      assets.push({
        sequenceId: sequence.id,
        sequenceName: sequence.name,
        trackIndex: track.index,
        clip,
      });
    }
  }
  return assets;
}

export function assetDisplayName(clip) {
  return clip.fileName || clip.name || (clip.filePath ? basename(clip.filePath) : clip.id);
}
