import Cocoa
import WebKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// Notes store. Order: $NAS_NOTES_DIR, then `defaults write com.hico.nasnotes notesDir <path>`,
// then ~/.rpidrive/notes if it already exists (older installs), else ~/Documents/Cherry.
let NOTES_DIR: String = {
    let env = ProcessInfo.processInfo.environment["NAS_NOTES_DIR"] ?? ""
    if !env.isEmpty { return (env as NSString).expandingTildeInPath }
    if let d = UserDefaults.standard.string(forKey: "notesDir"), !d.isEmpty { return (d as NSString).expandingTildeInPath }
    let legacy = ("~/.rpidrive/notes" as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: legacy) { return legacy }
    return ("~/Documents/Cherry" as NSString).expandingTildeInPath
}()

/// First run from a downloaded build: create the notes folder, seed a welcome note, and put the
/// helper scripts (bundled in Resources) next to the notes, where the rebuild step expects them.
/// Never overwrites scripts or notes that are already there.
func prepareNotesDir() {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: NOTES_DIR, withIntermediateDirectories: true)
    guard let res = Bundle.main.resourcePath else { return }
    for s in ["rebuild.sh", "make-launchers.sh"] {
        let dst = NOTES_DIR + "/" + s, src = res + "/" + s
        if !fm.fileExists(atPath: dst), fm.fileExists(atPath: src) {
            try? fm.copyItem(atPath: src, toPath: dst)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
        }
    }
    let hasNotes = ((try? fm.contentsOfDirectory(atPath: NOTES_DIR)) ?? []).contains { $0.hasSuffix(".md") }
    if !hasNotes, fm.fileExists(atPath: res + "/welcome.md") {
        try? fm.copyItem(atPath: res + "/welcome.md", toPath: NOTES_DIR + "/welcome.md")
    }
}
let ASSETS_DIR = NOTES_DIR + "/assets"   // embedded images / PDFs / attachments live here
let CTD = NOTES_DIR + "/NAS.ctd"
let CHERRYTREE = ["/opt/homebrew/bin/cherrytree", "/usr/local/bin/cherrytree"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/cherrytree"

struct Note { let name: String; let title: String; let category: String; let tags: [String]
              let body: String; let mtime: Double; let pinned: Bool; let parent: String? }

// Serves note attachments to the WebView as cherry://asset/<name> — loadHTMLString
// pages can't read file:// URLs, so embedded images/PDFs go through this handler.
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    weak var clips: ClipStore?
    init(clips: ClipStore) { self.clips = clips }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let name = url.path.removingPercentEncoding?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !name.isEmpty else { fail(task); return }
        // cherry://cthumb/<id> and cherry://sthumb/<id> → clipboard / screen-capture thumbnails.
        // They used to ride inline in the page as base64 (≈2.7 MB per open); now the page only
        // carries ids and the browser pulls each thumbnail when it scrolls into view.
        if url.host == "cthumb" || url.host == "sthumb" {
            let items = url.host == "cthumb" ? (clips?.items ?? []) : ScreenStore.shared.items
            guard let it = items.first(where: { ($0["id"] as? String) == name }),
                  let uri = it["thumb"] as? String, let comma = uri.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { fail(task); return }
            let mime = uri.hasPrefix("data:image/jpeg") ? "image/jpeg" : "image/png"
            let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
            task.didReceive(resp); task.didReceive(data); task.didFinish(); return
        }
        // cherry://screen/<id> → stream a captured screenshot/recording by id (path validated against the store)
        if url.host == "screen" {
            guard let path = ScreenStore.shared.path(name),
                  let data = FileManager.default.contents(atPath: path) else { fail(task); return }
            let ext = (path as NSString).pathExtension.lowercased()
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            let resp = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil)
            task.didReceive(resp); task.didReceive(data); task.didFinish(); return
        }
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
func parseFrontmatter(_ body: String) -> (category: String, tags: [String], pinned: Bool, parent: String?) {
    var category = "General"; var tags: [String] = []; var pinned = false; var parent: String? = nil
    let lines = body.components(separatedBy: "\n")
    guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return (category, tags, pinned, parent) }
    var i = 1
    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "---" {
        let parts = lines[i].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if parts.count == 2 {
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "category", !val.isEmpty { category = val }
            if key == "tags" { tags = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            if key == "pinned" { pinned = ["true","yes","1"].contains(val.lowercased()) }
            if key == "parent", !val.isEmpty { parent = val }
        }
        i += 1
    }
    return (category, tags, pinned, parent)
}

