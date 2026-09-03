import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import AVKit

// MARK: - Media helpers (shared by editor drop + preview)
func isImageExt(_ e: String) -> Bool {
    ["png","jpg","jpeg","gif","heic","webp","tiff","tif","bmp","svg"].contains(e.lowercased())
}
func isVideoExt(_ e: String) -> Bool {
    ["mp4","mov","m4v","webm","avi","mkv"].contains(e.lowercased())
}
// Copy a dropped file into assets/ under a collision-free name; return that name.
func importFileToAssets(_ url: URL) -> String? {
    try? FileManager.default.createDirectory(atPath: ASSETS_DIR, withIntermediateDirectories: true)
    let base = url.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "]", with: ")")
    let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
    var name = "\(base).\(ext)"; var i = 2
    while FileManager.default.fileExists(atPath: ASSETS_DIR + "/" + name) { name = "\(base)-\(i).\(ext)"; i += 1 }
    do { try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: ASSETS_DIR + "/" + name)); return name }
    catch { return nil }
}
// Images AND videos embed with the ![]() form so the preview renders them inline; other files link.
func mediaSnippet(_ name: String) -> String {
    let e = (name as NSString).pathExtension
    return (isImageExt(e) || isVideoExt(e)) ? "\n![\(name)](assets/\(name))\n" : "\n[\(name)](assets/\(name))\n"
}

// MARK: - Content calendar model
struct ScheduleSlot: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var day: String                 // "2026-08-21"
    var time: String                // "08:20" or "4:00–6:30"
    var title: String
    var note: String? = nil         // linked note name
    var done: Bool = false
}

// The fixed 10-day campaign window (key, short label, day's narrative).
let CAMPAIGN_DAYS: [(key: String, label: String, story: String)] = [
    ("2026-08-21", "Fri 21", "Upwork gave AI agents access to WHAT?"),
    ("2026-08-22", "Sat 22", "Bloomberg Terminal for freelancers"),
    ("2026-08-23", "Sun 23", "My personal Upwork agent"),
    ("2026-08-24", "Mon 24", "Everything MCP actually exposes"),
    ("2026-08-25", "Tue 25", "Upwork in your Mac notch"),
    ("2026-08-26", "Wed 26", "Bloomberg-style market ribbon"),
    ("2026-08-27", "Thu 27", "Best time to start freelancing"),
    ("2026-08-28", "Fri 28", "My first $1k online, again"),
    ("2026-08-29", "Sat 29", "Upwork as a native macOS app"),
    ("2026-08-30", "Sun 30", "This wasn't really about Upwork"),
]

// Single source of truth for a note's YAML frontmatter (category / tags / pinned / parent).
func makeFrontmatter(category: String, tags: [String], pinned: Bool, parent: String?) -> String {
    let cat = category.trimmingCharacters(in: .whitespaces)
    let par = (parent ?? "").trimmingCharacters(in: .whitespaces)
    let hasCat = cat != "General" && !cat.isEmpty
    guard hasCat || !tags.isEmpty || pinned || !par.isEmpty else { return "" }
    var fm = "---\n"
    if hasCat { fm += "category: \(cat)\n" }
    if !tags.isEmpty { fm += "tags: \(tags.joined(separator: ", "))\n" }
    if pinned { fm += "pinned: true\n" }
    if !par.isEmpty { fm += "parent: \(par)\n" }
    fm += "---\n\n"
    return fm
}

// Load a dropped note name (String) from item providers, file it under `cat`,
// and fire the caller's success animation. Returns true if it accepted anything.
@MainActor
func acceptNoteDrop(_ providers: [NSItemProvider], into cat: String?,
                    store: NotesStore, onCaught: @escaping () -> Void) -> Bool {
    guard let cat = cat else { return false }
    var accepted = false
    for p in providers where p.canLoadObject(ofClass: NSString.self) {
        accepted = true
        p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let name = obj as? String else { return }
            DispatchQueue.main.async {
                store.setCategory(noteName: name, to: cat)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                onCaught()
            }
        }
    }
    return accepted
}

// ============================================================================
// Full-screen "Liquid Glass" notes UI. Reuses NOTES_DIR / ASSETS_DIR / Note /
// loadNotes() / parseFrontmatter() from main.swift and reads & writes the same
// .md files, so it stays in sync with the menu-bar popover.
// ============================================================================

// MARK: - Liquid Glass material (real .glassEffect on macOS 26, fallback below)

