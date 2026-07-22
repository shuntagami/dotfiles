import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { mapSequenceFrameToRoot, parseXmeml } from "../src/xmeml.mjs";

const execFileAsync = promisify(execFile);

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<xmeml version="4">
  <sequence id="sequence-1">
    <name>master</name><duration>100</duration>
    <rate><timebase>30</timebase><ntsc>FALSE</ntsc></rate>
    <media><video><track><clipitem id="parent">
      <name>nested</name><start>10</start><end>60</end><in>0</in><out>50</out>
      <sequence id="sequence-2">
        <name>child</name><duration>100</duration>
        <rate><timebase>30</timebase><ntsc>FALSE</ntsc></rate>
        <media><video><track><clipitem id="asset">
          <name>asset.png</name><start>20</start><end>30</end><in>0</in><out>10</out>
          <file id="file-1"><name>asset.png</name><pathurl>file://localhost/tmp/asset.png</pathurl></file>
          <filter><effect><effectid>GraphicAndType</effectid><name>テロップです</name>
            <parameter><parameterid>source</parameterid><name>ソーステキスト</name><value>44OG44K544OI</value></parameter>
          </effect></filter>
        </clipitem></track></video>
        <audio><track><clipitem id="audio"><name>audio</name>
          <file id="file-2"><name>wrong.wav</name><pathurl>file://localhost/tmp/wrong.wav</pathurl></file>
        </clipitem></track></audio></media>
      </sequence>
      <filter><effect><effectid>timeremap</effectid>
        <parameter><parameterid>speed</parameterid><value>200</value></parameter>
        <parameter><parameterid>variablespeed</parameterid><value>0</value></parameter>
        <parameter><parameterid>graphdict</parameterid>
          <keyframe><when>0</when><value>0</value></keyframe>
          <keyframe><when>50</when><value>100</value></keyframe>
        </parameter>
      </effect></filter>
    </clipitem></track></video></media>
  </sequence>
</xmeml>`;

test("maps a child frame through a retimed nested sequence", async () => {
  const directory = await mkdtemp(join(tmpdir(), "premiere-xml-test-"));
  const path = join(directory, "sample.xml");
  await writeFile(path, xml, "utf8");
  const model = await parseXmeml(path);
  assert.equal(model.rootSequenceId, "sequence-1");
  const asset = model.sequences.get("sequence-2").videoTracks[0].clips[0];
  assert.equal(asset.fileName, "asset.png");
  assert.equal(asset.graphicEffects[0].name, "テロップです");
  assert.equal(asset.graphicEffects[0].parameters.get("source").name, "ソーステキスト");
  assert.equal(model.sequences.get("sequence-1").videoTracks[0].clips[0].fileName, null);
  const mapped = mapSequenceFrameToRoot(model, "sequence-2", 20);
  assert.equal(mapped.length, 1);
  assert.equal(mapped[0].rootFrame, 20);
  assert.equal(mapped[0].path[0].speed, 200);
});

test("telop CLI emits final-timeline timestamps", async () => {
  const directory = await mkdtemp(join(tmpdir(), "premiere-xml-test-"));
  const path = join(directory, "sample.xml");
  const output = join(directory, "telops.txt");
  const command = fileURLToPath(
    new URL("../../../bin/premiere-xml-telops", import.meta.url),
  );
  await writeFile(path, xml, "utf8");
  await execFileAsync(command, [path, "--timestamps", "--output", output]);
  assert.equal(await readFile(output, "utf8"), "[00:00.667] テロップです\n");
});

test("rejects a truncated XML unless recovery is enabled", async () => {
  const directory = await mkdtemp(join(tmpdir(), "premiere-xml-test-"));
  const path = join(directory, "truncated.xml");
  await writeFile(path, xml.slice(0, -20), "utf8");
  await assert.rejects(() => parseXmeml(path), /xml-parse-error/);
  const recovered = await parseXmeml(path, { allowTruncated: true });
  assert.equal(recovered.rootSequenceId, "sequence-1");
  assert.ok(recovered.warnings.some((warning) => warning.startsWith("xml-parse-error:")));
});

test("resolves -1 clip boundaries from adjacent transitions", async () => {
  const transitionXml = `<xmeml><sequence id="sequence-1"><name>master</name>
    <media><video><track>
      <transitionitem><start>100</start><end>104</end><alignment>center</alignment></transitionitem>
      <clipitem id="asset"><name>asset.jpg</name><start>-1</start><end>-1</end><in>50</in><out>154</out></clipitem>
      <transitionitem><start>200</start><end>204</end><alignment>center</alignment></transitionitem>
    </track></video></media>
  </sequence></xmeml>`;
  const directory = await mkdtemp(join(tmpdir(), "premiere-xml-test-"));
  const path = join(directory, "transitions.xml");
  await writeFile(path, transitionXml, "utf8");
  const model = await parseXmeml(path);
  const clip = model.sequences.get("sequence-1").videoTracks[0].clips[0];
  assert.equal(clip.start, 100);
  assert.equal(clip.end, 204);
  assert.equal(clip.xmlStart, -1);
  assert.equal(clip.xmlEnd, -1);
});