// Ordinary notes (run logs excluded) in display order, served from the in-memory store after a
// cheap incremental refresh. Callers that just need the cached list should use NoteStore directly.
func loadNotes() -> [Note] {
    NoteStore.shared.scan()
    return NoteStore.shared.notes()
}

func jsonString(_ s: String) -> String {
    // Encode as a JSON string safely. (A malformed note must never crash the app, so no try!.)
    let data = (try? JSONSerialization.data(withJSONObject: [s], options: [])) ?? Data("[\"\"]".utf8)
    var str = String(data: data, encoding: .utf8) ?? "\"\""
    str.removeFirst(); str.removeLast()   // strip the [ ]
    // "</script>" inside a note/draft must not terminate the inline <script> block
    return str.replacingOccurrences(of: "</", with: "<\\/")
}

// Coalesces rapid note saves into ONE background rebuild of NAS.ctd + the Spotlight launchers.
// Every save/delete/drag used to spawn its own `rebuild.sh` — which re-codesigns a launcher app
// per note — so a burst of edits stacked dozens of overlapping shell runs that thrashed the disk
// and stalled the UI (the "hang when adding notes"). This debounces bursts and runs strictly one
// rebuild at a time, entirely off the main thread.
final class RebuildCoordinator {
    static let shared = RebuildCoordinator()
    private let queue = DispatchQueue(label: "com.hico.cherry.rebuild")
    private var pending: DispatchWorkItem?
    private var running = false
    private var again = false

    func schedule() {
        queue.async { [self] in
            pending?.cancel()
            let item = DispatchWorkItem { [self] in self.fire() }
            pending = item
            queue.asyncAfter(deadline: .now() + 0.6, execute: item)   // trailing debounce
        }
    }
    private func fire() {   // always on `queue`
        if running { again = true; return }
        let sh = NOTES_DIR + "/rebuild.sh"
        guard FileManager.default.isExecutableFile(atPath: sh) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [sh]
        var env = ProcessInfo.processInfo.environment; env["NAS_NOTES_DIR"] = NOTES_DIR
        p.environment = env   // the script's own default is ~/.rpidrive/notes
        p.terminationHandler = { [self] _ in
            queue.async { [self] in
                running = false
                if again { again = false; fire() }   // saves arrived mid-run → one more pass
            }
        }
        running = true
        do { try p.run() } catch { running = false }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var web: WKWebView!
    // The popover page is loaded once and kept alive; clicks just tell it which view to show.
    var pageReady = false
    var pendingShow: [String: Any]?
    let clips = ClipStore()
    let screens = ScreenStore.shared
    var clipTimer: Timer?

    // Draft preservation: the editor state survives the popover closing (and app relaunch).
    var savedDraft: [String: Any]? {
        get { UserDefaults.standard.dictionary(forKey: "pendingDraft") }
        set { if let d = newValue { UserDefaults.standard.set(d, forKey: "pendingDraft") }
              else { UserDefaults.standard.removeObject(forKey: "pendingDraft") } }
    }
    var hotKeyRef: EventHotKeyRef?
    var hotKeyRef2: EventHotKeyRef?

    // Launching the app again (e.g. from Spotlight) while it's already running
    // opens the full-screen Liquid Glass window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        GlassWindowController.shared.show()
        return true
    }

