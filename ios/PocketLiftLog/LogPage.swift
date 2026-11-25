import SwiftUI

enum Field: Hashable {
    case title, name(UUID), weight(UUID), reps(UUID)

    var rowID: UUID? {
        switch self {
        case .title: return nil
        case .name(let id), .weight(let id), .reps(let id): return id
        }
    }
}

// MARK: - The page

struct LogPage: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @Environment(\.paper) private var paper
    @FocusState private var focus: Field?
    @State private var turn: CGFloat = 1
    let openMenu: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Rectangle().fill(pal.hair).frame(height: 1).padding(.horizontal, -20)
                        ForEach(store.day.exercises) { ex in
                            ExerciseBlock(exID: ex.id, focus: $focus).id(ex.id)
                        }
                        addExercise
                        footer
                    }
                    .padding(.horizontal, 20)
                    .id(store.current)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 14 * turn)), removal: .opacity))
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { old, new in
                    focusLeft(old, now: new)
                    if let id = new?.rowID { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .background { PaperTexture(paper: paper, palette: pal).ignoresSafeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { RestBar() }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if let next = nextField { Button("Next") { focus = next } }
                    Button("Done") { focus = nil }.fontWeight(.semibold)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 40).onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    if abs(dx) > 80, abs(dx) > abs(dy) * 2 { flip(dx < 0 ? 1 : -1) }
                }
            )
        }
        .scrollContentBackground(.hidden)
    }

    private var nextField: Field? {
        if case .weight(let id)? = focus { return .reps(id) }
        return nil
    }

    // MARK: header

    private var header: some View {
        let label = store.dateLabel
        return VStack(alignment: .leading, spacing: 4) {
            Text(store.brand)
                .font(.mono(10.5)).tracking(2.4).textCase(.uppercase)
                .foregroundStyle(pal.slate).lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            HStack(spacing: 0) {
                Color.clear.frame(width: 44, height: 44)
                Spacer(minLength: 0)
                Button { flip(-1) } label: { arrow("<") }.accessibilityLabel("Previous day")
                (Text("\(label.date) ") + Text("//").foregroundColor(pal.slate) + Text(" \(label.weekday)"))
                    .font(.mono(14, medium: true)).tracking(1.7).foregroundStyle(pal.ink)
                    .lineLimit(1).fixedSize()
                Button { flip(1) } label: { arrow(">") }.accessibilityLabel("Next day")
                Spacer(minLength: 0)
                Button(action: { focus = nil; openMenu() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(pal.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open menu")
            }
            .padding(.horizontal, -12)

            TextField("", text: titleBinding, prompt: Text("Untitled session").font(.serif(32, italic: true)).foregroundStyle(pal.slate.opacity(0.55)))
                .font(.serif(32, medium: true))
                .foregroundStyle(pal.ink)
                .focused($focus, equals: .title)
                .submitLabel(.done)
                .padding(.top, 6).padding(.bottom, 4)
                .ruledLine(paper == .ruled, pal.hair)

            HStack(spacing: 14) {
                Text(store.summary).font(.mono(11.5)).foregroundStyle(pal.slate).monospacedDigit()
                if !store.isToday {
                    Button("back to today") { jump(to: DayKey.today) }
                        .font(.mono(11)).foregroundStyle(pal.ink).underline(color: pal.hair)
                }
            }
            .frame(minHeight: 28)

            if store.hasSamples {
                HStack(spacing: 10) {
                    Text("Sample entries shown.").foregroundStyle(pal.slate)
                    Button("Clear samples") { withAnimation { store.clearSamples() } }.underline().foregroundStyle(pal.ink)
                }
                .font(.mono(11)).frame(minHeight: 32)
            }
        }
        .padding(.bottom, 12)
    }

    private func arrow(_ s: String) -> some View {
        Text(s).font(.mono(14)).foregroundStyle(pal.slate).frame(width: 32, height: 44).contentShape(Rectangle())
    }

    private var titleBinding: Binding<String> {
        Binding(get: { store.day.title }, set: { v in
            var d = store.day
            d.title = String(v.prefix(60))
            d.sampleTitle = false
            store.day = d
        })
    }

    // MARK: footer

    private var addExercise: some View {
        Button {
            let id = store.addExercise()
            DispatchQueue.main.async { focus = .name(id) }
        } label: {
            HStack(spacing: 10) {
                Text("+").font(.mono(17))
                Text("Add Exercise").font(.serif(19))
            }
            .foregroundStyle(pal.slate)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
            .ruledLine(paper == .ruled, pal.hair)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tap the ✓ box when you finish a set. Units, paper and rest time are in the menu.")
            Text("Everything saves on this iPhone and works offline.")
        }
        .font(.mono(10.5)).foregroundStyle(pal.slate)
        .padding(.top, 14).padding(.bottom, 28)
    }

    // MARK: behaviour

    private func flip(_ dir: Int) {
        jump(to: DayKey.add(store.current, dir))
    }

    private func jump(to key: String) {
        guard key != store.current else { return }
        focus = nil
        turn = key > store.current ? 1 : -1
        withAnimation(.easeOut(duration: 0.22)) { store.current = key }
    }

    /// Tidy up when a field loses focus: drop an unnamed empty exercise or a set left with no numbers.
    private func focusLeft(_ old: Field?, now new: Field?) {
        switch old {
        case .name(let id)?:
            guard let ex = store.exercise(id) else { return }
            let trimmed = ex.name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && ex.sets.isEmpty {
                withAnimation { store.deleteExercise(id) }
            } else if trimmed != ex.name {
                store.updateExercise(id) { $0.name = trimmed }
            }
        case .weight(let sid)?, .reps(let sid)?:
            if new == .weight(sid) || new == .reps(sid) { return }
            withAnimation { store.removeEmptySet(sid) }
        case .title?:
            let t = store.day.title.trimmingCharacters(in: .whitespaces)
            if t != store.day.title { store.day.title = t }
        case nil:
            break
        }
    }
}

// MARK: - One exercise

struct ExerciseBlock: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @Environment(\.paper) private var paper
    let exID: UUID
    var focus: FocusState<Field?>.Binding

    var body: some View {
        if let ex = store.exercise(exID) {
            VStack(alignment: .leading, spacing: 0) {
                nameRow(ex)
                suggestions(ex)
                history(ex)
                ForEach(Array(ex.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(exID: exID, set: set, index: index, focus: focus)
                    if let note = store.prNote(set) {
                        Text(note)
                            .font(.serif(15.5, italic: true))
                            .foregroundStyle(pal.ink)
                            .padding(.leading, 26)
                            .frame(height: 26)
                            .padding(.top, -6)
                            .transition(.opacity.combined(with: .offset(x: -10)))
                    }
                }
                Button {
                    if let sid = store.addSet(to: exID) { DispatchQueue.main.async { focus.wrappedValue = .weight(sid) } }
                } label: {
                    HStack(spacing: 0) {
                        Text("+").font(.mono(15)).frame(width: 26, alignment: .leading)
                        Text("add set").font(.mono(11.5)).tracking(0.9)
                    }
                    .foregroundStyle(pal.slate)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add set to \(ex.name.isEmpty ? "exercise" : ex.name)")
            }
            .padding(.top, 10).padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { store.exercise(exID)?.name ?? "" }, set: { v in
            store.updateExercise(exID) { ex in
                ex.name = String(v.prefix(60))
                if !v.isEmpty { ex.sample = false }
            }
        })
    }

    private func nameRow(_ ex: Exercise) -> some View {
        let editing = focus.wrappedValue == .name(exID)
        return HStack(spacing: 8) {
            TextField("", text: nameBinding, prompt: Text("Exercise name").font(.serif(21, italic: true)).foregroundStyle(pal.slate.opacity(0.55)))
                .font(.serif(21, medium: true))
                .foregroundStyle(pal.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused(focus, equals: .name(exID))
                .onSubmit {
                    guard !ex.name.trimmingCharacters(in: .whitespaces).isEmpty, let sid = store.addSet(to: exID) else {
                        focus.wrappedValue = nil
                        return
                    }
                    DispatchQueue.main.async { focus.wrappedValue = .weight(sid) }
                }
            if editing {
                Button("REMOVE") { withAnimation { store.removeExercise(exID) } }
                    .font(.mono(10.5)).tracking(1.2).foregroundStyle(pal.ink)
                    .frame(minHeight: 40)
            } else if ex.sample {
                Text("SAMPLE").font(.mono(10.5)).tracking(1.2).foregroundStyle(pal.slate)
            }
        }
        .frame(height: 40)
        .ruledLine(paper == .ruled, pal.hair)
    }

    /// Names you've used before, while typing a new one.
    @ViewBuilder
    private func suggestions(_ ex: Exercise) -> some View {
        let typed = LogStore.norm(ex.name)
        if focus.wrappedValue == .name(exID), !typed.isEmpty {
            let matches = store.allNames.filter { LogStore.norm($0).contains(typed) && LogStore.norm($0) != typed }.prefix(3)
            if !matches.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(matches), id: \.self) { name in
                        Button(name) { store.updateExercise(exID) { $0.name = name } }
                            .font(.mono(12)).foregroundStyle(pal.ink).underline(color: pal.hair)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 32)
            }
        }
    }

    @ViewBuilder
    private func history(_ ex: Exercise) -> some View {
        let last = store.last(for: ex.name)
        let pr = store.best(for: ex.name)
        if last != nil || pr != nil {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let last {
                    Text("Last: " + last.sets.map { store.setText($0) }.joined(separator: ", "))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pr {
                    Text("PR \(LogStore.num(store.shown(pr.weight, pr.unit))) \(store.unit.rawValue)").fixedSize()
                }
                Spacer(minLength: 0)
                let logged = ex.sets.filter { $0.reps != nil }.count
                if let last, last.sets.count > logged {
                    Button(logged > 0 ? "copy rest" : "copy last") { withAnimation { store.copyLast(exID) } }
                        .font(.mono(11)).underline(color: pal.hair)
                        .frame(minHeight: 32)
                        .fixedSize()
                }
            }
            .font(.mono(12))
            .foregroundStyle(pal.slate)
            .monospacedDigit()
            .padding(.top, -4).padding(.bottom, 4)
        }
    }
}

// MARK: - One set: n   [ weight ] × [ reps ]        [✓]

struct SetRow: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @Environment(\.paper) private var paper
    let exID: UUID
    let set: LiftSet
    let index: Int
    var focus: FocusState<Field?>.Binding
    @State private var weightText = ""
    @State private var repsText = ""

    private var editing: Bool {
        focus.wrappedValue == .weight(set.id) || focus.wrappedValue == .reps(set.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.mono(11.5)).foregroundStyle(pal.slate)
                .frame(width: 26, alignment: .leading)

            numberField($weightText, prompt: store.unit.rawValue, width: 64, field: .weight(set.id), trailing: true)
                .keyboardType(.decimalPad)
                .accessibilityLabel("Set \(index + 1) weight in \(store.unit.rawValue), blank for bodyweight")
            Text("×").font(.mono(13)).foregroundStyle(pal.slate).padding(.horizontal, 8)
            numberField($repsText, prompt: "reps", width: 42, field: .reps(set.id), trailing: false)
                .keyboardType(.numberPad)
                .accessibilityLabel("Set \(index + 1) reps")

            Spacer(minLength: 8)

            if editing {
                Button { withAnimation { store.removeSet(exID, set.id) } } label: {
                    Text("×").font(.mono(16)).foregroundStyle(pal.slate).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Delete set \(index + 1)")
            }
            CheckBox(on: set.done) { tapCheck() }
                .accessibilityLabel("Set \(index + 1) done")
        }
        .frame(height: 40)
        .ruledLine(paper == .ruled, pal.hair)
        .onAppear(perform: syncText)
        .onChange(of: store.unit) { syncText() }
        .onChange(of: set) { if !editing { syncText() } }
        .onChange(of: weightText) { writeWeight() }
        .onChange(of: repsText) { writeReps() }
    }

    private func numberField(_ text: Binding<String>, prompt: String, width: CGFloat, field: Field, trailing: Bool) -> some View {
        let focused = focus.wrappedValue == field
        return TextField("", text: text, prompt: Text(prompt).font(.mono(12)).foregroundStyle(pal.slate.opacity(0.55)))
            .font(.mono(17))
            .monospacedDigit()
            .foregroundStyle(pal.ink)
            .multilineTextAlignment(trailing ? .trailing : .leading)
            .frame(width: width, height: 30)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? pal.ink : (text.wrappedValue.isEmpty ? pal.hair : .clear))
                    .frame(height: 1)
            }
            .focused(focus, equals: field)
    }

    private func syncText() {
        weightText = set.weight.map { LogStore.num(store.shown($0, set.unit)) } ?? ""
        repsText = set.reps.map(String.init) ?? ""
    }

    private func writeWeight() {
        let v = weightText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let shownNow = set.weight.map { store.shown($0, set.unit) }
        if v.isEmpty {
            if set.weight != nil { store.updateSet(exID, set.id) { $0.weight = nil; $0.unit = store.unit } }
            return
        }
        guard let w = Double(v), w >= 0, w < 10_000, w != shownNow else { return }
        let u = store.unit
        store.updateSet(exID, set.id) { $0.weight = w; $0.unit = u }
    }

    private func writeReps() {
        let r = Int(repsText.trimmingCharacters(in: .whitespaces))
        let valid = (r ?? 0) > 0 && (r ?? 0) < 1000 ? r : nil
        guard valid != set.reps else { return }
        store.updateSet(exID, set.id) { s in
            s.reps = valid
            if valid == nil { s.done = false; s.doneAt = nil }  // a set needs reps to count as done
        }
    }

    private func tapCheck() {
        if set.reps == nil && !set.done {
            focus.wrappedValue = .reps(set.id)
            return
        }
        focus.wrappedValue = nil
        withAnimation(.easeOut(duration: 0.5)) { _ = store.toggle(exID, set.id) }
    }
}

