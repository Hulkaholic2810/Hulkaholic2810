import AuthenticationServices
import SwiftUI

/// The logo: a pocket notebook with an elastic band and a ticked box on the cover.
/// Drawn on a 120 × 120 grid, matching brand/logo-mark-*.svg.
struct LogoMark: View {
    let ink: Color
    let paper: Color

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 120
            let dx = (size.width - 120 * s) / 2, dy = (size.height - 120 * s) / 2
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: dx + x * s, y: dy + y * s, width: w * s, height: h * s)
            }
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * s, y: dy + y * s) }

            ctx.fill(Path(roundedRect: r(24, 10, 72, 100), cornerRadius: 9 * s), with: .color(ink))
            ctx.fill(Path(r(80, 10, 5, 100)), with: .color(paper.opacity(0.92)))
            ctx.stroke(Path(roundedRect: r(36, 44, 30, 30), cornerRadius: 4 * s), with: .color(paper), lineWidth: 3 * s)
            var tick = Path()
            tick.move(to: pt(42.5, 59.5))
            tick.addLine(to: pt(49.5, 66))
            tick.addLine(to: pt(61, 51.5))
            ctx.stroke(tick, with: .color(paper), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// First screen: Sign in with Apple, or carry on without an account. Either way the log lives on this iPhone.
struct SignInView: View {
    @Environment(LogStore.self) private var store
    @Environment(\.palette) private var pal
    @State private var message: String?
    @State private var doc: MenuPage?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LogoMark(ink: pal.ink, paper: pal.paper).frame(width: 112, height: 112)
            Text("Pocket Lift Log")
                .font(.serif(34, medium: true)).foregroundStyle(pal.ink)
                .padding(.top, 18)
            Text("THE QUIET LOGBOOK FOR LOUD LIFTS.")
                .font(.mono(10.5)).tracking(2.3).foregroundStyle(pal.slate)
                .padding(.top, 10)
            Spacer()
            Spacer()

            VStack(spacing: 14) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(pal.night ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // re-create the button when the paper changes so its style follows day/night
                .id(pal.night)

                if let message {
                    Text(message)
                        .font(.serif(14.5, italic: true)).foregroundStyle(pal.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Continue without an account") { withAnimation(.easeOut(duration: 0.3)) { store.continueAsGuest() } }
                    .font(.mono(12.5)).foregroundStyle(pal.ink).underline(color: pal.hair)
                    .frame(minHeight: 44)

                VStack(spacing: 4) {
                    Text("Your log stays on this iPhone either way.")
                        .font(.serif(14, italic: true)).foregroundStyle(pal.slate)
                    HStack(spacing: 8) {
                        Button("Privacy") { doc = .privacy }.underline(color: pal.hair)
                        Text("·")
                        Button("Terms") { doc = .terms }.underline(color: pal.hair)
                    }
                    .font(.mono(11)).foregroundStyle(pal.slate)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PaperTexture(paper: store.data.settings.paper, palette: pal).ignoresSafeArea() }
        .sheet(item: $doc) { page in
            NavigationStack {
                ScrollView {
                    DocPage(sections: page == .privacy ? Legal.privacy : Legal.terms)
                        .padding(.horizontal, 20).padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(pal.paper)
                .navigationTitle(page == .privacy ? "Privacy Policy" : "Terms & Conditions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { doc = nil } } }
            }
            .environment(\.palette, pal)
            .tint(pal.ink)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let parts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.filter { !$0.isEmpty }
            withAnimation(.easeOut(duration: 0.3)) {
                store.signIn(appleUserID: credential.user,
                             name: parts.joined(separator: " "),
                             givenName: credential.fullName?.givenName ?? "",
                             email: credential.email)
            }
        case .failure(let error):
            if let e = error as? ASAuthorizationError, e.code == .canceled { return }
            message = "Sign in with Apple isn't switched on for this build yet. You can continue without an account; the log works the same."
        }
    }
}

extension MenuPage: Identifiable {
    var id: Self { self }
}