@available(macOS 26.0, *)
private func mkGlass(_ tint: Color?, _ interactive: Bool) -> Glass {
    var g: Glass = .regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

extension View {
    @ViewBuilder
    func lg<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(mkGlass(tint, interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
        }
    }
}

func catColor(_ name: String) -> Color {
    if name == "General" { return Color(hue: 0.58, saturation: 0.10, brightness: 0.9) }
    var h: UInt64 = 1469598103934665603
    for b in name.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Color(hue: Double(h % 360) / 360.0, saturation: 0.62, brightness: 0.92)
}

// MARK: - Store

@MainActor
final class NotesStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var query = ""
    @Published var selectedCat: String? = nil
    @Published var selectedName: String? = nil

    // Editor state (body is kept WITHOUT frontmatter; we re-attach it on save)
    @Published var editName = ""
    @Published var editBody = ""
    @Published var editCategory = "General"
    @Published var editTags = ""
    @Published var editPinned = false
    @Published var editParent: String? = nil
    @Published var isNew = false
    @Published var dirty = false
    @Published var preview = false
    @Published var hasSelection = false

    // View mode of the main pane: note editor (default), folder grid, or calendar grid.
    @Published var calendarView = false
    @Published var schedule: [ScheduleSlot] = []

    // Which parent rows are collapsed in the tree, and a manual sibling order (name → rank).
    // Both are UI state, persisted app-side (parent itself lives in each note's frontmatter).
    @Published var collapsed: Set<String> =
        Set((UserDefaults.standard.array(forKey: "cherryCollapsed") as? [String]) ?? [])
    @Published var manualOrder: [String: Double] =
        (UserDefaults.standard.dictionary(forKey: "cherryOrder") as? [String: Double]) ?? [:]

    func toggleCollapse(_ name: String) {
        if collapsed.contains(name) { collapsed.remove(name) } else { collapsed.insert(name) }
        UserDefaults.standard.set(Array(collapsed), forKey: "cherryCollapsed")
    }
    private func persistOrder() { UserDefaults.standard.set(manualOrder, forKey: "cherryOrder") }

    // folder / label system
    @Published var folderView = false        // true = folder grid, false = note list
    @Published var customCategories: [String] =
        (UserDefaults.standard.array(forKey: "cherryCats") as? [String]) ?? []

    // union of categories in use + user-created empty ones (General first, then A→Z)
    var allCategories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for n in notes where !seen.contains(n.category) { seen.insert(n.category); out.append(n.category) }
        for c in customCategories where !seen.contains(c) { seen.insert(c); out.append(c) }
        return out.sorted { $0 == "General" ? true : ($1 == "General" ? false : $0 < $1) }
    }
    func count(_ cat: String?) -> Int {
        cat == nil ? notes.count : notes.filter { $0.category == cat }.count
    }
    func addCategory(_ raw: String) {
        let n = raw.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !allCategories.contains(n) else { return }
        customCategories.append(n)
        UserDefaults.standard.set(customCategories, forKey: "cherryCats")
    }
    // Reassign a note's category by rewriting its frontmatter in place (used by drag & drop).
    func setCategory(noteName: String, to cat: String) {
        guard let n = notes.first(where: { $0.name == noteName }) else { return }
        let (_, tags, pinned, parent) = parseFrontmatter(n.body)
        let rest = bodyWithoutFrontmatter(n.body)
        let fm = makeFrontmatter(category: cat, tags: tags, pinned: pinned, parent: parent)
        let safe = noteName.replacingOccurrences(of: "/", with: "-")
        try? (fm + rest).write(toFile: NOTES_DIR + "/" + safe + ".md", atomically: true, encoding: .utf8)
        runRebuild()
        notes = loadNotes()
        if selectedName == noteName { editCategory = cat }
    }

    // Reparent a note (drag one note onto another → sub-note; onto "top level" → root).
    // Guards against making a note a child of its own descendant.
    func setParent(noteName: String, to newParent: String?) {
        guard let n = notes.first(where: { $0.name == noteName }) else { return }
        if let p = newParent, p == noteName || isDescendant(p, of: noteName) { return }
        let (cat, tags, pinned, _) = parseFrontmatter(n.body)
        let rest = bodyWithoutFrontmatter(n.body)
        let fm = makeFrontmatter(category: cat, tags: tags, pinned: pinned, parent: newParent)
        let safe = noteName.replacingOccurrences(of: "/", with: "-")
        try? (fm + rest).write(toFile: NOTES_DIR + "/" + safe + ".md", atomically: true, encoding: .utf8)
        // drop it at the end of its new sibling group
        let sibs = childrenOrdered(of: newParent).filter { $0.name != noteName }
        manualOrder[noteName] = (sibs.compactMap { manualOrder[$0.name] }.max() ?? Double(sibs.count) * 1000) + 1000
        persistOrder()
        runRebuild()
        notes = loadNotes()
        if selectedName == noteName { editParent = newParent }
    }

    private func isDescendant(_ maybeChild: String, of ancestor: String) -> Bool {
        var cur: String? = notes.first(where: { $0.name == maybeChild })?.parent
        var guardCount = 0
        while let c = cur, guardCount < 200 {
            if c == ancestor { return true }
            cur = notes.first(where: { $0.name == c })?.parent
            guardCount += 1
        }
        return false
    }

    // MARK: - Tree model
    // Roots = notes with no parent (or a parent that no longer exists). Siblings sort:
    // pinned first, then manual order (drag), then title.
    private func siblingSort(_ a: Note, _ b: Note) -> Bool {
        if a.pinned != b.pinned { return a.pinned && !b.pinned }
        let oa = manualOrder[a.name] ?? .greatestFiniteMagnitude
        let ob = manualOrder[b.name] ?? .greatestFiniteMagnitude
        if oa != ob { return oa < ob }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
    var rootNotes: [Note] {
        let names = Set(notes.map { $0.name })
        return notes.filter { $0.parent == nil || !names.contains($0.parent!) }.sorted(by: siblingSort)
    }
    func childrenOrdered(of parent: String?) -> [Note] {
        guard let parent else { return rootNotes }
        return notes.filter { $0.parent == parent }.sorted(by: siblingSort)
    }
    func hasChildren(_ name: String) -> Bool { notes.contains { $0.parent == name } }
    private func note(_ name: String) -> Note? { notes.first { $0.name == name } }

    // Drag-to-rearrange primitive: put `moved` into `parent`'s child list, positioned just before
    // `anchor` (nil = append to the end). Anchor-based so it's robust to index shifts.
    func place(_ moved: String, into parent: String?, before anchor: String?) {
        if let p = parent, p == moved || isDescendant(p, of: moved) { return }
        if note(moved)?.parent != parent { setParent(noteName: moved, to: parent) }   // writes frontmatter + reloads
        guard let movedNote = note(moved) else { return }
        var sibs = childrenOrdered(of: parent).filter { $0.name != moved }
        let idx = anchor.flatMap { a in sibs.firstIndex { $0.name == a } } ?? sibs.count
        sibs.insert(movedNote, at: max(0, min(idx, sibs.count)))
        for (i, s) in sibs.enumerated() { manualOrder[s.name] = Double(i + 1) * 1000 }   // even spacing
        persistOrder()
        objectWillChange.send()
    }

    // Flatten the tree to (note, depth) rows, skipping collapsed subtrees — drives the sidebar.
    func visibleTree() -> [(note: Note, depth: Int)] {
        var out: [(Note, Int)] = []
        func walk(_ nodes: [Note], _ depth: Int) {
            for n in nodes {
                out.append((n, depth))
                if !collapsed.contains(n.name) {
                    let kids = childrenOrdered(of: n.name)
                    if !kids.isEmpty { walk(kids, depth + 1) }
                }
            }
        }
        walk(rootNotes, 0)
        return out
    }

    func reload() {
        notes = loadNotes()
        loadSchedule()
        if selectedName == nil, let first = notes.first { select(first) }
        else if let s = selectedName, let n = notes.first(where: { $0.name == s }) {
            // keep current editor content; just refresh list
            _ = n
        }
    }

    // MARK: - Content calendar persistence (JSON next to the notes)
    private var scheduleURL: URL { URL(fileURLWithPath: NOTES_DIR + "/up_arc_schedule.json") }
    func loadSchedule() {
        if let data = try? Data(contentsOf: scheduleURL),
           let slots = try? JSONDecoder().decode([ScheduleSlot].self, from: data) {
            schedule = slots
        } else if schedule.isEmpty {
            schedule = NotesStore.seedSchedule()
            saveSchedule()
        }
    }
    func saveSchedule() {
        if let data = try? JSONEncoder().encode(schedule) { try? data.write(to: scheduleURL) }
    }
    func addSlot(day: String) {
        schedule.append(ScheduleSlot(day: day, time: "12:00", title: "New slot"))
        saveSchedule()
    }
    func deleteSlot(_ id: String) { schedule.removeAll { $0.id == id }; saveSchedule() }
    func slots(for day: String) -> [ScheduleSlot] {
        schedule.filter { $0.day == day }.sorted { $0.time.localizedStandardCompare($1.time) == .orderedAscending }
    }

    // Seeded from the run-of-show + 10-day plan so the calendar is useful on first open.
    static func seedSchedule() -> [ScheduleSlot] {
        let d1 = "2026-08-21"
        var out: [ScheduleSlot] = [
            ScheduleSlot(day: d1, time: "08:20", title: "Master MCP proof recording", note: "up-arc-plus-nuked"),
            ScheduleSlot(day: d1, time: "09:15", title: "Bloomberg terminal footage", note: "up-arc-bloomberg"),
            ScheduleSlot(day: d1, time: "09:45", title: "Ribbon footage", note: "up-arc-open-market"),
            ScheduleSlot(day: d1, time: "10:15", title: "Apple notch footage", note: "yo"),
            ScheduleSlot(day: d1, time: "10:45", title: "Native glass app footage", note: "yo"),
            ScheduleSlot(day: d1, time: "11:20", title: "Record 3 B-roll shorts", note: "up-arc-today"),
            ScheduleSlot(day: d1, time: "13:30", title: "Record YouTube #1", note: "up-arc-10day-plan"),
            ScheduleSlot(day: d1, time: "14:15", title: "Record YouTube #2", note: "up-arc-bloomberg"),
            ScheduleSlot(day: d1, time: "15:35", title: "Editor handoff", note: "up-arc-editor-brief"),
            ScheduleSlot(day: d1, time: "16:00", title: "Write 50 X posts", note: "up-arc-queue-x"),
            ScheduleSlot(day: d1, time: "18:30", title: "Write 30 LinkedIn posts", note: "up-arc-queue-linkedin"),
            ScheduleSlot(day: d1, time: "20:30", title: "Write 30 Reddit posts", note: "up-arc-queue-reddit"),
            ScheduleSlot(day: d1, time: "22:30", title: "Match posts to assets/memes", note: "up-arc-visuals"),
            ScheduleSlot(day: d1, time: "23:30", title: "Schedule X + LinkedIn", note: "up-arc-10day-plan"),
        ]
        for d in CAMPAIGN_DAYS.dropFirst() {   // one post-day slot per remaining day, linked to the plan
            out.append(ScheduleSlot(day: d.key, time: "09:00", title: "Post day: \(d.story)", note: "up-arc-10day-plan"))
        }
        return out
    }

    var categories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for n in notes where !seen.contains(n.category) { seen.insert(n.category); out.append(n.category) }
        return out.sorted { $0 == "General" ? true : ($1 == "General" ? false : $0 < $1) }
    }

    // Tree only when not searching / not filtered by a category; otherwise a flat result list.
    var isBrowsingTree: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && selectedCat == nil
    }

    var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return notes.filter { n in
            if let c = selectedCat, n.category != c { return false }
            if q.isEmpty { return true }
            return n.title.lowercased().contains(q) || n.name.lowercased().contains(q)
                || n.body.lowercased().contains(q) || n.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: selection / editing
    func select(_ n: Note) {
        autosaveIfNeeded()
        selectedName = n.name
        editName = n.name
        editBody = bodyWithoutFrontmatter(n.body)
        editCategory = n.category
        editTags = n.tags.joined(separator: ", ")
        editPinned = n.pinned
        editParent = n.parent
        isNew = false; dirty = false; hasSelection = true; preview = true   // open in view mode
        calendarView = false
    }

    func openNamed(_ name: String) {
        notes = loadNotes()
        if let n = notes.first(where: { $0.name.lowercased() == name.lowercased()
                                     || $0.title.lowercased() == name.lowercased() }) {
            folderView = false
            calendarView = false
            select(n)
        }
    }

    func newNote(parent: String? = nil) {
        autosaveIfNeeded()
        selectedName = nil
        editName = ""
        editBody = "# New Note\n\nStart writing…\n"
        editCategory = parent.flatMap { p in notes.first(where: { $0.name == p })?.category } ?? "General"
        editTags = ""; editPinned = false; editParent = parent
        isNew = true; dirty = true; hasSelection = true; preview = false
        calendarView = false
        if let parent { collapsed.remove(parent) }   // reveal the new child under its parent
    }

    func save() {
        let raw = editName.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let safe = raw.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let text = serialize()
        try? FileManager.default.createDirectory(atPath: NOTES_DIR, withIntermediateDirectories: true)
        try? text.write(toFile: NOTES_DIR + "/" + safe + ".md", atomically: true, encoding: .utf8)
        runRebuild()
        selectedName = safe; editName = safe; isNew = false; dirty = false
        notes = loadNotes()
    }

    func autosaveIfNeeded() {
        if dirty && !editName.trimmingCharacters(in: .whitespaces).isEmpty { save() }
    }

    func delete() {
        guard let s = selectedName else { return }
        let safe = s.replacingOccurrences(of: "/", with: "-")
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: NOTES_DIR + "/" + safe + ".md"),
                                           resultingItemURL: nil)
        runRebuild()
        selectedName = nil; hasSelection = false; editBody = ""; editName = ""; dirty = false
        notes = loadNotes()
        if let first = notes.first { select(first) }
    }

    func revealInFinder() {
        guard let s = selectedName else { return }
        NSWorkspace.shared.selectFile(NOTES_DIR + "/" + s + ".md", inFileViewerRootedAtPath: NOTES_DIR)
    }

    // MARK: frontmatter round-trip
    private func bodyWithoutFrontmatter(_ full: String) -> String {
        let lines = full.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return full }
        var i = 1
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "---" { i += 1 }
        i += 1                                            // skip closing ---
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        return lines[i...].joined(separator: "\n")
    }

    private func serialize() -> String {
        let tags = editTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return makeFrontmatter(category: editCategory, tags: tags, pinned: editPinned, parent: editParent) + editBody
    }

    // Debounced + serialized off the main thread (shared with the popover) so rapid
    // saves/drags don't stack overlapping rebuild.sh runs and hang the UI.
    private func runRebuild() { RebuildCoordinator.shared.schedule() }
}

