#!/usr/bin/env python3
"""Protocol tests use isolated named pasteboards, never the user's clipboard."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = r'''
import AppKit
import CryptoKit
let a=Array(CommandLine.arguments.dropFirst())
let b = a[0] == "general" ? NSPasteboard.general : NSPasteboard(name:NSPasteboard.Name(a[0]))
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:8,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
for y in 0..<8 { for x in 0..<8 { let p=bitmap.bitmapData!+y*bitmap.bytesPerRow+x*4; p[0]=255; p[1]=0; p[2]=0; p[3]=255 } }
let png=bitmap.representation(using:.png,properties:[:])!
let converted=NSBitmapImageRep(data:bitmap.tiffRepresentation!)!.representation(using:.png,properties:[:])!
switch a[1] {
case "png": FileHandle.standardOutput.write(png)
case "converted-png": FileHandle.standardOutput.write(converted)
case "image": b.clearContents(); b.setData(png,forType:.png)
case "tiff": b.clearContents(); b.setData(bitmap.tiffRepresentation!,forType:.tiff)
case "text": b.clearContents(); b.setString("test text",forType:.string)
case "digest":
    if let d=b.data(forType:.png) { print(SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()) }
    else { print("no image") }
case "guard":
    let saved=(b.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType:t).map{(t,$0)} } }
    print("READY"); fflush(stdout)
    _=readLine()
    // Restore only our test image. Never overwrite an intervening user copy.
    if b.data(forType:.png) == png || b.data(forType:.png) == converted || b.string(forType:.string) == "test text" {
        b.clearContents()
        let items=saved.map { entries -> NSPasteboardItem in let item=NSPasteboardItem(); for (t,d) in entries {item.setData(d,forType:t)}; return item }
        b.writeObjects(items)
        print("RESTORED")
    } else { print("UNCHANGED") }
default: fatalError()
}
'''


class BridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.temp.name) / "bridge"
        cls.fixture = Path(cls.temp.name) / "fixture"
        src = Path(cls.temp.name) / "fixture.swift"
        src.write_text(FIXTURE)
        subprocess.run(["swiftc", str(ROOT / "scripts/clipboard-image-bridge.swift"), "-o", str(cls.binary)], check=True)
        subprocess.run(["swiftc", str(src), "-o", str(cls.fixture)], check=True)
        cls.png = subprocess.check_output([str(cls.fixture), "unused", "png"])

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.board = "bridge-test-" + str(uuid.uuid4())
        self.fixture_run("text")
        self.process = subprocess.Popen([str(self.binary), "--pasteboard", self.board, "receive"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.assertEqual(self.process.stdout.readline(), b"READY\n")

    def tearDown(self):
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=5)
        self.process.stdin.close()
        self.process.stdout.close()

    def fixture_run(self, command):
        return subprocess.check_output([str(self.fixture), self.board, command]).strip()

    def stage(self, data):
        self.process.stdin.write(str(len(data)).encode() + b"\n" + data)
        self.process.stdin.flush()

    def test_png_arrives_intact(self):
        self.stage(self.png)
        self.assertEqual(self.process.stdout.readline(), b"STAGED\n")
        self.process.stdin.write(b"COMMIT\n"); self.process.stdin.flush()
        self.assertEqual(self.process.stdout.readline(), b"OK\n")
        self.assertEqual(self.fixture_run("digest").decode(), hashlib.sha256(self.png).hexdigest())

    def test_destination_copy_wins_during_transfer(self):
        self.stage(self.png)
        self.assertEqual(self.process.stdout.readline(), b"STAGED\n")
        self.fixture_run("text")
        self.process.stdin.write(b"COMMIT\n"); self.process.stdin.flush()
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.fixture_run("digest"), b"no image")

    def test_invalid_image_does_not_clear_clipboard(self):
        self.stage(b"not an image")
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.fixture_run("digest"), b"no image")

    def test_oversize_rejected_before_allocation(self):
        self.process.stdin.write(b"999999999\n"); self.process.stdin.flush()
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.fixture_run("digest"), b"no image")

    def test_disconnect_before_commit_does_not_paste(self):
        self.stage(self.png)
        self.assertEqual(self.process.stdout.readline(), b"STAGED\n")
        self.process.stdin.close()
        self.assertNotEqual(self.process.wait(timeout=5), 0)
        self.assertEqual(self.fixture_run("digest"), b"no image")


if __name__ == "__main__":
    unittest.main()
