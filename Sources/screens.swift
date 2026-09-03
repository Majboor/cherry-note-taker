import Cocoa
import AVFoundation

// Screen capture history: watches the macOS screenshot/recording save folder and files every
// new capture into its own tab. Unlike ClipStore, the files are the user's own (on the Desktop,
// usually) — Cherry never moves or deletes them; it only remembers a pointer, a thumbnail, and an
// optional note you attach. "Reveal" jumps to the file in Finder; "Open" opens it.
final class ScreenStore {
    static let shared = ScreenStore()

    static let dir: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NASNotes").appendingPathComponent("screens").path
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }()
    static let jsonPath = dir + "/screens.json"
    static let maxItems = 200

    var items: [[String: Any]] = []          // newest first
    private var seen = Set<String>()          // every path ever imported — survives deletion so we don't re-add
    private var seq = 0
    private let baseline: TimeInterval        // ignore captures older than first launch (no Desktop backfill)

    private static let imageExt = ["png","jpg","jpeg","heic","heif","gif","tiff","tif","bmp","webp"]
    private static let videoExt = ["mov","mp4","m4v","webm","avi","mkv","hevc"]

    init() {
        if let b = UserDefaults.standard.object(forKey: "screenBaseline") as? Double {
            baseline = b
        } else {
            let now = Date().timeIntervalSince1970
            UserDefaults.standard.set(now, forKey: "screenBaseline")
            baseline = now
        }
        load()
        for it in items { if let p = it["path"] as? String { seen.insert(p) } }
        for p in (UserDefaults.standard.array(forKey: "screenRemoved") as? [String] ?? []) { seen.insert(p) }
    }

    // Where macOS drops screenshots / recordings (Screenshot.app "Save to" setting). Default: Desktop.
    static func captureDir() -> String {
        if let v = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !v.isEmpty {
            return (v as NSString).expandingTildeInPath
        }
        return ("~/Desktop" as NSString).expandingTildeInPath
    }

    // MARK: persistence
    func load() {
        if let d = try? Data(contentsOf: URL(fileURLWithPath: ScreenStore.jsonPath)),
           let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { items = a }
    }
    func save() {
        if let d = try? JSONSerialization.data(withJSONObject: items, options: []) {
            try? d.write(to: URL(fileURLWithPath: ScreenStore.jsonPath))
        }
    }
    private func newID() -> String { seq += 1; return "\(Int(Date().timeIntervalSince1970 * 1000))-\(seq)" }

    // MARK: detection
    // macOS tags every screen capture with the kMDItemIsScreenCapture extended attribute the moment
    // the file is finalized — the strong, locale-independent signal. Fall back to the (localized)
    // "Screenshot / Screen Recording" filename only if the xattr is somehow absent.
    private func isScreenCapture(_ path: String) -> Bool {
        if getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0 { return true }
        let n = (path as NSString).lastPathComponent
        return n.range(of: "^(Screenshot|Screen Recording|Screen Shot|CleanShot)",
                       options: [.regularExpression, .caseInsensitive]) != nil
    }
    private func kindFor(_ path: String) -> String {
        let e = (path as NSString).pathExtension.lowercased()
        return ScreenStore.videoExt.contains(e) ? "video" : "image"
    }

    // MARK: polling — called on the same 1s timer as the clipboard watcher
    @discardableResult
    func poll() -> Bool {
        let dir = ScreenStore.captureDir()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return false }
        var added = false
        for name in names {
            if name.hasPrefix(".") { continue }
            let e = (name as NSString).pathExtension.lowercased()
            guard ScreenStore.imageExt.contains(e) || ScreenStore.videoExt.contains(e) else { continue }
            let path = dir + "/" + name
            if seen.contains(path) { continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            let ctime = (attrs[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
            if ctime < baseline { seen.insert(path); continue }   // pre-existing file → ignore forever
            let size = (attrs[.size] as? Int) ?? 0
            if size == 0 { continue }                              // still being written — retry next tick
            guard isScreenCapture(path) else { continue }         // xattr not set yet (or not a capture)
            addFile(path: path, kind: kindFor(path), ts: ctime)
            added = true
        }
        if added { trimAndSave() }
        return added
    }

    private func addFile(path: String, kind: String, ts: TimeInterval) {
        seen.insert(path)
        var it: [String: Any] = ["id": newID(), "ts": ts, "path": path,
                                 "name": (path as NSString).lastPathComponent, "kind": kind, "note": ""]
        if let thumb = makeThumb(path: path, kind: kind) { it["thumb"] = thumb }
        items.insert(it, at: 0)
    }

    private func makeThumb(path: String, kind: String) -> String? {
        if kind == "image", let img = NSImage(contentsOfFile: path) { return thumbURI(img) }
        if kind == "video" {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 440, height: 440)
            let t = CMTime(seconds: 0.2, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                return thumbURI(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
        }
        return nil
    }

    private func thumbURI(_ img: NSImage, maxDim: CGFloat = 240) -> String {
        let sz = img.size
        guard sz.width > 0, sz.height > 0 else { return "" }
        let scale = min(1, maxDim / max(sz.width, sz.height))
        let w = max(1, Int(sz.width * scale)), h = max(1, Int(sz.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private func trimAndSave() {
        if items.count > ScreenStore.maxItems { items = Array(items.prefix(ScreenStore.maxItems)) }
        save()
    }

    // MARK: bridge actions
    func item(_ id: String) -> [String: Any]? { items.first { ($0["id"] as? String) == id } }
    func path(_ id: String) -> String? { item(id)?["path"] as? String }

    func setNote(_ id: String, _ note: String) {
        if let i = items.firstIndex(where: { ($0["id"] as? String) == id }) {
            items[i]["note"] = note; save()
        }
    }
    // Forget a capture from Cherry (the file on disk is left untouched) and don't re-import it.
    func forget(_ id: String) {
        if let p = path(id) {
            var removed = UserDefaults.standard.array(forKey: "screenRemoved") as? [String] ?? []
            if !removed.contains(p) { removed.append(p); UserDefaults.standard.set(removed, forKey: "screenRemoved") }
            seen.insert(p)
        }
        items.removeAll { ($0["id"] as? String) == id }
        save()
    }
    func copyFile(_ id: String) {
        guard let p = path(id) else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: p) as NSURL])
    }

    // Compact JSON for the WebView. Full-res preview is streamed on demand via cherry://screen/<id>.
    func injectJSON() -> String {
        let out: [[String: Any]] = items.prefix(ScreenStore.maxItems).compactMap { it in
            guard let p = it["path"] as? String, FileManager.default.fileExists(atPath: p) else { return nil }
            var o: [String: Any] = ["id": it["id"] ?? "", "ts": it["ts"] ?? 0,
                                    "kind": it["kind"] ?? "image", "name": it["name"] ?? "",
                                    "path": p, "note": it["note"] as? String ?? ""]
            if let th = it["thumb"] { o["thumb"] = th }
            return o
        }
        return (try? String(data: JSONSerialization.data(withJSONObject: out), encoding: .utf8)) ?? "[]"
    }
}