// MARK: - Window controller (transparent glass window; toggled from the menu bar)

@MainActor
final class GlassWindowController: NSObject, NSWindowDelegate {
    static let shared = GlassWindowController()
    var window: NSWindow?
    let store = NotesStore()

    func toggle() {
        if let w = window, w.isVisible { hide() } else { show() }
    }

    func show() {
        store.reload()
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func build() {
        let root = NotesRootView().environmentObject(store)
        let host = NSHostingView(rootView: root)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        // Must stay false: window-background dragging would otherwise hijack the
        // note drag-and-drop gesture. The window is still movable by its top strip.
        w.isMovableByWindowBackground = false
        w.minSize = NSSize(width: 940, height: 620)
        w.isReleasedWhenClosed = false
        // Ride along on whatever Space is active (incl. over another app's
        // full-screen window) instead of spawning its own Space. Also stops the
        // green button from taking over the screen and glitching the popover.
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.contentView = host
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("CherryGlassWindow")
        window = w
    }

    // Red-X / ⌘W → hide the window back into the menu-bar ribbon instead of
    // closing it. The app keeps running with the googly-eyes icon; clicking the
    // icon (or ⌃⌥⌘N) brings this same window back, position preserved.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        store.autosaveIfNeeded()
        sender.orderOut(nil)
        return false
    }
}

