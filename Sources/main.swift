import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// Notes store — override with NAS_NOTES_DIR; defaults to ~/.rpidrive/notes.
let NOTES_DIR: String = {
    let env = ProcessInfo.processInfo.environment["NAS_NOTES_DIR"] ?? ""
    return ((env.isEmpty ? "~/.rpidrive/notes" : env) as NSString).expandingTildeInPath
}()
let ASSETS_DIR = NOTES_DIR + "/assets"   // embedded images / PDFs / attachments live here
let CTD = NOTES_DIR + "/NAS.ctd"
let CHERRYTREE = "/opt/homebrew/bin/cherrytree"

struct Note { let name: String; let title: String; let category: String; let tags: [String]
              let body: String; let mtime: Double; let pinned: Bool }

// Serves note attachments to the WebView as cherry://asset/<name> — loadHTMLString
// pages can't read file:// URLs, so embedded images/PDFs go through this handler.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let name = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !name.isEmpty else { fail(task); return }
        let path = (ASSETS_DIR as NSString).appendingPathComponent(name)
        // never serve anything outside the assets folder
        let canonical = (path as NSString).standardizingPath
        guard canonical.hasPrefix((ASSETS_DIR as NSString).standardizingPath + "/"),
              let data = FileManager.default.contents(atPath: canonical) else { fail(task); return }
        let ext = (canonical as NSString).pathExtension.lowercased()
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
    private func fail(_ task: WKURLSchemeTask) { task.didFailWithError(NSError(domain: "cherry", code: 404)) }
}

// Parse an optional YAML-ish frontmatter block (--- … ---) at the very top of a note.
// Returns the category (default "General") and tags. The body is kept intact for round-trip editing;
// the UI hides the frontmatter when rendering.
func parseFrontmatter(_ body: String) -> (category: String, tags: [String], pinned: Bool) {
    var category = "General"; var tags: [String] = []; var pinned = false
    let lines = body.components(separatedBy: "\n")
    guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return (category, tags, pinned) }
    var i = 1
    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "---" {
        let parts = lines[i].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 {
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "category", !val.isEmpty { category = val }
            if key == "tags" { tags = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            if key == "pinned" { pinned = ["true","yes","1"].contains(val.lowercased()) }
        }
        i += 1
    }
    return (category, tags, pinned)
}

func loadNotes() -> [Note] {
    let fm = FileManager.default
    let preferred = ["NAS", "email"]
    let files = ((try? fm.contentsOfDirectory(atPath: NOTES_DIR)) ?? []).filter { $0.hasSuffix(".md") }
    func loadOne(_ base: String) -> Note? {
        let path = NOTES_DIR + "/" + base + ".md"
        guard let body = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var title = base
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") { title = String(line.dropFirst(2)); break }
        }
        let (category, tags, pinned) = parseFrontmatter(body)
        let mtime = ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Note(name: base, title: title, category: category, tags: tags, body: body, mtime: mtime, pinned: pinned)
    }
    var notes: [Note] = []; var used = Set<String>()
    for base in preferred where files.contains(base + ".md") {
        if let n = loadOne(base) { notes.append(n); used.insert(base + ".md") }
    }
    for f in files.sorted() where !used.contains(f) {
        if let n = loadOne(String(f.dropLast(3))) { notes.append(n) }
    }
    // Pinned first; then the preferred/alphabetical base order gives way to recency.
    let pinnedNotes = notes.filter { $0.pinned }.sorted { $0.mtime > $1.mtime }
    let preferredNotes = notes.filter { !$0.pinned && preferred.contains($0.name) }
    let rest = notes.filter { !$0.pinned && !preferred.contains($0.name) }.sorted { $0.mtime > $1.mtime }
    return pinnedNotes + preferredNotes + rest
}

