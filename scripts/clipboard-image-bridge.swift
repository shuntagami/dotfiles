import AppKit
import ImageIO

// No image files or clipboard contents are logged. SSH supplies authentication.
let limit = 32 * 1024 * 1024
let marker = NSPasteboard.PasteboardType("com.shuntagami.clipboard-image-bridge")
let input = FileHandle.standardInput
let output = FileHandle.standardOutput

func line() throws -> String {
    var data = Data()
    while data.count < 128 {
        guard let b = try input.read(upToCount: 1), !b.isEmpty else { throw Failure.protocolError }
        if b[0] == 10 { return String(decoding: data, as: UTF8.self) }
        data.append(b)
    }
    throw Failure.protocolError
}
func say(_ text: String) { output.write(Data((text + "\n").utf8)) }
enum Failure: Error { case protocolError, image, changed }
func validPNG(_ data: Data) -> Bool {
    guard data.count <= limit, data.starts(with: [137,80,78,71,13,10,26,10]),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = p[kCGImagePropertyPixelWidth] as? Int,
          let h = p[kCGImagePropertyPixelHeight] as? Int else { return false }
    return w > 0 && h > 0 && w <= 16384 && h <= 16384 && w * h <= 64_000_000
}
func imageFrom(_ board: NSPasteboard) -> Data? {
    let types = board.types ?? []
    guard !types.contains(marker), !types.contains(.fileURL),
          !types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) else { return nil }
    if let png = board.data(forType: .png), validPNG(png) { return png }
    guard let tiff = board.data(forType: .tiff), tiff.count <= limit,
          let source = CGImageSourceCreateWithData(tiff as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int,
          w > 0, h > 0, w <= 16384, h <= 16384, w * h <= 64_000_000,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]), validPNG(png) else { return nil }
    return png
}
func receive(_ board: NSPasteboard) throws {
    // Bound abandoned SSH clients even if they never finish sending a frame.
    DispatchQueue.global().asyncAfter(deadline: .now() + 20) { exit(75) }
    let original = board.changeCount
    say("READY")
    guard let size = Int(try line()), size > 0, size <= limit else { throw Failure.protocolError }
    var data = Data()
    while data.count < size {
        guard let chunk = try input.read(upToCount: min(65536, size - data.count)), !chunk.isEmpty else {
            throw Failure.protocolError
        }
        data.append(chunk)
    }
    guard validPNG(data) else { throw Failure.image }
    say("STAGED")
    guard try line() == "COMMIT" else { throw Failure.protocolError }
    guard board.changeCount == original else { throw Failure.changed }
    let item = NSPasteboardItem()
    item.setData(data, forType: .png)
    item.setString("received", forType: marker)
    board.clearContents()
    guard board.writeObjects([item]) else { throw Failure.image }
    say("OK")
}

// The worker never reads NSPasteboard. All source checks run on the main thread.
final class Watcher {
    let board: NSPasteboard
    let host: String
    let identity: String
    var seen: Int
    var busy = false
    var pending: (Int, Data)?
    var timer: Timer?
    init(_ board: NSPasteboard, _ host: String, _ identity: String) {
        self.board = board; self.host = host; self.identity = identity
        seen = board.changeCount // Do not replay an old image on login/restart.
    }
    func tick() {
        let count = board.changeCount
        if count != seen {
            seen = count
            pending = nil
            if let data = imageFrom(board), board.changeCount == count { pending = (count, data) }
        }
        guard !busy, let (count, data) = pending else { return }
        pending = nil; busy = true
        DispatchQueue.global().async {
            let ok = self.send(count, data)
            DispatchQueue.main.async {
                self.busy = false
                // Failed/offline transfers are dropped, not replayed much later.
                fputs(ok ? "image synced\n" : "image skipped (connection or clipboard changed)\n", stderr)
            }
        }
    }
    func send(_ count: Int, _ data: Data) -> Bool {
        let process = Process()
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-T", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
                             "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
                             "-o", "ServerAliveInterval=3", "-o", "ServerAliveCountMax=2",
                             "-o", "ControlMaster=no", "-o", "ControlPath=none",
                             "-i", identity, host, "receive"]
        process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        func readLine() throws -> String {
            var bytes = Data()
            while bytes.count < 128 {
                guard let b = try stdout.fileHandleForReading.read(upToCount: 1), !b.isEmpty else {
                    throw Failure.protocolError
                }
                if b[0] == 10 { return String(decoding: bytes, as: UTF8.self) }
                bytes.append(b)
            }
            throw Failure.protocolError
        }
        do {
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            defer {
                timeout.cancel()
                try? stdin.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
            }
            guard try readLine() == "READY" else { return false }
            try stdin.fileHandleForWriting.write(contentsOf: Data("\(data.count)\n".utf8))
            try stdin.fileHandleForWriting.write(contentsOf: data)
            guard try readLine() == "STAGED" else { return false }
            let current = DispatchQueue.main.sync { self.board.changeCount == count }
            guard current else { return false }
            try stdin.fileHandleForWriting.write(contentsOf: Data("COMMIT\n".utf8))
            return try readLine() == "OK"
        } catch { return false }
    }
    func run() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in self.tick() }
        RunLoop.main.run()
    }
}

signal(SIGPIPE, SIG_IGN)
var args = Array(CommandLine.arguments.dropFirst())
let board: NSPasteboard
if args.count >= 2 && args[0] == "--pasteboard" {
    board = NSPasteboard(name: NSPasteboard.Name(args[1])); args.removeFirst(2)
} else { board = .general }
do {
    if args == ["receive"] { try receive(board) }
    else if args.count == 3 && args[0] == "watch" {
        let watcher = Watcher(board, args[1], args[2]); watcher.run()
    } else {
        fputs("Usage: clipboard-image-bridge [--pasteboard NAME] receive | watch HOST IDENTITY\n", stderr)
        exit(64)
    }
} catch {
    fputs("transfer rejected\n", stderr)
    exit(1)
}