// MARK: - Root view

struct NotesRootView: View {
    @EnvironmentObject var store: NotesStore
    var body: some View {
        ZStack {
            Color.clear                       // transparent → desktop shows through
            HStack(spacing: 14) {
                Sidebar().frame(width: 310)
                EditorPane()
            }
            .padding(16)
            .padding(.top, 12)
        }
        .frame(minWidth: 940, minHeight: 620)
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: NotesStore
    @State private var showNewCat = false
    @State private var newCatName = ""

    var body: some View {
        VStack(spacing: 12) {
            // header: brand · folder/list toggle · new note
            HStack(spacing: 10) {
                Text("🍒").font(.system(size: 16))
                Text("Cherry").font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button { store.calendarView.toggle(); store.folderView = false } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.calendarView ? .black : .white)
                        .frame(width: 30, height: 30)
                        .lg(Circle(), tint: store.calendarView ? .white.opacity(0.9) : .white.opacity(0.14), interactive: true)
                }.buttonStyle(.plain).help("Content calendar")
                Button { withAnimation(.easeInOut(duration: 0.18)) { store.folderView.toggle() } } label: {
                    Image(systemName: store.folderView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .lg(Circle(), tint: .white.opacity(0.14), interactive: true)
                }.buttonStyle(.plain).help(store.folderView ? "Show note list" : "Show folders")
                Button { store.newNote() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .lg(Circle(), tint: .white.opacity(0.14), interactive: true)
                }.buttonStyle(.plain).help("New note (⌘N)")
            }
            .padding(.leading, 62)                // clear the traffic lights

            // search
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                TextField("", text: $store.query, prompt:
                    Text("Search notes…").foregroundStyle(.white.opacity(0.45)))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .lg(Capsule(), tint: .black.opacity(0.12))

            // category chips — filter + drag-and-drop targets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    DropChip(title: "All", color: .white, count: store.count(nil),
                             active: store.selectedCat == nil, catForDrop: nil)
                    ForEach(store.allCategories, id: \.self) { c in
                        DropChip(title: c, color: catColor(c), count: store.count(c),
                                 active: store.selectedCat == c, catForDrop: c)
                    }
                    Button { showNewCat = true } label: {
                        HStack(spacing: 4) { Image(systemName: "plus"); Text("New") }
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 11).frame(height: 30)
                            .lg(Capsule(), tint: .white.opacity(0.06), interactive: true)
                    }.buttonStyle(.plain).help("New category")
                }
            }

            // note list — a collapsible tree when browsing (drag a row onto another to nest it,
            // onto the top/bottom edge to reorder); a flat list while searching or filtering.
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if store.isBrowsingTree {
                        RootDropZone()
                        ForEach(store.visibleTree(), id: \.note.name) { item in
                            OutlineRow(note: item.note, depth: item.depth,
                                       selected: store.selectedName == item.note.name)
                        }
                        if store.notes.isEmpty {
                            Text("No notes here").font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4)).padding(.top, 24)
                        }
                    } else {
                        ForEach(store.filtered, id: \.name) { n in
                            NoteRow(note: n, selected: store.selectedName == n.name)
                                .onTapGesture { store.select(n) }
                                .onDrag { NSItemProvider(object: n.name as NSString) }
                        }
                        if store.filtered.isEmpty {
                            Text("No notes here").font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4)).padding(.top, 24)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .lg(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: .black.opacity(0.16))
        .alert("New Category", isPresented: $showNewCat) {
            TextField("Name", text: $newCatName)
            Button("Create") { store.addCategory(newCatName); newCatName = "" }
            Button("Cancel", role: .cancel) { newCatName = "" }
        } message: { Text("Create a folder/label, then drag notes onto it to file them.") }
    }
}

