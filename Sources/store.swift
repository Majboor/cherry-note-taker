import Foundation

// In-memory note index shared by the popover and the full-screen window.
//
// Cherry used to re-read every .md file and rebuild the whole popover page on every click.
// Fine at 50 notes; at ~3,000 (agent run logs) it took seconds. Now the folder is read once,
// kept in memory, and refreshed incrementally: a folder watcher (plus a cheap stat-only scan
// on demand) re-reads only files whose mtime changed and drops the ones that vanished.
//
// Run logs — any file named *-run-<digits>* (the same rule make-launchers.sh uses) — are kept
// apart from ordinary notes and are only paged out to the UI when asked for.

func isRunLogName(_ name: String) -> Bool { name.range(of: "-run-[0-9]", options: .regularExpression) != nil }
func runAgent(_ name: String) -> String {
    guard let r = name.range(of: "-run-[0-9]", options: .regularExpression) else { return name }
    return String(name[..<r.lowerBound])
}

// Drop a leading YAML-ish frontmatter block (--- … ---).
func stripFrontmatter(_ s: String) -> String {
    guard s.hasPrefix("---") else { return s }
    let lines = s.components(separatedBy: "\n")
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return s }
    var i = 1
    while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces) != "---" { i += 1 }
    guard i < lines.count else { return s }
    return lines[(i + 1)...].joined(separator: "\n")
}

// One-line preview for list rows (mirrors the old firstText() in the page script).
func previewText(_ body: String) -> String {
    for raw in stripFrontmatter(body).split(separator: "\n", omittingEmptySubsequences: false) {
        let l = raw.trimmingCharacters(in: .whitespaces)
        if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("---") || l.hasPrefix("```") { continue }
        let t = l.replacingOccurrences(of: "[*`>#_\\[\\]]", with: "", options: .regularExpression)
                 .replacingOccurrences(of: "\\([^)]+\\)", with: "", options: .regularExpression)
        return String(t.prefix(90))
    }
    return "No additional text"
}

// JSON text for a JS literal (safe inside an inline <script> too).
func jsText(_ obj: Any) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data("null".utf8)
    return (String(data: data, encoding: .utf8) ?? "null").replacingOccurrences(of: "</", with: "<\\/")
}

final class NoteStore {
    static let shared = NoteStore()
    private static let preferred = ["NAS", "email"]

    private let lock = NSLock()
    private var byName: [String: Note] = [:]
    private var scanned = false
    private let queue = DispatchQueue(label: "com.hico.cherry.notestore", qos: .userInitiated)
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    /// Main-thread callback after a background scan found changes; receives changed/removed names.
    var onChange: ((Set<String>) -> Void)?

    // MARK: reading

