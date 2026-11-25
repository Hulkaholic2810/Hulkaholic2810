import Foundation
import Observation

// MARK: - Data

enum WeightUnit: String, Codable, CaseIterable { case kg, lb }

enum Paper: String, Codable, CaseIterable, Identifiable {
    case grain, dots, ruled, plain
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum Tone: String, Codable { case day, night }

struct LiftSet: Codable, Identifiable, Equatable {
    var id = UUID()
    /// nil means bodyweight
    var weight: Double?
    /// the unit the weight was typed in; other units are shown converted
    var unit: WeightUnit
    var reps: Int?
    var done = false
    /// when the set was ticked; PRs are judged in this order, whatever page the set is on
    var doneAt: Date?
}

struct Exercise: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var sets: [LiftSet] = []
    var sample = false
}

struct Day: Codable, Equatable {
    var title = ""
    var exercises: [Exercise] = []
    var sampleTitle = false
}

struct Settings: Codable, Equatable {
    var unit: WeightUnit = .kg
    var rest = 90
    var autoRest = true
    var chime = true
    var paper: Paper = .grain
    var tone: Tone = .day
    var followDevice = false
    var owner = ""
}

struct LogData: Codable, Equatable {
    var days: [String: Day] = [:]
    var settings = Settings()
    var timerEnd: Date?
    var timerDuration: Int?
}

struct Record: Equatable {
    var weight: Double
    var unit: WeightUnit
    var kg: Double
    var day: String
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let undoable: Bool
}

/// Pages are keyed by local calendar day, "yyyy-MM-dd".
enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date { formatter.date(from: key) ?? Date() }
    static var today: String { key(Date()) }
    static func add(_ key: String, _ days: Int) -> String {
        self.key(Calendar.current.date(byAdding: .day, value: days, to: date(key)) ?? Date())
    }
}

// MARK: - Store

@MainActor
@Observable
final class LogStore {
    var data: LogData
    var current: String = DayKey.today
    var toast: Toast?
    private(set) var prPrevious: [UUID: Record] = [:]
    private(set) var bests: [String: Record] = [:]
    let timer = RestTimer()