    // Menu-bar app: closing the window must never quit it — it lives in the ribbon.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ n: Notification) {
        prepareNotesDir()
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        installEditMenu()   // gives the editor ⌘X/⌘C/⌘V/⌘A/⌘Z (menu-bar apps have no menu otherwise)
        statusItem = NSStatusBar.system.statusItem(withLength: 34)
        if let b = statusItem.button {
            b.title = ""
            b.toolTip = "Cherry — notes (⌃⌥⌘C) · full screen (⌃⌥⌘N)"
            b.target = self; b.action = #selector(toggle(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])   // right-click → settings menu
            // googly eyes that follow the cursor; clicks pass through to the button
            let eyes = GooglyEyesView(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
            eyes.autoresizingMask = [.width, .height]
            b.addSubview(eyes)
        }
        try? FileManager.default.createDirectory(atPath: ASSETS_DIR, withIntermediateDirectories: true)
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "bridge")
        cfg.setURLSchemeHandler(AssetSchemeHandler(clips: clips), forURLScheme: "cherry")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 680), configuration: cfg)
        web.uiDelegate = self   // route JS alert/confirm/prompt to native panels
        web.navigationDelegate = self   // reload the page if WebKit's content process dies
        let vc = NSViewController(); vc.view = web
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 600, height: 680)
        popover.behavior = .transient
        popover.delegate = self
        // watch the clipboard + the screenshot folder in the background so both histories
        // accumulate even when the panel is closed
        clipTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.clips.poll(); self?.screens.poll()
        }
        registerHotKey()   // ⌃⌥⌘C toggles Cherry from anywhere
        // Index the notes folder once, then keep the index fresh from a folder watcher; any change
        // is pushed straight into the live page (and the full-screen window) — no reload per click.
        NoteStore.shared.onChange = { [weak self] changed in self?.notesChanged(changed) }
        NoteStore.shared.startWatching()
        loadPage()
    }

    // MARK: global hotkey (⌃⌥⌘C) — Carbon, no permissions needed
    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                if hkID.id == 2 { GlassWindowController.shared.toggle() }   // ⌃⌥⌘N → full screen
                else { me.toggleFromHotKey() }                              // ⌃⌥⌘C → popover
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        let sig = OSType(0x43485259) /* 'CHRY' */
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey | cmdKey),
                            EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &hotKeyRef)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey),
                            EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &hotKeyRef2)
    }
    func toggleFromHotKey() {
        if popover.isShown { popover.performClose(nil) } else { showHome(); openPopover() }
    }

    // MARK: right-click settings menu on the menu-bar cherry
    func showContextMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Open Full Screen  (⌃⌥⌘N)", action: #selector(menuFullScreen), keyEquivalent: "").target = self
        m.addItem(withTitle: "New Note  (⌘N)", action: #selector(menuNewNote), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clipboard History", action: #selector(menuClips), keyEquivalent: "").target = self
        m.addItem(withTitle: "Screen Captures", action: #selector(menuScreens), keyEquivalent: "").target = self
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
    @objc func menuFullScreen() { GlassWindowController.shared.show() }
    @objc func menuNewNote() { show(["view": "new"]); openPopover() }
    @objc func menuClips() { show(["view": "clips"]); openPopover() }
    @objc func menuScreens() { show(["view": "screens"]); openPopover() }
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

        // Application menu (needed for ⌘Q and a real app menu when the glass window is open)
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Hide Cherry", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Cherry", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu (New note, Close window)
        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        file.addItem(withTitle: "New Note", action: #selector(menuNewNote), keyEquivalent: "n").target = self
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

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

    // MARK: the popover page — built once, then driven with small JS calls

    func notesJSON() -> String { jsText(NoteStore.shared.notes().map { NoteStore.shared.meta($0) }) }

    /// Load the page. The only data baked in is the slim note index (title/category/tags/preview —
    /// no bodies); bodies, run logs, clipboard and screen lists are fetched on demand.
    func loadPage() {
        pageReady = false
        NoteStore.shared.ensureScanned()
        web.loadHTMLString(htmlTemplate.replacingOccurrences(of: "/*__NOTES__*/", with: notesJSON()), baseURL: nil)
    }
    func js(_ code: String) { web.evaluateJavaScript(code, completionHandler: nil) }

    /// Tell the live page which view to show (queued until the page has booted).
    func show(_ cmd: [String: Any]) {
        if pageReady { js("window.__show(\(jsText(cmd)))") } else { pendingShow = cmd }
        // Catch edits the folder watcher can't see (in-place writes by other tools) — off the main thread.
        NoteStore.shared.scheduleScan()
    }
    func showHome() {
        var cmd: [String: Any] = ["view": savedDraft != nil ? "edit" : "home"]
        if let d = savedDraft { cmd["draft"] = d }
        show(cmd)
    }
    /// Push the refreshed index into the page (and the full-screen window, if it's open).
    func notesChanged(_ changed: Set<String>) {
        if pageReady { js("window.__setNotes(\(notesJSON()), \(jsText(Array(changed))))") }
        // Refresh the full-screen window too — but never under an unsaved draft, and not for run logs.
        let g = GlassWindowController.shared
        if let w = g.window, w.isVisible, !g.store.dirty, !g.store.isNew, changed.contains(where: { !isRunLogName($0) }) { g.store.reload() }
    }
    /// A crashed WebKit content process leaves a blank popover — rebuild the page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadPage() }

    // Open the popover focused on a given note (by file name or tab title). Used by the per-note Spotlight apps.
    func showNote(named name: String) {
        let want = name.lowercased()
        let all = NoteStore.shared.notes() + NoteStore.shared.runs()
        let n = all.first { $0.name.lowercased() == want || $0.title.lowercased() == want }
        if let n = n { show(["view": "note", "name": n.name]) } else { show(["view": "home"]) }
        openPopover()
    }

    func openPopover() {
        NSApp.activate(ignoringOtherApps: true)
        guard let b = statusItem.button else { return }
        // If it's already up, show() has already switched its view — don't tear the
        // window down and re-show it in the same runloop tick. That close+show churn (and poking
        // the popover's private window with makeKeyAndOrderFront) is what drove the intermittent
        // _NSWindowTransformAnimation over-release crash during CoreAnimation commit.
        if popover.isShown { return }
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    // Persist edits, then regenerate the CherryTree doc + Spotlight launchers — debounced and
    // serialized off the main thread so a burst of saves can't stack overlapping rebuilds.
    func rebuild() { RebuildCoordinator.shared.schedule() }

    // custom URL scheme: nasnote://<name>
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URLComponents(string: s) else { return }
        let name = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        showNote(named: name)
    }

    @objc func toggle(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        // Left-click the ribbon eyes → the quick-note popover (as before).
        if popover.isShown { popover.performClose(sender); return }
        showHome()
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
            NoteStore.shared.write(name: safe, body: text)   // file + index together
            savedDraft = nil
            rebuild()
            notesChanged([safe])
        case "delete":
            guard let name = body["name"] as? String, !name.isEmpty else { break }
            let safe = name.replacingOccurrences(of: "/", with: "-")
            NoteStore.shared.delete(name: safe)   // recoverable: goes to the macOS Trash
            rebuild()
            notesChanged([safe])
        // ---- on-demand data for the live page ----
        case "ready":   // page script finished booting
            pageReady = true
            if let p = pendingShow { pendingShow = nil; show(p) }
        case "body":    // full text (+ backlinks) of one note, fetched when it's opened
            guard let name = body["name"] as? String, let n = NoteStore.shared.note(name) else { break }
            let bl = NoteStore.shared.backlinks(to: n).map { ["name": $0.name, "title": $0.title] }
            js("window.__body(\(jsText(["name": name, "body": n.body, "backlinks": bl])))")
        case "runs":    // one page of run logs (agent filter / search / offset)
            let agent = (body["agent"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let q = body["q"] as? String ?? ""
            let offset = body["offset"] as? Int ?? 0, limit = body["limit"] as? Int ?? 40
            DispatchQueue.global(qos: .userInitiated).async {
                let page = NoteStore.shared.runsPage(agent: agent, q: q, offset: offset, limit: limit)
                DispatchQueue.main.async { self.js("window.__runsPage(\(jsText(page)))") }
            }
        case "search":  // full-text search across ordinary notes (titles/tags/previews match locally)
            let q = body["q"] as? String ?? ""
            DispatchQueue.global(qos: .userInitiated).async {
                let names = NoteStore.shared.search(q)
                DispatchQueue.main.async { self.js("window.__searchResult(\(jsText(["q": q, "names": names])))") }
            }
        case "clips":
            js("window.__clips(\(clips.injectJSON()))")
        case "screens":
            js("window.__screens(\(screens.injectJSON()))")
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
        case "screen-open":
            if let id = body["id"] as? String, let p = screens.path(id) { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        case "screen-reveal":
            if let id = body["id"] as? String, let p = screens.path(id) { NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: "") }
        case "screen-copy-file":
            if let id = body["id"] as? String { screens.copyFile(id) }
        case "screen-note":
            if let id = body["id"] as? String { screens.setNote(id, (body["note"] as? String) ?? "") }
        case "screen-delete":
            if let id = body["id"] as? String { screens.forget(id) }
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
        case "open-app":
            popover.performClose(nil)
            GlassWindowController.shared.show()
        case "open-note":
            popover.performClose(nil)
            GlassWindowController.shared.show()
            if let name = body["name"] as? String, !name.isEmpty {
                GlassWindowController.shared.store.openNamed(name)
            }
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
        let e = (name as NSString).pathExtension
        // Images and videos embed inline (![]); everything else is a link.
        return (isImageExt(e) || isVideoExt(e)) ? "\n![\(name)](assets/\(name))\n" : "\n[\(name)](assets/\(name))\n"
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