// MARK: - The check box: fills with ink when ticked

struct CheckBox: View {
    let on: Bool
    let action: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).stroke(on ? pal.ink : pal.slate, lineWidth: 1.2)
                RoundedRectangle(cornerRadius: 3).fill(pal.ink).scaleEffect(on ? 1 : 0.01).opacity(on ? 1 : 0)
                CheckMark()
                    .stroke(on ? pal.paper : pal.slate.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 22, height: 22)
            .frame(width: 48, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: on)
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.29, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.65))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.35))
        return p
    }
}

// MARK: - Rest bar: slim when idle, a countdown with ±15s and × while resting

struct RestBar: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @Environment(\.paper) private var paper
    @State private var pulse = false

    private func mmss(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }

    var body: some View {
        let t = store.timer
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle().fill(pal.hair).frame(height: 1)
                if t.phase == .running {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        GeometryReader { g in
                            Rectangle().fill(pal.ink)
                                .frame(width: g.size.width * CGFloat(t.remaining) / CGFloat(max(1, t.duration)), height: 1)
                        }
                    }
                    .frame(height: 1)
                }
            }
            HStack(spacing: 4) {
                switch t.phase {
                case .idle:
                    Text("Saved offline").font(.mono(10.5)).foregroundStyle(pal.slate)
                    Spacer()
                    Button { store.startRest() } label: {
                        Text("REST \(mmss(store.data.settings.rest)) ▸").font(.mono(11)).tracking(1.1)
                            .foregroundStyle(pal.slate).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Start rest timer")
                case .running, .done:
                    Group {
                        Text(t.phase == .done ? "GO" : "REST").font(.mono(10.5)).tracking(1.5).foregroundStyle(pal.slate)
                            .frame(width: 52, alignment: .leading)
                        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                            Text(mmss(t.remaining)).font(.mono(24, medium: true)).monospacedDigit().foregroundStyle(pal.ink)
                        }
                    }
                    .opacity(t.phase == .done && pulse ? 0.3 : 1)
                    Spacer()
                    Button("-15s") { store.adjustRest(-15) }.font(.mono(13)).foregroundStyle(pal.slate).frame(minWidth: 44, minHeight: 44)
                    Button("+15s") { store.adjustRest(15) }.font(.mono(13)).foregroundStyle(pal.slate).frame(minWidth: 44, minHeight: 44)
                    Button { withAnimation { store.stopRest() } } label: {
                        Text("×").font(.mono(18)).foregroundStyle(pal.ink).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Dismiss rest timer")
                }
            }
            .frame(height: t.phase == .idle ? 44 : 58)
            .padding(.horizontal, 20)
        }
        .background {
            PaperTexture(paper: paper == .grain ? .grain : .plain, palette: pal).ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeOut(duration: 0.2), value: t.phase)
        .onChange(of: t.phase) {
            pulse = false
            if t.phase == .done {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}