// A category chip that both filters the list and accepts dropped notes.
struct DropChip: View {
    @EnvironmentObject var store: NotesStore
    let title: String; let color: Color; let count: Int; let active: Bool; let catForDrop: String?
    @State private var targeted = false
    @State private var caught = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? .black : .white).lineLimit(1)
            Text("\(count)").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? .black.opacity(0.5) : .white.opacity(0.45))
        }
        .padding(.horizontal, 11).frame(height: 30)
        .lg(Capsule(), tint: active ? .white.opacity(0.92)
                : (targeted ? color.opacity(0.6) : .black.opacity(0.08)))
        .overlay(Capsule().stroke(color.opacity(targeted || caught ? 0.95 : 0), lineWidth: 1.5))
        .scaleEffect(caught ? 1.18 : (targeted ? 1.06 : 1.0))
        .animation(.spring(response: 0.28, dampingFraction: 0.45), value: caught)
        .animation(.easeOut(duration: 0.12), value: targeted)
        .contentShape(Capsule())
        .onTapGesture {
            store.selectedCat = active ? nil : catForDrop
            store.folderView = false
        }
        .onDrop(of: [.plainText, .utf8PlainText, .text], isTargeted: $targeted) { providers in
            acceptNoteDrop(providers, into: catForDrop, store: store) {
                caught = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { caught = false }
            }
        }
    }
}

struct FolderCard: View {
    @EnvironmentObject var store: NotesStore
    let title: String; let color: Color; let count: Int; let cat: String?
    var big: Bool = false
    @State private var targeted = false
    @State private var caught = false
    var body: some View {
        VStack(alignment: .leading, spacing: big ? 12 : 8) {
            HStack {
                Image(systemName: (targeted || caught) ? "folder.fill.badge.plus" : "folder.fill")
                    .font(.system(size: big ? 24 : 16)).foregroundStyle(color)
                    .symbolEffect(.bounce, value: caught)
                Spacer()
                Text("\(count)").font(.system(size: big ? 14 : 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(title).font(.system(size: big ? 15 : 12.5, weight: .semibold))
                .foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(big ? 16 : 12)
        .frame(maxWidth: .infinity, minHeight: big ? 104 : 82, alignment: .topLeading)
        .lg(RoundedRectangle(cornerRadius: big ? 18 : 16, style: .continuous),
            tint: caught ? color.opacity(0.7) : (targeted ? color.opacity(0.5) : .black.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: big ? 18 : 16, style: .continuous)
            .stroke(color.opacity(targeted || caught ? 0.95 : 0), lineWidth: 2))
        .scaleEffect(caught ? 1.1 : (targeted ? 1.04 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: caught)
        .animation(.easeOut(duration: 0.12), value: targeted)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedCat = cat; withAnimation { store.folderView = false } }
        .onDrop(of: [.plainText, .utf8PlainText, .text], isTargeted: $targeted) { providers in
            acceptNoteDrop(providers, into: cat, store: store) {
                caught = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { caught = false }
            }
        }
    }
}

struct NoteRow: View {
    let note: Note; let selected: Bool
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(catColor(note.category))
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                            .foregroundStyle(.yellow.opacity(0.9))
                    }
                    Text(note.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(1)
                }
                Text(note.category).font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(selected ? 0.16 : 0.0)))
        .contentShape(Rectangle())
    }
}

// MARK: - Tree rows (nested sub-notes, drag to nest/reorder)

enum DropZone { case before, into, after }

struct OutlineRow: View {
    @EnvironmentObject var store: NotesStore
    let note: Note; let depth: Int; let selected: Bool
    @State private var hovering = false
    @State private var zone: DropZone? = nil

    var body: some View {
        HStack(spacing: 6) {
            if depth > 0 { Spacer().frame(width: CGFloat(depth) * 14) }
            if store.hasChildren(note.name) {
                Button { store.toggleCollapse(note.name) } label: {
                    Image(systemName: store.collapsed.contains(note.name) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.65))
                        .frame(width: 14, height: 14)
                }.buttonStyle(.plain)
            } else {
                Circle().fill(.white.opacity(0.18)).frame(width: 3, height: 3).frame(width: 14)
            }
            RoundedRectangle(cornerRadius: 3).fill(catColor(note.category)).frame(width: 3, height: 24)
            HStack(spacing: 4) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(.yellow.opacity(0.9))
                }
                Text(note.title).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering {
                Button { store.newNote(parent: note.name) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }.buttonStyle(.plain).help("Add sub-note")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(.white.opacity(selected ? 0.16 : (zone == .into ? 0.10 : 0))))
        .overlay(alignment: .top) { if zone == .before { dropLine } }
        .overlay(alignment: .bottom) { if zone == .after { dropLine } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.select(note) }
        .onDrag { NSItemProvider(object: note.name as NSString) }
        .onDrop(of: [.plainText, .utf8PlainText, .text],
                delegate: NoteDropDelegate(target: note, store: store, zone: $zone))
    }
    private var dropLine: some View {
        RoundedRectangle(cornerRadius: 1).fill(.blue).frame(height: 2).padding(.horizontal, 4)
    }
}

