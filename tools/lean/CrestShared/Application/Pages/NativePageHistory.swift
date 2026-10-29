import Foundation

/// Bounded WebKit history, including cold entries retained when a renderer
/// is released. Native restoration may rename entry identities by position.
final class NativePageHistory {
    static let capacity = 100
    private final class Run {
        var entries: [PageHistoryEntry]
        var current: Int
        var start: UUID?
        var boundary: UUID?
        init(entries: [PageHistoryEntry] = [], current: Int = -1, start: UUID? = nil, boundary: UUID? = nil) {
            self.entries = entries
            self.current = current
            self.start = start
            self.boundary = boundary
        }
        func holds(_ id: UUID) -> Bool { entries.contains { $0.id == id } }
        func slice(_ from: Int, _ to: Int) -> Run {
            Run(
                entries: Array(entries[from..<to]),
                current: (from..<to).contains(current) ? current - from : to - from - 1,
                start: entries[from].id, boundary: entries[to - 1].id)
        }
    }
    private struct Arrival {
        let run: Run
        var entry: UUID
        let native: [UUID]
        var restored: UUID?
    }
    private var runs: [Run] = []
    private var live = -1
    private var native: [UUID] = []
    private var arriving: Arrival?
    private var going: UUID?
    var entries: [PageHistoryEntry] { runs.flatMap(\.entries) }
    var current: Int {
        live < 0 || runs[live].current < 0
            ? -1 : runs.prefix(live).reduce(0) { $0 + $1.entries.count } + runs[live].current
    }
    var shown: PageHistoryEntry? { current >= 0 ? entries[current] : nil }
    var canGoBack: Bool { current > 0 }
    var canGoForward: Bool { current >= 0 && current < entries.count - 1 }
    var back: [PageHistoryEntry] { Array(entries.prefix(max(current, 0)).reversed()) }
    var forward: [PageHistoryEntry] { current < 0 ? [] : Array(entries.dropFirst(current + 1)) }
    static func holds(_ entries: [PageHistoryEntry], _ current: Int) -> Bool {
        (entries.isEmpty ? current == -1 : entries.indices.contains(current))
            && entries.count <= capacity && Set(entries.map(\.id)).count == entries.count
    }
    @discardableResult
    func report(_ reported: [PageHistoryEntry], _ current: Int) -> UUID? {
        guard Self.holds(reported, current) else { return nil }
        guard !reported.isEmpty else {
            native = []
            return nil
        }
        if live < 0 {
            runs.append(Run())
            live = runs.count - 1
        }
        let shown = reported[current].id
        var target: UUID?
        if let asked = going,
            shown == asked || !runs.contains(where: { $0.holds(shown) })
                || native.contains(asked) && !reported.contains(where: { $0.id == asked })
        {
            going = nil
        }
        var restoring = arriving.map { $0.run === runs[live] && ($0.restored == nil || $0.restored == shown) } ?? false
        if restoring, var arrival = arriving {
            var entry = arrival.entry
            var restored = true
            if arrival.restored == nil {
                restored = rename(arrival.native, reported, &entry)
                target = entry
            }
            arrival.entry = entry
            arrival.restored = shown
            arriving = shown == entry ? nil : arrival
            if !restored {
                recover(entry)
                restoring = false
                target = nil
            }
        } else {
            arriving = nil
            if !runs[live].holds(shown), let other = runs.firstIndex(where: { $0.holds(shown) }) { live = other }
        }
        let run = runs[live]
        var from = run.start.flatMap { start in reported.firstIndex { $0.id == start } } ?? 0
        var to = run.boundary.flatMap { end in reported.firstIndex { $0.id == end } } ?? reported.count - 1
        if !restoring && current > to {
            run.boundary = nil
            to = reported.count - 1
            dropAfter(live)
        }
        if !restoring && current < from {
            run.start = nil
            from = 0
        }
        var anchor = min(max(current, from), to)
        if let arrival = arriving, let at = reported.firstIndex(where: { $0.id == arrival.entry }),
            (from...to).contains(at)
        {
            anchor = at
        }
        if anchor > from {
            for index in stride(from: anchor - 1, through: from, by: -1) where foreign(run, reported[index].id) {
                from = index + 1
                break
            }
        }
        if anchor < to {
            for index in (anchor + 1)...to where foreign(run, reported[index].id) {
                to = index - 1
                break
            }
        }
        let slice = Array(reported[from...to])
        let at = anchor - from
        if !restoring && !run.entries.isEmpty && !run.holds(slice[at].id) { dropAfter(live) }
        run.entries = slice
        run.current = at
        native = reported.map(\.id)
        trim()
        return target.flatMap { id in id != shown && slice.contains(where: { $0.id == id }) ? id : nil }
    }
    private func foreign(_ run: Run, _ id: UUID) -> Bool { runs.contains { $0 !== run && $0.holds(id) } }
    private func rename(_ kept: [UUID], _ reported: [PageHistoryEntry], _ target: inout UUID) -> Bool {
        let goal = target
        if kept.allSatisfy({ id in reported.contains { $0.id == id } }) { return reported.contains { $0.id == goal } }
        guard kept.count == reported.count else { return false }
        for (index, id) in kept.enumerated() {
            if let known = entry(id), !PageAddress.samePage(known.url, reported[index].url) { return false }
        }
        var renamed: [UUID: UUID] = [:]
        for (old, new) in zip(kept, reported.map(\.id)) { renamed[old] = new }
        func of(_ id: UUID) -> UUID { renamed[id] ?? id }
        for run in runs {
            run.entries = run.entries.map { PageHistoryEntry(id: of($0.id), url: $0.url, title: $0.title) }
            run.start = run.start.map(of)
            run.boundary = run.boundary.map(of)
        }
        target = of(target)
        return reported.contains { $0.id == goal } || renamed[goal] != nil
    }
    private func recover(_ id: UUID) {
        let run = runs[live]
        run.current = run.entries.firstIndex { $0.id == id } ?? run.current
        arriving = nil
        leave(entry(id)?.url)
    }
    private func dropAfter(_ index: Int) {
        if index + 1 < runs.count { runs.removeSubrange((index + 1)..<runs.count) }
    }
    private func trim() {
        while runs.reduce(0, { $0 + $1.entries.count }) > Self.capacity {
            let oldest = runs[0]
            if live == 0 && oldest.current <= 0 { return }
            if oldest.entries.isEmpty {
                runs.removeFirst()
                live -= 1
                continue
            }
            oldest.entries.removeFirst()
            oldest.current = oldest.entries.isEmpty ? -1 : max(oldest.current - 1, 0)
            if let first = oldest.entries.first {
                oldest.start = first.id
            } else if live > 0 {
                runs.removeFirst()
                live -= 1
            }
        }
    }
    private func leave(_ address: String?) {
        var at = runs.count
        if live >= 0 {
            let run = runs[live]
            let moves =
                address.map { run.current >= 0 && PageAddress.samePage(run.entries[run.current].url, $0) } ?? false
            if !moves { dropAfter(live) }
            if run.current >= 0 {
                if moves && run.current + 1 < run.entries.count {
                    runs.insert(run.slice(run.current + 1, run.entries.count), at: live + 1)
                }
                let keep = moves ? run.current : run.current + 1
                run.entries = Array(run.entries.prefix(keep))
                run.current = keep - 1
            }
            at = live + 1
            if run.entries.isEmpty {
                runs.remove(at: live)
                at = live
            } else {
                run.boundary = run.entries.last?.id
            }
        }
        let arrival = Run()
        runs.insert(arrival, at: at)
        arrive(at)
    }
    @discardableResult
    func load(_ id: UUID) -> PageHistoryEntry {
        let run = runs[live]
        if run.current >= 0 && run.current + 1 < run.entries.count {
            let ahead = run.slice(run.current + 1, run.entries.count)
            run.entries = Array(run.entries.prefix(run.current + 1))
            run.boundary = run.entries.last?.id
            runs.insert(ahead, at: live + 1)
        } else if run.current >= 0 {
            run.boundary = run.entries.last?.id
        }
        let held = native
        let targetIndex = runs.firstIndex { $0.holds(id) }!
        let target = runs[targetIndex]
        let at = target.entries.firstIndex { $0.id == id }!
        let entry = target.entries[at]
        var parts: [Run] = []
        if at > 0 { parts.append(target.slice(0, at)) }
        let arrival = Run(entries: [entry], current: 0)
        parts.append(arrival)
        if at + 1 < target.entries.count { parts.append(target.slice(at + 1, target.entries.count)) }
        runs.replaceSubrange(targetIndex...targetIndex, with: parts)
        arrive(runs.firstIndex { $0 === arrival }!)
        runs[live].start = id
        native = held
        going = id
        return entry
    }
    private func arrive(_ index: Int) {
        live = index
        native = []
        arriving = nil
        going = nil
    }
    func reopen(restores: Bool) {
        if live >= 0 && restores && runs[live].current >= 0 {
            arriving = Arrival(run: runs[live], entry: runs[live].entries[runs[live].current].id, native: native)
            native = []
        } else {
            leave(shown?.url)
        }
    }
    func go(_ id: UUID) { going = id }
    func step(_ offset: Int) -> PageHistoryEntry? {
        let (index, overflow) = current.addingReportingOverflow(offset)
        return offset != 0 && current >= 0 && !overflow && entries.indices.contains(index) ? entries[index] : nil
    }
    func reaches(_ id: UUID) -> Bool {
        current >= 0 && entries.enumerated().contains { $0.offset != current && $0.element.id == id }
    }
    func holds(_ id: UUID) -> Bool { live >= 0 && native.contains(id) && runs.contains { $0.holds(id) } }
    func entry(_ id: UUID) -> PageHistoryEntry? { entries.first { $0.id == id } }

