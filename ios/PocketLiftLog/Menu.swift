import SwiftUI

enum MenuPage: Hashable {
    case menu, settings, logout, info, privacy, terms

    var title: String {
        switch self {
        case .menu: return "Menu"
        case .settings: return "Settings"
        case .logout: return "Log out"
        case .info: return "App info"
        case .privacy: return "Privacy"
        case .terms: return "Terms"
        }
    }
}

/// The right-hand menu: Settings, Log out, App info.
struct MenuPanel: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @Environment(\.paper) private var paper
    let close: () -> Void
    @State private var stack: [MenuPage] = [.menu]
    @State private var eraseArmed = false

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        content
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(width: min(g.size.width * 0.88, 380))
                .background {
                    PaperTexture(paper: paper == .grain ? .grain : .plain, palette: pal).ignoresSafeArea()
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(pal.hair).frame(width: 1).ignoresSafeArea()
                }
            }
        }
    }

    private var page: MenuPage { stack.last ?? .menu }

    private var topBar: some View {
        HStack(spacing: 0) {
            if stack.count > 1 {
                Button { stack.removeLast(); eraseArmed = false } label: {
                    Text("<").font(.mono(15)).foregroundStyle(pal.slate).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text(page.title.uppercased()).font(.mono(12, medium: true)).tracking(1.9).foregroundStyle(pal.ink)
            Spacer()
            Button(action: close) {
                Text("×").font(.mono(20)).foregroundStyle(pal.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close menu")
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .menu:
            VStack(spacing: 0) {
                row(.settings, "Settings", "Name, paper, weight unit, rest timer")
                row(.logout, "Log out", "Account and data on this iPhone")
                row(.info, "App info", "Privacy policy, terms & conditions")
            }
        case .settings: SettingsPage()
        case .logout: logout
        case .info: info
        case .privacy: DocPage(sections: Legal.privacy)
        case .terms: DocPage(sections: Legal.terms)
        }
    }

    private func row(_ target: MenuPage, _ label: String, _ sub: String? = nil) -> some View {
        Button { stack.append(target) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.serif(20)).foregroundStyle(pal.ink)
                    if let sub { Text(sub).font(.mono(10.5)).foregroundStyle(pal.slate) }
                }
                Spacer()
                Text(">").font(.mono(13)).foregroundStyle(pal.slate)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private var logout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pocket Lift Log doesn't use accounts yet, so there's nothing to sign out of. Your log is kept only on this iPhone.")
            Text("To start fresh, or before you hand this phone to someone else, erase the log. This removes every workout, PR and setting stored here.")
            Button {
                if eraseArmed {
                    store.eraseAll()
                    eraseArmed = false
                    close()
                } else {
                    eraseArmed = true
                    Task { try? await Task.sleep(nanoseconds: 4_000_000_000); eraseArmed = false }
                }
            } label: {
                Text(eraseArmed ? "Tap again to erase everything" : "Erase this iPhone's log")
                    .font(.mono(12)).tracking(0.7)
                    .foregroundStyle(eraseArmed ? pal.paper : pal.ink)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(eraseArmed ? pal.ink : .clear, in: RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(pal.ink, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .font(.serif(15.5))
        .foregroundStyle(pal.ink)
        .padding(.top, 16)
    }

    private var info: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
        return VStack(alignment: .leading, spacing: 0) {
            Text("Pocket Lift Log").font(.serif(28, medium: true)).foregroundStyle(pal.ink).padding(.top, 16)
            Text("Version \(version)").font(.mono(11)).foregroundStyle(pal.slate).padding(.top, 2)
            Text("A bullet-journal workout log. Write the lift, tick the set, rest, repeat. Everything stays on your iPhone and works offline.")
                .font(.serif(15.5)).foregroundStyle(pal.ink).padding(.top, 10).padding(.bottom, 8)
            row(.privacy, "Privacy Policy")
            row(.terms, "Terms & Conditions")
        }
    }
}

// MARK: - Settings

struct SettingsPage: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @FocusState private var nameFocused: Bool

    var body: some View {
        let s = store.data.settings
        VStack(alignment: .leading, spacing: 0) {
            section("Your name", "Shown at the top of your log.") {
                TextField("", text: ownerBinding, prompt: Text("e.g. Sam").font(.serif(18, italic: true)).foregroundStyle(pal.slate.opacity(0.55)))
                    .font(.serif(18)).foregroundStyle(pal.ink)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .submitLabel(.done).focused($nameFocused)
                    .frame(height: 44)
                    .overlay(alignment: .bottom) { Rectangle().fill(nameFocused ? pal.ink : pal.hair).frame(height: 1) }
            }
            section("Paper", "Night papers use light ink.") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([Tone.day, Tone.night], id: \.self) { tone in
                        Text(tone == .day ? "DAY" : "NIGHT").font(.mono(10)).tracking(1.4).foregroundStyle(pal.slate).padding(.top, 6)
                        HStack(spacing: 10) {
                            ForEach(Paper.allCases) { paper in
                                Swatch(paper: paper, tone: tone,
                                       selected: s.paper == paper && (s.followDevice || s.tone == tone)) {
                                    store.data.settings.paper = paper
                                    store.data.settings.tone = tone
                                    store.data.settings.followDevice = false
                                }
                            }
                        }
                    }
                }
            }
            section("Follow device", "Use the night version of your paper when your iPhone is in dark mode.") {
                Choice(options: [(true, "ON"), (false, "OFF")], selection: s.followDevice) { store.data.settings.followDevice = $0 }
            }
            section("Weight unit", "Default for new entries. Switching converts every weight on screen.") {
                Choice(options: [(WeightUnit.kg, "KG"), (.lb, "LB")], selection: s.unit) { store.data.settings.unit = $0 }
            }
            section("Rest timer", "Default countdown after each completed set.") {
                Choice(options: [45, 60, 90, 120, 150, 180].map { ($0, String(format: "%d:%02d", $0 / 60, $0 % 60)) },
                       selection: s.rest) { store.data.settings.rest = $0 }
            }
            section("Start rest automatically", "Begin the countdown when you tick a set.") {
                Choice(options: [(true, "ON"), (false, "OFF")], selection: s.autoRest) { store.data.settings.autoRest = $0 }
            }
            section("Chime", "Play a soft chime when rest is over. Follows the silent switch.") {
                Choice(options: [(true, "ON"), (false, "OFF")], selection: s.chime) { store.data.settings.chime = $0 }
            }
        }
    }

    private var ownerBinding: Binding<String> {
        Binding(get: { store.data.settings.owner }, set: { store.data.settings.owner = String($0.prefix(24)) })
    }

    private func section<C: View>(_ title: String, _ note: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.mono(11, medium: true)).tracking(1.5).foregroundStyle(pal.ink)
            Text(note).font(.serif(15)).foregroundStyle(pal.slate).fixedSize(horizontal: false, vertical: true)
            control().padding(.top, 4)
        }
        .padding(.top, 16).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
    }
}