struct NoteDropDelegate: DropDelegate {
    let target: Note
    let store: NotesStore
    @Binding var zone: DropZone?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText, .utf8PlainText, .text])
    }
    func dropEntered(info: DropInfo) { zone = zoneFor(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { zone = zoneFor(info); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { zone = nil }
    func performDrop(info: DropInfo) -> Bool {
        let z = zoneFor(info); zone = nil
        guard let item = info.itemProviders(for: [.plainText, .utf8PlainText, .text]).first else { return false }
        let t = target
        item.loadObject(ofClass: NSString.self) { obj, _ in
            guard let moved = obj as? String, moved != t.name else { return }
            DispatchQueue.main.async {
                switch z {
                case .into:
                    store.place(moved, into: t.name, before: nil)
                case .before:
                    store.place(moved, into: t.parent, before: t.name)
                case .after:
                    let sibs = store.childrenOrdered(of: t.parent).filter { $0.name != moved }
                    let idx = sibs.firstIndex { $0.name == t.name } ?? (sibs.count - 1)
                    let after = (idx + 1 < sibs.count) ? sibs[idx + 1].name : nil
                    store.place(moved, into: t.parent, before: after)
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        return true
    }
    // Row ≈ 36pt tall: top/bottom bands reorder as a sibling, the middle nests as a child.
    private func zoneFor(_ info: DropInfo) -> DropZone {
        let y = info.location.y
        if y < 11 { return .before }
        if y > 25 { return .after }
        return .into
    }
}

// Drop a note here to pull it back out to the top level (clear its parent).
struct RootDropZone: View {
    @EnvironmentObject var store: NotesStore
    @State private var targeted = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.to.line").font(.system(size: 9, weight: .bold))
            Text("Top level").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(targeted ? 0.95 : 0.32))
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(targeted ? 0.12 : 0.02)))
        .onDrop(of: [.plainText, .utf8PlainText, .text], isTargeted: $targeted) { providers in
            guard let p = providers.first else { return false }
            p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let moved = obj as? String else { return }
                DispatchQueue.main.async { store.place(moved, into: nil, before: nil) }
            }
            return true
        }
    }
}

// MARK: - Editor

struct EditorPane: View {
    @EnvironmentObject var store: NotesStore
    var body: some View {
        VStack(spacing: 0) {
            if store.calendarView {
                CalendarView()
            } else if store.folderView {
                FolderBrowser()
            } else if store.hasSelection {
                EditorHeader()
                Divider().overlay(.white.opacity(0.12))
                if store.preview {
                    ScrollView {
                        MarkdownView(text: store.editBody, onOpenNote: { store.openNamed($0) })
                            .padding(22)
                    }
                } else {
                    EditorTextView(text: $store.editBody, onChange: { store.dirty = true })
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cherry").font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Select or create a note").font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lg(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: .black.opacity(0.18))
    }
}

// Folder browser shown in the MAIN pane. Big folder cards you drag notes onto
// from the sidebar list on the left.
struct FolderBrowser: View {
    @EnvironmentObject var store: NotesStore
    @State private var showNewCat = false
    @State private var newCatName = ""
    private let cols = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Folders").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("drag a note from the left onto a folder to file it")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { showNewCat = true } label: {
                    HStack(spacing: 5) { Image(systemName: "plus"); Text("New Folder") }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(height: 30)
                        .lg(Capsule(), tint: .white.opacity(0.12), interactive: true)
                }.buttonStyle(.plain)
                Button { withAnimation { store.folderView = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white).frame(width: 30, height: 30)
                        .lg(Circle(), tint: .black.opacity(0.12), interactive: true)
                }.buttonStyle(.plain).help("Back to editor")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            Divider().overlay(.white.opacity(0.12))

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: cols, spacing: 14) {
                    FolderCard(title: "All Notes", color: .white, count: store.count(nil), cat: nil, big: true)
                    ForEach(store.allCategories, id: \.self) { c in
                        FolderCard(title: c, color: catColor(c), count: store.count(c), cat: c, big: true)
                    }
                    Button { showNewCat = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle").font(.system(size: 22))
                            Text("New Folder").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 104)
                        .lg(RoundedRectangle(cornerRadius: 18, style: .continuous),
                            tint: .white.opacity(0.05), interactive: true)
                    }.buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .alert("New Category", isPresented: $showNewCat) {
            TextField("Name", text: $newCatName)
            Button("Create") { store.addCategory(newCatName); newCatName = "" }
            Button("Cancel", role: .cancel) { newCatName = "" }
        } message: { Text("Create a folder/label, then drag notes onto it to file them.") }
    }
}

// MARK: - Content calendar view

struct CalendarView: View {
    @EnvironmentObject var store: NotesStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Content Calendar").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                Text("Aug 21–30 · click ↗ to open a slot's note").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button { store.calendarView = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white).frame(width: 30, height: 30)
                        .lg(Circle(), tint: .black.opacity(0.12), interactive: true)
                }.buttonStyle(.plain).help("Back to editor")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            Divider().overlay(.white.opacity(0.12))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CAMPAIGN_DAYS, id: \.key) { day in
                        DayColumn(dayKey: day.key, label: day.label, story: day.story)
                    }
                }
                .padding(18)
            }
        }
    }
}

struct DayColumn: View {
    @EnvironmentObject var store: NotesStore
    let dayKey: String; let label: String; let story: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(story).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                Button { store.addSlot(day: dayKey) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75)).frame(width: 24, height: 24)
                        .lg(Circle(), tint: .white.opacity(0.1), interactive: true)
                }.buttonStyle(.plain).help("Add a time slot")
            }
            let slots = store.slots(for: dayKey)
            if slots.isEmpty {
                Text("No slots — tap + to add").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35)).padding(.vertical, 4)
            } else {
                ForEach(slots) { slot in SlotCard(slot: slot) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lg(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .black.opacity(0.14))
    }
}

struct SlotCard: View {
    @EnvironmentObject var store: NotesStore
    let slot: ScheduleSlot
    @State private var hovering = false

    private var bind: Binding<ScheduleSlot> {
        Binding(
            get: { store.schedule.first(where: { $0.id == slot.id }) ?? slot },
            set: { v in
                if let i = store.schedule.firstIndex(where: { $0.id == slot.id }) {
                    store.schedule[i] = v; store.saveSchedule()
                }
            })
    }
    private func noteTitle(_ name: String) -> String {
        store.notes.first { $0.name == name }?.title ?? name
    }

    var body: some View {
        let b = bind
        HStack(spacing: 8) {
            Button { b.done.wrappedValue.toggle() } label: {
                Image(systemName: b.wrappedValue.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(b.wrappedValue.done ? .green : .white.opacity(0.4))
            }.buttonStyle(.plain)

            TextField("time", text: b.time)
                .textFieldStyle(.plain).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8)).frame(width: 62)

            TextField("what to do", text: b.title)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(b.wrappedValue.done ? 0.4 : 0.92))
                .strikethrough(b.wrappedValue.done)

            Spacer(minLength: 4)