func jsonString(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
    var str = String(data: data, encoding: .utf8)!
    str.removeFirst(); str.removeLast()   // strip the [ ]
    // "</script>" inside a note/draft must not terminate the inline <script> block
    return str.replacingOccurrences(of: "</", with: "<\\/")
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var web: WKWebView!
    var notes: [Note] = []
    let clips = ClipStore()
    var clipTimer: Timer?

    // Draft preservation: the editor state survives the popover closing (and app relaunch).
    var savedDraft: [String: Any]? {
        get { UserDefaults.standard.dictionary(forKey: "pendingDraft") }
        set { if let d = newValue { UserDefaults.standard.set(d, forKey: "pendingDraft") }
              else { UserDefaults.standard.removeObject(forKey: "pendingDraft") } }
    }
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        installEditMenu()   // gives the editor ⌘X/⌘C/⌘V/⌘A/⌘Z (menu-bar apps have no menu otherwise)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.title = "🍒"   // emoji only — keeps the menu-bar footprint tiny so it isn't pushed behind the notch
            b.toolTip = "Cherry — notes (⌃⌥⌘C)"
            b.target = self; b.action = #selector(toggle(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])   // right-click → settings menu
        }
        try? FileManager.default.createDirectory(atPath: ASSETS_DIR, withIntermediateDirectories: true)
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "bridge")
        cfg.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "cherry")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 680), configuration: cfg)
        web.uiDelegate = self   // route JS alert/confirm/prompt to native panels
        let vc = NSViewController(); vc.view = web
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 600, height: 680)
        popover.behavior = .transient
        popover.delegate = self
        // watch the clipboard in the background so history accumulates even when the panel is closed
        clipTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.clips.poll() }
        registerHotKey()   // ⌃⌥⌘C toggles Cherry from anywhere
        render()
    }

    // MARK: global hotkey (⌃⌥⌘C) — Carbon, no permissions needed
    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggleFromHotKey() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x43485259) /* 'CHRY' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    func toggleFromHotKey() {
        if popover.isShown { popover.performClose(nil) } else { render(view: savedDraft != nil ? "edit" : "home"); openPopover() }
    }

    // MARK: right-click settings menu on the menu-bar cherry
    func showContextMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "New Note  (⌘N)", action: #selector(menuNewNote), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clipboard History", action: #selector(menuClips), keyEquivalent: "").target = self
        m.addItem(.separator())
        let snd = NSMenuItem(title: "Capture Sound", action: #selector(menuToggleSound), keyEquivalent: "")
        snd.target = self; snd.state = ClipStore.soundOn ? .on : .off; m.addItem(snd)
        if #available(macOS 13.0, *) {
            let li = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
            li.target = self; li.state = SMAppService.mainApp.status == .enabled ? .on : .off; m.addItem(li)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Cherry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // detach so plain left-click keeps toggling the popover
    }
    @objc func menuNewNote() { render(view: "new"); openPopover() }
    @objc func menuClips() { render(view: "clips"); openPopover() }
    @objc func menuToggleSound() {
        ClipStore.soundOn.toggle()
        if ClipStore.soundOn { clips.playSound(volume: 1.0) }
    }
    @objc func menuToggleLogin() {
        if #available(macOS 13.0, *) {
            let svc = SMAppService.mainApp
            do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } }
            catch { notify("Launch at Login", "Couldn't change setting: \(error.localizedDescription)") }
        }
    }

    // Snapshot the editor before the popover closes so nothing typed is ever lost.
    func popoverWillClose(_ notification: Notification) {
        web.evaluateJavaScript("window.__snapDraft ? __snapDraft() : null") { [weak self] res, _ in
            guard let self = self else { return }
            if let d = res as? [String: Any], (d["body"] as? String) != nil { self.savedDraft = d }
        }
    }

    // A menu-bar (accessory) app has no main menu, so standard editing key equivalents
    // (⌘C/⌘V/⌘X/⌘A/⌘Z) never reach the WKWebView — pasting a link into a note "does nothing".
    // Installing a minimal Edit menu wires those actions back up through the responder chain.
    func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    // MARK: WKUIDelegate — native alert/confirm/prompt (WKWebView shows none by default)
    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK")
        a.runModal(); completionHandler()
    }
    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = defaultText ?? ""; a.accessoryView = tf
        a.window.initialFirstResponder = tf
        completionHandler(a.runModal() == .alertFirstButtonReturn ? tf.stringValue : nil)
    }

    func render(view: String = "home", active: Int = 0) {
        notes = loadNotes()
        let items = notes.map { n in
            let tagArr = "[" + n.tags.map { jsonString($0) }.joined(separator: ",") + "]"
            return "{name:\(jsonString(n.name)),title:\(jsonString(n.title)),category:\(jsonString(n.category)),tags:\(tagArr),body:\(jsonString(n.body)),mtime:\(Int(n.mtime)),pinned:\(n.pinned)}"
        }.joined(separator: ",")
        let idx = (active >= 0 && active < notes.count) ? active : 0
        let draftJSON: String = {
            guard let d = savedDraft, let data = try? JSONSerialization.data(withJSONObject: d) else { return "null" }
            return (String(data: data, encoding: .utf8) ?? "null").replacingOccurrences(of: "</", with: "<\\/")
        }()
        let html = htmlTemplate
            .replacingOccurrences(of: "/*__NOTES__*/", with: "[\(items)]")
            .replacingOccurrences(of: "/*__CLIPS__*/", with: clips.injectJSON())
            .replacingOccurrences(of: "/*__VIEW__*/", with: view)
            .replacingOccurrences(of: "/*__ACTIVE__*/", with: String(idx))
            .replacingOccurrences(of: "/*__DRAFT__*/null", with: draftJSON)
        web.loadHTMLString(html, baseURL: nil)
    }

    // Open the popover focused on a given note (by file name or tab title). Used by the per-note Spotlight apps.
    func showNote(named name: String) {
        let want = name.lowercased()
        notes = loadNotes()
        let idx = notes.firstIndex { $0.name.lowercased() == want || $0.title.lowercased() == want } ?? 0
        render(view: "note", active: idx)
        openPopover()
    }

    func openPopover() {
        NSApp.activate(ignoringOtherApps: true)
        if let b = statusItem.button {
            if popover.isShown { popover.performClose(nil) }
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    // Persist edits, then regenerate the CherryTree doc + Spotlight launchers in the background.
    func rebuild() {
        let sh = NOTES_DIR + "/rebuild.sh"
        guard FileManager.default.isExecutableFile(atPath: sh) else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [sh]
        try? p.run()
    }

    // custom URL scheme: nasnote://<name>
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URLComponents(string: s) else { return }
        let name = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        showNote(named: name)
    }

    @objc func toggle(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if popover.isShown { popover.performClose(sender); return }
        // reload notes each open so edits show up; resume an interrupted edit if one exists
        render(view: savedDraft != nil ? "edit" : "home")
        openPopover()
    }

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "copy":
            let text = (body["text"] as? String) ?? ""
            let pb = NSPasteboard.general; pb.clearContents(); pb.setString(text, forType: .string)
            // feedback is the in-app toast + capture sound — no system banner (and no banner "trub")
        case "cherrytree":
            openCherryTree()
        case "reveal":
            NSWorkspace.shared.selectFile(CTD, inFileViewerRootedAtPath: NOTES_DIR)
        case "edit":
            let name = (body["name"] as? String) ?? "NAS"
            NSWorkspace.shared.open(URL(fileURLWithPath: NOTES_DIR + "/" + name + ".md"))
        case "save":
            guard let name = body["name"] as? String, !name.isEmpty,
                  let text = body["text"] as? String ?? body["body"] as? String else { break }
            let safe = name.replacingOccurrences(of: "/", with: "-")
            try? FileManager.default.createDirectory(atPath: NOTES_DIR, withIntermediateDirectories: true)
            try? text.write(toFile: NOTES_DIR + "/" + safe + ".md", atomically: true, encoding: .utf8)
            savedDraft = nil
            rebuild()
        case "delete":
            guard let name = body["name"] as? String, !name.isEmpty else { break }
            let safe = name.replacingOccurrences(of: "/", with: "-")
            // recoverable: the note goes to the macOS Trash, not straight to oblivion
            try? FileManager.default.trashItem(at: URL(fileURLWithPath: NOTES_DIR + "/" + safe + ".md"), resultingItemURL: nil)
            rebuild()
        case "clip-copy":
            if let id = body["id"] as? String { clips.copyBack(id) }   // in-app toast handles feedback
        case "clip-copy-path":
            if let id = body["id"] as? String { clips.copyPath(id) }
        case "clip-copy-file":
            if let id = body["id"] as? String { clips.copyFile(id) }
        case "clip-open":
            if let id = body["id"] as? String, let it = clips.items.first(where: { ($0["id"] as? String) == id }),
               let p = it["path"] as? String { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        case "clip-reveal":
            if let id = body["id"] as? String, let it = clips.items.first(where: { ($0["id"] as? String) == id }),
               let p = it["path"] as? String { NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: "") }
        case "clip-fav":
            if let id = body["id"] as? String { clips.setFav(id, (body["fav"] as? Bool) ?? true) }
        case "clip-delete":
            if let id = body["id"] as? String { clips.delete(id) }
        case "clip-clear":
            clips.clearAll()
        case "attach":
            attachViaPanel()
        case "paste-attach":
            pasteAttach()
        case "open-asset":
            if let f = body["file"] as? String, let p = assetPath(f) { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        case "reveal-asset":
            if let f = body["file"] as? String, let p = assetPath(f) { NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: ASSETS_DIR) }
        case "copy-asset-path":
            if let f = body["file"] as? String, let p = assetPath(f) {
                let pb = NSPasteboard.general; pb.clearContents(); pb.setString(p, forType: .string)
            }
        case "draft":
            savedDraft = ["name": body["name"] as? String ?? "",
                          "body": body["body"] as? String ?? "",
                          "isNew": body["isNew"] as? Bool ?? false]
        case "draft-clear":
            savedDraft = nil
        case "export-pdf":
            exportPDF(title: body["name"] as? String ?? "note")
        case "quit":
            NSApp.terminate(nil)
        default: break
        }
    }

    // MARK: attachments (embedded images / PDFs / files)
    private func assetPath(_ file: String) -> String? {
        let p = ((ASSETS_DIR as NSString).appendingPathComponent(file) as NSString).standardizingPath
        guard p.hasPrefix((ASSETS_DIR as NSString).standardizingPath + "/"),
              FileManager.default.fileExists(atPath: p) else { return nil }
        return p
    }
    // Copy a file into assets/ under a collision-free name and return that name.
    private func importAsset(from url: URL) -> String? {
        try? FileManager.default.createDirectory(atPath: ASSETS_DIR, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "]", with: ")")
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        var name = "\(base).\(ext)"; var i = 2
        while FileManager.default.fileExists(atPath: ASSETS_DIR + "/" + name) { name = "\(base)-\(i).\(ext)"; i += 1 }
        do { try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: ASSETS_DIR + "/" + name)); return name }
        catch { return nil }
    }
    private func importAsset(data: Data, ext: String, base: String) -> String? {
        try? FileManager.default.createDirectory(atPath: ASSETS_DIR, withIntermediateDirectories: true)
        var name = "\(base).\(ext)"; var i = 2
        while FileManager.default.fileExists(atPath: ASSETS_DIR + "/" + name) { name = "\(base)-\(i).\(ext)"; i += 1 }
        do { try data.write(to: URL(fileURLWithPath: ASSETS_DIR + "/" + name)); return name }
        catch { return nil }
    }
    private func snippet(for name: String) -> String {
        let e = (name as NSString).pathExtension.lowercased()
        let images = ["png","jpg","jpeg","gif","heic","webp","tiff","tif","bmp","svg"]
        return images.contains(e) ? "\n![\(name)](assets/\(name))\n" : "\n[\(name)](assets/\(name))\n"
    }
    private func insertInEditor(_ names: [String]) {
        guard !names.isEmpty else { return }
        let snip = names.map { snippet(for: $0) }.joined()
        web.evaluateJavaScript("window.__insertSnippet && __insertSnippet(\(jsonString(snip)))", completionHandler: nil)
    }
    func attachViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach images, PDFs or files — they're copied into the note's assets folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        insertInEditor(panel.urls.compactMap { importAsset(from: $0) })
    }
    // Paste straight into the editor: file URLs or raw image data on the pasteboard become attachments.
    func pasteAttach() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            insertInEditor(urls.compactMap { importAsset(from: $0) }); return
        }
        if let types = pb.types, types.contains(.png) || types.contains(.tiff), let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let stamp = Int(Date().timeIntervalSince1970)
            if let name = importAsset(data: png, ext: "png", base: "pasted-\(stamp)") { insertInEditor([name]) }
        }
    }

    // MARK: export the open note as a PDF
    func exportPDF(title: String) {
        // let the page grow to its full height so the PDF isn't clipped to the viewport
        web.evaluateJavaScript("window.__preparePDF ? __preparePDF() : document.body.scrollHeight") { [weak self] h, _ in
            guard let self = self else { return }
            let height = max((h as? Double) ?? 680, 100)
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: Double(self.web.frame.width), height: height)
            self.web.createPDF(configuration: cfg) { result in
                self.web.evaluateJavaScript("window.__endPDF && __endPDF()", completionHandler: nil)
                guard case .success(let data) = result else { return }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + ".pdf"
                if #available(macOS 11.0, *) { panel.allowedContentTypes = [.pdf] }
                NSApp.activate(ignoringOtherApps: true)
                if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
            }
        }
    }

    func openCherryTree() {
        if FileManager.default.isExecutableFile(atPath: CHERRYTREE) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: CHERRYTREE)
            p.arguments = [CTD]
            do { try p.run() } catch { NSWorkspace.shared.open(URL(fileURLWithPath: CTD)) }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: CTD))
        }
        popover.performClose(nil)
    }

    func notify(_ title: String, _ text: String) {
        let n = NSUserNotification(); n.title = title; n.informativeText = text
        NSUserNotificationCenter.default.deliver(n)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