/// A paper tile: its real colour, texture and ink.
struct Swatch: View {
    let paper: Paper
    let tone: Tone
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        let p = Palette.of(tone)
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    PaperTexture(paper: paper, palette: p, dotSpacing: 10, ruleSpacing: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aa").font(.serif(19, medium: true)).foregroundStyle(p.ink)
                        Text("100×8").font(.mono(9.5)).foregroundStyle(p.slate)
                    }
                    .padding(7)
                }
                .aspectRatio(1 / 1.15, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.hair, lineWidth: 1))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? pal.ink : .clear, lineWidth: 1.5))
                Text(paper.title).font(.mono(10.5, medium: selected)).foregroundStyle(selected ? pal.ink : pal.slate)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(paper.title), \(tone.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Policy pages

struct DocPage: View {
    let sections: [(String, String)]
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Last updated 25 November 2026").font(.mono(11)).foregroundStyle(pal.slate).padding(.top, 16)
            ForEach(sections.indices, id: \.self) { i in
                Text(sections[i].0.uppercased()).font(.mono(11, medium: true)).tracking(1.5).foregroundStyle(pal.ink).padding(.top, 20)
                Text(sections[i].1).font(.serif(15.5)).foregroundStyle(pal.ink).lineSpacing(3).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum Legal {
    static let privacy: [(String, String)] = [
        ("What we collect", "Nothing is sent to us. The workouts, personal records and settings you enter are saved in the app's storage on this iPhone. We have no server that receives them."),
        ("No tracking", "The app has no accounts, analytics, advertising or tracking. It doesn't use the network: its typefaces are built in."),
        ("Notifications", "If you allow notifications, the app schedules a local \"Rest over\" alert on this iPhone when a rest timer runs. Nothing leaves the device."),
        ("Backups", "Like other app data, your log can be included in your iPhone's own iCloud or computer backups, under Apple's terms."),
        ("Your control", "You can erase everything from Menu › Log out, or by deleting the app. Deleting the app removes the log from this iPhone."),
        ("Children", "The app isn't directed at children under 13."),
        ("Changes", "If this policy changes, the new version will appear here with a new date."),
    ]

    static let terms: [(String, String)] = [
        ("Using the app", "Pocket Lift Log is a free tool for keeping your own training records. By using it you agree to these terms."),
        ("Not medical advice", "The app records the numbers you enter. It doesn't give medical, health or training advice. Talk to a qualified professional before starting a new program, and lift within your limits. You're responsible for how you train."),
        ("Your data", "Your log is stored only on your iPhone. You're responsible for keeping it; we can't recover data that's been erased or lost."),
        ("No warranty", "The app is provided \"as is\", without warranties of any kind. To the extent the law allows, we aren't liable for injury, lost data or any other loss arising from its use."),
        ("Changes", "We may update these terms. The current version will always be shown here with its date."),
    ]
}