    @ObservationIgnored private var undoSnapshot: LogData?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let lbPerKg = 2.2046226218

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pocketlog.json")
    }

    init() {
        if let raw = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(LogData.self, from: raw) {
            data = saved
        } else {
            data = Self.sample()
        }
        recompute()
        timer.onFinish = { [weak self] in self?.data.timerEnd = nil }
        timer.resume(end: data.timerEnd, duration: data.timerDuration)
    }

    // MARK: saving

    /// Called whenever `data` changes.
    func changed() {
        recompute()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        var snapshot = data
        snapshot.days = snapshot.days.filter { !$0.value.title.isEmpty || !$0.value.exercises.isEmpty }
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: Self.fileURL, options: .atomic)
        } catch {
            print("save failed:", error)
        }
    }

    // MARK: current page

    var day: Day {
        get { data.days[current] ?? Day() }
        set { data.days[current] = newValue }
    }

    var isToday: Bool { current == DayKey.today }

    var dateLabel: (date: String, weekday: String) {
        let d = DayKey.date(current)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let sameYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
        f.dateFormat = sameYear ? "MMM d" : "MMM d yyyy"
        let date = f.string(from: d).uppercased()
        f.dateFormat = "EEE"
        return (date, f.string(from: d).uppercased())
    }

    var brand: String {
        let n = data.settings.owner.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "Pocket Lift Log" }
        return n.lowercased().hasSuffix("s") ? "\(n)’ Pocket Log" : "\(n)’s Pocket Log"
    }

    var summary: String {
        let exs = day.exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || !$0.sets.isEmpty }
        guard !exs.isEmpty else { return "Blank page" }
        let sets = exs.flatMap(\.sets).filter { $0.reps != nil }
        let done = sets.filter(\.done)
        let volume = done.reduce(0.0) { $0 + ($1.weight.map { shown($0, $1.unit) } ?? 0) * Double($1.reps ?? 0) }
        var parts = ["\(exs.count) exercise\(exs.count == 1 ? "" : "s")", "\(done.count)/\(sets.count) sets"]
        if volume > 0 { parts.append("\(Int(volume.rounded()).formatted()) \(unit.rawValue) moved") }
        return parts.joined(separator: " · ")
    }

    var hasSamples: Bool { data.days.values.contains { $0.exercises.contains(where: \.sample) } }

    var allNames: [String] {
        var seen = Set<String>(), names: [String] = []
        for k in data.days.keys.sorted(by: >) {
            for ex in data.days[k]?.exercises ?? [] {
                let n = ex.name.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty, seen.insert(Self.norm(n)).inserted { names.append(n) }
            }
        }
        return names
    }

    // MARK: units

    var unit: WeightUnit { data.settings.unit }

    /// A weight in the active unit. Entries typed in the active unit show as typed; conversions round to 0.5.
    func shown(_ w: Double, _ u: WeightUnit) -> Double {
        if u == unit { return w }
        return Self.round05(unit == .lb ? w * Self.lbPerKg : w / Self.lbPerKg)
    }

    static func round05(_ x: Double) -> Double { (x * 2).rounded() / 2 }
    static func kg(_ w: Double, _ u: WeightUnit) -> Double { u == .lb ? w / lbPerKg : w }
    static func num(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
    }
    static func norm(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func setText(_ s: LiftSet) -> String {
        "\(s.weight.map { Self.num(shown($0, s.unit)) } ?? "BW")×\(s.reps ?? 0)"
    }

    // MARK: history and PRs

    func last(for name: String) -> (day: String, sets: [LiftSet])? {
        let n = Self.norm(name)
        guard !n.isEmpty else { return nil }
        for k in data.days.keys.sorted(by: >) where k < current {
            if let ex = data.days[k]?.exercises.first(where: { Self.norm($0.name) == n && $0.sets.contains { $0.reps != nil } }) {
                return (k, ex.sets.filter { $0.reps != nil })
            }
        }
        return nil
    }

    /// Walk every completed set in the order it was ticked; a set is a PR when it beats the best weight before it.
    func recompute() {
        struct Item { let time: Date; let name: String; let set: LiftSet; let day: String; let weight: Double }
        var items: [Item] = []
        for (k, d) in data.days {
            let base = DayKey.date(k)
            var i = 0
            for ex in d.exercises {
                let n = Self.norm(ex.name)
                for s in ex.sets {
                    i += 1
                    guard !n.isEmpty, s.done, let w = s.weight else { continue }
                    items.append(Item(time: s.doneAt ?? base.addingTimeInterval(Double(i) / 1000), name: n, set: s, day: k, weight: w))
                }
            }
        }
        items.sort { $0.time < $1.time }
        var best: [String: Record] = [:], previous: [UUID: Record] = [:]
        for it in items {
            let kg = Self.kg(it.weight, it.set.unit)
            if let b = best[it.name], kg > b.kg + 1e-6 { previous[it.set.id] = b }
            if kg > (best[it.name]?.kg ?? -1) + 1e-6 {
                best[it.name] = Record(weight: it.weight, unit: it.set.unit, kg: kg, day: it.day)
            }
        }
        if previous != prPrevious { prPrevious = previous }
        if best != bests { bests = best }
    }

    func prNote(_ s: LiftSet) -> String? {
        guard let p = prPrevious[s.id], let w = s.weight else { return nil }
        let diff = ((shown(w, s.unit) - shown(p.weight, p.unit)) * 100).rounded() / 100
        return diff > 0 ? "↳ New PR — up by +\(Self.num(diff)) \(unit.rawValue)" : "↳ New PR"
    }

    func best(for name: String) -> Record? { bests[Self.norm(name)] }

    // MARK: editing

    func exercise(_ id: UUID) -> Exercise? { day.exercises.first { $0.id == id } }

    func updateExercise(_ id: UUID, _ body: (inout Exercise) -> Void) {
        var d = day
        guard let i = d.exercises.firstIndex(where: { $0.id == id }) else { return }
        body(&d.exercises[i])
        day = d
    }

    func updateSet(_ exID: UUID, _ setID: UUID, _ body: (inout LiftSet) -> Void) {
        updateExercise(exID) { ex in
            if let j = ex.sets.firstIndex(where: { $0.id == setID }) { body(&ex.sets[j]) }
        }
    }

    func exerciseID(containing setID: UUID) -> UUID? {
        day.exercises.first { $0.sets.contains { $0.id == setID } }?.id
    }

    func addExercise() -> UUID {
        let ex = Exercise()
        day.exercises.append(ex)
        return ex.id
    }

    /// New sets copy the previous set, or the same set from last session.
    @discardableResult
    func addSet(to exID: UUID) -> UUID? {
        guard let ex = exercise(exID) else { return nil }
        let lastSets = last(for: ex.name)?.sets ?? []
        let prev = ex.sets.last ?? (lastSets.indices.contains(ex.sets.count) ? lastSets[ex.sets.count] : nil)
        let s = LiftSet(weight: prev?.weight, unit: prev?.unit ?? unit, reps: prev?.reps)
        updateExercise(exID) { $0.sets.append(s) }
        return s.id
    }

    func copyLast(_ exID: UUID) {
        guard let ex = exercise(exID), let last = last(for: ex.name) else { return }
        updateExercise(exID) { e in
            e.sets.removeAll { $0.reps == nil && $0.weight == nil }
            for s in last.sets.dropFirst(e.sets.count) {
                e.sets.append(LiftSet(weight: s.weight, unit: s.unit, reps: s.reps))
            }
        }
    }

    /// Returns true when the set is now done.
    @discardableResult
    func toggle(_ exID: UUID, _ setID: UUID) -> Bool {
        var nowDone = false
        updateSet(exID, setID) { s in
            s.done.toggle()
            s.doneAt = s.done ? Date() : nil
            nowDone = s.done
        }
        recompute()
        if nowDone && data.settings.autoRest { startRest() }
        return nowDone
    }

    func deleteExercise(_ id: UUID) {
        day.exercises.removeAll { $0.id == id }
    }

    func removeExercise(_ id: UUID) {
        let name = exercise(id)?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let before = data
        deleteExercise(id)
        showToast("\(name.isEmpty ? "Exercise" : name) removed", undo: before)
    }

    func removeSet(_ exID: UUID, _ setID: UUID) {
        let before = data
        updateExercise(exID) { $0.sets.removeAll { $0.id == setID } }
        showToast("Set removed", undo: before)
    }

    /// Drops a set left with neither weight nor reps.
    func removeEmptySet(_ setID: UUID) {
        guard let exID = exerciseID(containing: setID),
              let s = exercise(exID)?.sets.first(where: { $0.id == setID }),
              s.weight == nil, s.reps == nil else { return }
        updateExercise(exID) { $0.sets.removeAll { $0.id == setID } }
    }

    func clearSamples() {
        for k in data.days.keys {
            guard var d = data.days[k] else { continue }
            d.exercises.removeAll(where: \.sample)
            if d.sampleTitle { d.title = ""; d.sampleTitle = false }
            data.days[k] = (d.exercises.isEmpty && d.title.isEmpty) ? nil : d
        }
    }

    func eraseAll() {
        let before = data
        stopRest()
        data = LogData()
        current = DayKey.today
        showToast("Log erased from this device", undo: before)
    }

    // MARK: toast and undo

    func showToast(_ message: String, undo snapshot: LogData?) {
        undoSnapshot = snapshot
        let t = Toast(message: message, undoable: snapshot != nil)
        toast = t
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.toast == t else { return }
            self.toast = nil
            self.undoSnapshot = nil
        }
    }

    func undo() {
        guard let snapshot = undoSnapshot else { return }
        data = snapshot
        undoSnapshot = nil
        toast = nil
    }

    // MARK: rest timer

    func startRest(_ seconds: Int? = nil) {
        timer.start(seconds: seconds ?? data.settings.rest, chime: data.settings.chime)
        data.timerEnd = timer.end
        data.timerDuration = timer.duration
    }

    func adjustRest(_ delta: Int) {
        timer.adjust(delta)
        data.timerEnd = timer.phase == .running ? timer.end : nil
        data.timerDuration = timer.duration
    }

    func stopRest() {
        timer.stop()
        data.timerEnd = nil
    }

    // MARK: sample pages (shown on first launch, removable from the header)

    static func sample() -> LogData {
        func sets(_ list: [(Double?, Int)], done: Int) -> [LiftSet] {
            list.enumerated().map { i, s in LiftSet(weight: s.0, unit: .kg, reps: s.1, done: i < done) }
        }
        let t = DayKey.today, p = DayKey.add(t, -3), q = DayKey.add(t, -7)
        var d = LogData()
        d.days[q] = Day(title: "Upper", exercises: [
            Exercise(name: "Bench Press", sets: sets([(80, 8), (90, 6), (92.5, 5)], done: 3), sample: true),
            Exercise(name: "Overhead Press", sets: sets([(50, 8), (50, 8), (52.5, 6)], done: 3), sample: true),
        ], sampleTitle: true)
        d.days[p] = Day(title: "Upper", exercises: [
            Exercise(name: "Bench Press", sets: sets([(80, 8), (90, 6), (95, 5)], done: 3), sample: true),
            Exercise(name: "Overhead Press", sets: sets([(50, 8), (52.5, 7), (52.5, 6)], done: 3), sample: true),
            Exercise(name: "Pull-up", sets: sets([(nil, 10), (nil, 8), (nil, 7)], done: 3), sample: true),
        ], sampleTitle: true)
        d.days[t] = Day(title: "Upper", exercises: [
            Exercise(name: "Bench Press", sets: sets([(80, 8), (97.5, 5), (100, 3)], done: 2), sample: true),
            Exercise(name: "Overhead Press", sets: [], sample: true),
        ], sampleTitle: true)
        return d
    }
}