    private func makeNote(name: String, body: String, mtime: Double) -> Note {
        var title = name
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") { title = String(line.dropFirst(2)); break }
        }
        let (category, tags, pinned, parent) = parseFrontmatter(body)
        return Note(name: name, title: title, category: category, tags: tags, body: body,
                    mtime: mtime, pinned: pinned, parent: parent)
    }
    private func readNote(_ name: String, mtime: Double) -> Note? {
        guard let body = try? String(contentsOfFile: NOTES_DIR + "/" + name + ".md", encoding: .utf8) else { return nil }
        return makeNote(name: name, body: body, mtime: mtime)
    }

    /// Incremental refresh: one bulk directory listing (names + mtimes), then re-read only what
    /// changed. Safe from any thread. Returns the names that were (re)loaded or removed.
    @discardableResult
    func scan() -> Set<String> {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let dir = URL(fileURLWithPath: NOTES_DIR, isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys),
                                                                 options: [.skipsHiddenFiles])) ?? []
        var onDisk: [String: Double] = [:]
        for u in urls {
            let file = u.lastPathComponent
            guard file.hasSuffix(".md") else { continue }
            let m = ((try? u.resourceValues(forKeys: keys))?.contentModificationDate)?.timeIntervalSince1970 ?? 0
            onDisk[String(file.dropLast(3))] = m
        }
        lock.lock(); let cached = byName.mapValues { $0.mtime }; lock.unlock()
        let toRead = onDisk.filter { cached[$0.key] != $0.value }.map { $0.key }
        let removed = Set(cached.keys).subtracting(onDisk.keys)
        let loaded = toRead.compactMap { readNote($0, mtime: onDisk[$0] ?? 0) }
        lock.lock()
        for r in removed { byName[r] = nil }
        for n in loaded { byName[n.name] = n }
        scanned = true
        lock.unlock()
        return Set(toRead).union(removed)
    }
    func ensureScanned() {
        lock.lock(); let done = scanned; lock.unlock()
        if !done { scan() }
    }

    // MARK: queries (all served from memory)

    /// Ordinary notes in display order: pinned first (stable preferred/alphabetical order), then
    /// NAS/email, then everything else by recency. Run logs are excluded.
    func notes() -> [Note] {
        ensureScanned()
        lock.lock(); let all = byName.values.filter { !isRunLogName($0.name) }; lock.unlock()
        let pref = NoteStore.preferred
        let base = all.sorted { a, b in
            let ia = pref.firstIndex(of: a.name) ?? pref.count, ib = pref.firstIndex(of: b.name) ?? pref.count
            if ia != ib { return ia < ib }
            return a.name + ".md" < b.name + ".md"
        }
        let pinned = base.filter { $0.pinned }
        let preferredNotes = base.filter { !$0.pinned && pref.contains($0.name) }
        let rest = base.filter { !$0.pinned && !pref.contains($0.name) }.sorted { $0.mtime > $1.mtime }
        return pinned + preferredNotes + rest
    }
    /// Run logs, newest first.
    func runs() -> [Note] {
        ensureScanned()
        lock.lock(); let all = byName.values.filter { isRunLogName($0.name) }; lock.unlock()
        return all.sorted { $0.mtime > $1.mtime }
    }
    func note(_ name: String) -> Note? {
        ensureScanned()
        lock.lock(); defer { lock.unlock() }
        return byName[name]
    }
    func meta(_ n: Note) -> [String: Any] {
        ["name": n.name, "title": n.title, "category": n.category, "tags": n.tags,
         "mtime": Int(n.mtime), "pinned": n.pinned, "preview": previewText(n.body), "run": isRunLogName(n.name)]
    }
    /// Ordinary notes whose body wiki-links [[title]] or [[name]] of `n`.
    func backlinks(to n: Note) -> [Note] {
        let t = "[[" + n.title + "]]", nm = "[[" + n.name + "]]"
        return notes().filter { o in
            o.name != n.name && (o.body.range(of: t, options: .caseInsensitive) != nil
                                 || o.body.range(of: nm, options: .caseInsensitive) != nil)
        }
    }
    /// Full-text search over ordinary notes → matching names.
    func search(_ q: String) -> [String] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return notes().filter { $0.body.range(of: q, options: .caseInsensitive) != nil }.map { $0.name }
    }
    /// One page of run logs, optionally narrowed to an agent and/or a search string, plus the
    /// per-agent totals for the filter chips.
    func runsPage(agent: String?, q: String, offset: Int, limit: Int) -> [String: Any] {
        let all = runs()
        var count: [String: Int] = [:], latest: [String: Double] = [:], order: [String] = []
        for r in all {
            let a = runAgent(r.name)
            if count[a] == nil { order.append(a) }
            count[a, default: 0] += 1
            latest[a] = max(latest[a] ?? 0, r.mtime)
        }
        let groups = order.map { ["agent": $0, "count": count[$0] ?? 0, "latest": Int(latest[$0] ?? 0)] }
        let q = q.trimmingCharacters(in: .whitespaces)
        let filtered = all.filter { r in
            (agent == nil || runAgent(r.name) == agent!)
            && (q.isEmpty || r.title.range(of: q, options: .caseInsensitive) != nil
                          || r.body.range(of: q, options: .caseInsensitive) != nil)
        }
        let page = filtered.dropFirst(max(0, offset)).prefix(max(1, limit))
        return ["agent": agent ?? "", "q": q, "offset": max(0, offset), "total": filtered.count,
                "all": all.count, "groups": groups, "items": page.map(meta)]
    }

    // MARK: writes (file + cache together, so the UI never waits on a rescan)

    func write(name: String, body: String) {
        let path = NOTES_DIR + "/" + name + ".md"
        try? FileManager.default.createDirectory(atPath: NOTES_DIR, withIntermediateDirectories: true)
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
        let m = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let n = makeNote(name: name, body: body, mtime: m)
        lock.lock(); byName[name] = n; lock.unlock()
    }
    /// Moves the note to the Trash (recoverable) and forgets it.
    func delete(name: String) {
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: NOTES_DIR + "/" + name + ".md"), resultingItemURL: nil)
        lock.lock(); byName[name] = nil; lock.unlock()
    }

    // MARK: folder watcher

    /// Watch the notes folder; new/renamed/deleted files trigger a debounced background scan.
    /// (In-place edits don't touch the directory vnode — scheduleScan() covers those on demand.)
    func startWatching() {
        let fd = open(NOTES_DIR, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                            eventMask: [.write, .rename, .delete, .attrib, .extend], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan(after: 0.35) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }
    /// Background incremental scan (debounced); fires onChange on the main thread if anything moved.
    func scheduleScan(after delay: Double = 0) {
        queue.async { [self] in
            debounce?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let changed = self.scan()
                guard !changed.isEmpty else { return }
                DispatchQueue.main.async { self.onChange?(changed) }
            }
            debounce = item
            queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }
}