    private struct StoredEntry: Codable {
        let id: String
        let url: String
        let title: String
        init(_ entry: PageHistoryEntry) {
            id = entry.id.uuidString.lowercased()
            url = entry.url
            title = entry.title
        }
        var value: PageHistoryEntry? { UUID(uuidString: id).map { PageHistoryEntry(id: $0, url: url, title: title) } }
    }
    private struct StoredRun: Codable {
        let entries: [StoredEntry]
        let current: Int
        let start: String?
        let boundary: String?
    }
    private struct Archive: Codable {
        let version: Int
        let live: Int
        let native: [String]
        let runs: [StoredRun]
    }
    func archive() -> Data? {
        guard shown != nil else { return nil }
        return try? JSONEncoder().encode(
            Archive(
                version: 2, live: live, native: (arriving?.native ?? native).map { $0.uuidString.lowercased() },
                runs: runs.map {
                    StoredRun(
                        entries: $0.entries.map(StoredEntry.init), current: $0.current,
                        start: $0.start?.uuidString.lowercased(), boundary: $0.boundary?.uuidString.lowercased())
                }))
    }
    static func unarchive(_ data: Data?) -> NativePageHistory? {
        guard let data, let value = try? JSONSerialization.jsonObject(with: data), depth(value, 1) <= 8,
            let stored = try? JSONDecoder().decode(Archive.self, from: data), stored.version == 2
        else { return nil }
        let history = NativePageHistory()
        history.live = stored.live
        history.native = stored.native.compactMap(UUID.init(uuidString:))
        guard history.native.count == stored.native.count else { return nil }
        for stored in stored.runs {
            let entries = stored.entries.compactMap(\.value)
            let start = stored.start.flatMap(UUID.init(uuidString:))
            let boundary = stored.boundary.flatMap(UUID.init(uuidString:))
            guard !entries.isEmpty, entries.count == stored.entries.count, entries.indices.contains(stored.current),
                stored.start == nil || start != nil, stored.boundary == nil || boundary != nil
            else { return nil }
            let first = start.flatMap { id in entries.firstIndex { $0.id == id } } ?? (start == nil ? 0 : -1)
            let last =
                boundary.flatMap { id in entries.firstIndex { $0.id == id } }
                ?? (boundary == nil ? entries.count - 1 : -1)
            guard first < 0 || last < 0 || last >= first else { return nil }
            history.runs.append(Run(entries: entries, current: stored.current, start: start, boundary: boundary))
        }
        let entries = history.entries
        return history.runs.indices.contains(history.live) && entries.count <= capacity
            && Set(entries.map(\.id)).count == entries.count ? history : nil
    }
    private static func depth(_ value: Any, _ level: Int) -> Int {
        guard level <= 8 else { return level }
        if let object = value as? [String: Any] { return object.values.map { depth($0, level + 1) }.max() ?? level }
        if let array = value as? [Any] { return array.map { depth($0, level + 1) }.max() ?? level }
        return level - 1
    }
}

/// Page identity preserves the recorded spelling and ignores only web fragments.
/// Ordinal comparison keeps distinct Unicode spellings distinct, as Crest does.
enum PageAddress {
    static func held(_ spelling: String) -> String? {
        let value = spelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            ["http", "https", "about", "blob", "crest-extension", "data", "webkit-extension", "file"].contains(scheme),
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return nil }
        if ["http", "https"].contains(scheme), url.host?.isEmpty != false { return nil }
        return value
    }

    static func samePage(_ first: String, _ second: String) -> Bool {
        Data(key(first).utf8) == Data(key(second).utf8)
    }
    private static func key(_ spelling: String) -> String {
        guard let url = URL(string: spelling.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["http", "https"].contains(url.scheme?.lowercased()), url.host?.isEmpty == false,
            url.port.map({ (0...65535).contains($0) }) ?? true
        else { return spelling }
        return String(spelling.prefix { $0 != "#" })
    }
}
