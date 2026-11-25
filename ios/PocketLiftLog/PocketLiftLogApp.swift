import CoreText
import SwiftUI

@main
struct PocketLiftLogApp: App {
    @State private var store = LogStore()

    init() {
        // JetBrains Mono and Newsreader ship inside the app (SIL Open Font License), so it looks right offline.
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(store)
        }
    }
}

struct RootView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var menuOpen = false

    private var tone: Tone {
        let s = store.data.settings
        return s.followDevice ? (systemScheme == .dark ? .night : .day) : s.tone
    }

    var body: some View {
        let palette = Palette.of(tone)
        let settings = store.data.settings
        ZStack(alignment: .trailing) {
            PaperTexture(paper: settings.paper, palette: palette).ignoresSafeArea()

            LogPage(openMenu: { withAnimation(.easeOut(duration: 0.26)) { menuOpen = true } })

            if menuOpen {
                Color.black.opacity(palette.night ? 0.5 : 0.16)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
                MenuPanel(close: closeMenu)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                ToastView(toast: t).padding(.bottom, 76).transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .environment(\.palette, palette)
        .environment(\.paper, settings.paper)
        .preferredColorScheme(settings.followDevice ? nil : (tone == .night ? .dark : .light))
        .tint(palette.ink)
        .onChange(of: store.data) { store.changed() }
        .onChange(of: scenePhase) { if scenePhase != .active { store.save() } }
    }

    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.26)) { menuOpen = false }
    }
}

struct ToastView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message).font(.mono(12))
            if toast.undoable {
                Button("Undo") { withAnimation { store.undo() } }
                    .font(.mono(12)).underline()
                    .frame(minHeight: 36)
            }
        }
        .foregroundStyle(pal.paper)
        .padding(.leading, 14).padding(.trailing, toast.undoable ? 10 : 14).padding(.vertical, 4)
        .background(pal.ink, in: RoundedRectangle(cornerRadius: 2))
        .padding(.horizontal, 20)
    }
}