            Menu {
                Button("— no note —") { b.note.wrappedValue = nil }
                Divider()
                ForEach(store.notes, id: \.name) { n in
                    Button(n.title) { b.note.wrappedValue = n.name }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "link").font(.system(size: 9))
                    Text(b.wrappedValue.note.map(noteTitle) ?? "link note")
                        .font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(b.wrappedValue.note == nil ? .white.opacity(0.45) : .cyan.opacity(0.9))
                .frame(maxWidth: 140, alignment: .trailing)
            }.menuStyle(.borderlessButton).fixedSize()

            if let nm = b.wrappedValue.note {
                Button { store.openNamed(nm) } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                }.buttonStyle(.plain).help("Open \(noteTitle(nm))")
            }
            if hovering {
                Button { store.deleteSlot(slot.id) } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
        .onHover { hovering = $0 }
    }
}

struct EditorHeader: View {
    @EnvironmentObject var store: NotesStore
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if store.isNew {
                    TextField("note-name", text: $store.editName)
                        .textFieldStyle(.plain).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).frame(maxWidth: 260)
                } else {
                    Text(store.editName).font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                // preview toggle
                Picker("", selection: $store.preview) {
                    Image(systemName: "pencil").tag(false)
                    Image(systemName: "eye").tag(true)
                }.pickerStyle(.segmented).frame(width: 90).labelsHidden()

                Button { store.editPinned.toggle(); store.dirty = true } label: {
                    Image(systemName: store.editPinned ? "pin.fill" : "pin")
                        .foregroundStyle(store.editPinned ? .yellow : .white.opacity(0.8))
                        .frame(width: 30, height: 28).lg(Capsule(), tint: .black.opacity(0.1))
                }.buttonStyle(.plain).help("Pin")

                Button { store.revealInFinder() } label: {
                    Image(systemName: "folder").foregroundStyle(.white.opacity(0.8))
                        .frame(width: 30, height: 28).lg(Capsule(), tint: .black.opacity(0.1))
                }.buttonStyle(.plain).help("Reveal .md in Finder")

                Button { store.delete() } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.85))
                        .frame(width: 30, height: 28).lg(Capsule(), tint: .black.opacity(0.1))
                }.buttonStyle(.plain).help("Delete note")

                Button { store.save() } label: {
                    Text("Save").font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 30)
                        .lg(Capsule(), tint: store.dirty ? .blue.opacity(0.5) : .white.opacity(0.1),
                            interactive: true)
                }.buttonStyle(.plain).keyboardShortcut("s", modifiers: .command)
            }
            HStack(spacing: 8) {
                Image(systemName: "tag").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                TextField("category", text: $store.editCategory, onEditingChanged: { _ in store.dirty = true })
                    .textFieldStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 150)
                Circle().fill(catColor(store.editCategory)).frame(width: 7, height: 7)
                Text("·").foregroundStyle(.white.opacity(0.3))
                TextField("tags, comma, separated", text: $store.editTags,
                          onEditingChanged: { _ in store.dirty = true })
                    .textFieldStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if store.dirty { Text("unsaved").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.8)) }
            }
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 12)
    }
}

// NSTextView-backed editor so it's a proper, fast, monospace-friendly writing surface
// with a transparent background over the glass.
// An NSTextView that accepts dropped images / videos / files: each is copied into the note's
// assets/ folder and its Markdown reference is inserted at the drop point. Non-media just links.
final class DropTextView: NSTextView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppableFiles(sender) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppableFiles(sender) ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return super.performDragOperation(sender) }
        let names = urls.compactMap { importFileToAssets($0) }
        guard !names.isEmpty else { return false }
        let snip = names.map { mediaSnippet($0) }.joined()
        let r = selectedRange()
        if shouldChangeText(in: r, replacementString: snip) {
            insertText(snip, replacementRange: r)   // fires textDidChange → binding + dirty update
        }
        return true
    }
    private func hasDroppableFiles(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true])
    }
}

struct EditorTextView: NSViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.autohidesScrollers = true

        let tv = DropTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        tv.textColor = NSColor(white: 0.94, alpha: 1)
        tv.insertionPointColor = .white
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.registerForDraggedTypes([.fileURL])
        tv.string = text

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditorTextView
        init(_ p: EditorTextView) { parent = p }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
        }
    }
}

// MARK: - Lightweight markdown preview

struct MarkdownView: View {
    let text: String
    var onOpenNote: (String) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, blk in
                view(for: blk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        // Tapping a [[wiki-link]] (rewritten to a cherrynote: URL) jumps to that note in place.
        .environment(\.openURL, OpenURLAction { url in
            let raw = url.absoluteString
            if raw.hasPrefix("cherrynote:") {
                let ref = String(raw.dropFirst("cherrynote:".count)).removingPercentEncoding
                    ?? String(raw.dropFirst("cherrynote:".count))
                onOpenNote(ref)
                return .handled
            }
            return .systemAction
        })
    }

    // [[ref]] and [[ref|label]] → [label](cherrynote:<encoded ref>) so AttributedString linkifies them.
    private func linkifyWiki(_ s: String) -> String {
        guard s.contains("[["), let re = try? NSRegularExpression(pattern: "\\[\\[([^\\]|]+)(\\|([^\\]]+))?\\]\\]")
        else { return s }
        let ns = s as NSString
        var out = ""; var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let ref = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let label = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ref
            let enc = ref.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ref
            out += "[\(label)](cherrynote:\(enc))"
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    enum Block { case h1(String), h2(String), h3(String), p(String), bullet([String])
                 case code(String), image(String, String), quote(String), rule
                 case table([[String]], Int) }   // rows, header-row count

    private func tableCells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                var buf: [String] = []; i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    buf.append(lines[i]); i += 1
                }
                i += 1; out.append(.code(buf.joined(separator: "\n"))); continue
            }
            if t.isEmpty { i += 1; continue }
            if let img = parseImage(t) { out.append(.image(img.0, img.1)); i += 1; continue }
            if t == "---" || t == "***" || t == "___" { out.append(.rule); i += 1; continue }
            if t.hasPrefix("### ") { out.append(.h3(String(t.dropFirst(4)))); i += 1; continue }
            if t.hasPrefix("## ") { out.append(.h2(String(t.dropFirst(3)))); i += 1; continue }
            if t.hasPrefix("# ") { out.append(.h1(String(t.dropFirst(2)))); i += 1; continue }
            // GitHub-style table: consecutive |a|b| lines; a |---|---| row marks the header break.
            if t.hasPrefix("|") && t.dropFirst().contains("|") {
                var rows: [[String]] = []; var headerCount = 0
                while i < lines.count {
                    let lt = lines[i].trimmingCharacters(in: .whitespaces)
                    guard lt.hasPrefix("|") else { break }
                    let cells = tableCells(lt)
                    let isSep = cells.allSatisfy { c in !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" } }
                    if isSep { headerCount = rows.count; i += 1; continue }
                    rows.append(cells); i += 1
                }
                if !rows.isEmpty { out.append(.table(rows, headerCount)) }
                continue
            }
            if t.hasPrefix("> ") {
                var buf: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    buf.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))); i += 1
                }
                out.append(.quote(buf.joined(separator: " "))); continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                var buf: [String] = []
                while i < lines.count {
                    let lt = lines[i].trimmingCharacters(in: .whitespaces)
                    if lt.hasPrefix("- ") || lt.hasPrefix("* ") { buf.append(String(lt.dropFirst(2))); i += 1 }
                    else { break }
                }
                out.append(.bullet(buf)); continue
            }
            // paragraph: gather consecutive plain lines
            var buf: [String] = []
            while i < lines.count {
                let lt = lines[i].trimmingCharacters(in: .whitespaces)
                if lt.isEmpty || lt.hasPrefix("#") || lt.hasPrefix("- ") || lt.hasPrefix("* ")
                    || lt.hasPrefix("> ") || lt.hasPrefix("```") || lt == "---" { break }
                buf.append(lt); i += 1
            }
            out.append(.p(buf.joined(separator: " ")))
        }
        return out
    }

    private func parseImage(_ s: String) -> (String, String)? {
        guard s.hasPrefix("!["), let close = s.firstIndex(of: "]"),
              let open = s.range(of: "]("), s.hasSuffix(")") else { return nil }
        let alt = String(s[s.index(s.startIndex, offsetBy: 2)..<close])
        let path = String(s[open.upperBound..<s.index(before: s.endIndex)])
        return (path, alt)
    }

    private func inline(_ s: String) -> AttributedString {
        let src = linkifyWiki(s)
        return (try? AttributedString(markdown: src,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    @ViewBuilder private func view(for b: Block) -> some View {
        switch b {
        case .h1(let s): Text(inline(s)).font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
        case .h2(let s): Text(inline(s)).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .padding(.top, 4)
        case .h3(let s): Text(inline(s)).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .p(let s): Text(inline(s)).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.85))
                .lineSpacing(3)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.white.opacity(0.55))
                        Text(inline(it)).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        case .code(let s):
            Text(s).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.green.opacity(0.9))
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.28)))
                .textSelection(.enabled)
        case .image(let path, let alt):
            let full = path.hasPrefix("assets/")
                ? ASSETS_DIR + "/" + String(path.dropFirst(7))
                : (path.hasPrefix("/") ? path : ASSETS_DIR + "/" + path)
            if isVideoExt((full as NSString).pathExtension) {
                NoteVideo(path: full)
            } else {
                AsyncNoteImage(path: full, alt: alt)
            }
        case .quote(let s):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.3)).frame(width: 3)
                Text(inline(s)).font(.system(size: 13, weight: .regular).italic())
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .rule: Divider().overlay(.white.opacity(0.15))
        case .table(let rows, let headerCount):
            let cols = rows.map { $0.count }.max() ?? 0
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                        GridRow {
                            ForEach(0..<cols, id: \.self) { ci in
                                Text(inline(ci < row.count ? row[ci] : ""))
                                    .font(.system(size: 12.5, weight: ri < headerCount ? .bold : .regular))
                                    .foregroundStyle(.white.opacity(ri < headerCount ? 0.98 : 0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if ri < headerCount || (headerCount == 0 && ri == 0) {
                            Divider().overlay(.white.opacity(0.16)).gridCellUnsizedAxes(.horizontal)
                        }
                    }
                }
                .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.045)))
        }
    }
}

// MARK: - Async, downscaled note images
// The preview used to call NSImage(contentsOfFile:) synchronously in the view body and hold the
// full-resolution bitmap — fine for a screenshot, brutal for the campaign's 1–2.4 MB PNGs, which
// stalled scrolling and spiked memory (a plausible contributor to instability). We now decode a
// display-sized thumbnail off the main thread via ImageIO and cache it.

final class NoteImageCache {
    static let shared = NoteImageCache()
    let cache = NSCache<NSString, NSImage>()
    private init() { cache.countLimit = 120 }
}

// Thread-safe: CGImageSource thumbnail generation decodes at reduced size and is safe off-main
// (unlike NSImage.lockFocus drawing).
func loadThumbnail(path: String, maxPixel: CGFloat) -> NSImage? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let src = CGImageSourceCreateWithURL(url, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}

struct AsyncNoteImage: View {
    let path: String
    let alt: String
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if failed {
                Text("🖼 \(alt)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05))
                    .frame(height: 140)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        if let cached = NoteImageCache.shared.cache.object(forKey: path as NSString) {
            image = cached; return
        }
        let p = path
        let loaded = await Task.detached(priority: .userInitiated) {
            loadThumbnail(path: p, maxPixel: 1360)   // ~680pt @2x
        }.value
        if let loaded {
            NoteImageCache.shared.cache.setObject(loaded, forKey: p as NSString)
            image = loaded
        } else {
            failed = true
        }
    }
}

// Inline video player for embedded clips (drag a .mp4/.mov into a note → it plays here).
struct NoteVideo: View {
    let path: String
    @State private var player: AVPlayer?
    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.35))
                    .frame(height: 300)
                    .overlay(Image(systemName: "play.rectangle").font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.5)))
            }
        }
        .task(id: path) {
            if FileManager.default.fileExists(atPath: path) {
                player = AVPlayer(url: URL(fileURLWithPath: path))
            }
        }
    }
}
