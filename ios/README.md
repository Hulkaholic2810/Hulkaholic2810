# Pocket Lift Log for iPhone (SwiftUI)

A native SwiftUI version of the log, designed for iPhone 17 Pro (402 × 874 pt, Dynamic Island) and any iPhone on iOS 17 or later.

## Run it on your iPhone

1. On a Mac with Xcode 16 or newer (Xcode 26 for iOS 26 on iPhone 17 Pro), open `ios/PocketLiftLog.xcodeproj`.
2. Select the **PocketLiftLog** target → **Signing & Capabilities** → choose your Team (a free Apple ID works for testing).
   If Xcode says the bundle identifier is taken, change `app.pocketlog.ios` to something unique.
3. Plug in your iPhone (enable Developer Mode when iOS asks), pick it as the run destination, press **Run**.
   Or pick the **iPhone 17 Pro** simulator.

## What's in it

- `Model.swift` – the log, kg/lb conversion (rounded to 0.5), PRs judged in the order sets were ticked, JSON saved in Application Support.
- `LogPage.swift` – header (name line, `< NOV 25 // WED >`, session title), exercises, set rows with the ink check box, PR notes, rest bar.
- `RestTimer.swift` – the countdown, a synthesised chime, and a local "Rest over" notification for when the phone is locked.
- `Menu.swift` – Settings (name, paper swatches, follow device, unit, rest time, auto-start, chime), Log out (erase), App info, privacy policy and terms.
- `Theme.swift` – day and night palettes, grain / dots / ruled / plain paper, bundled JetBrains Mono and Newsreader.

The iPhone app keeps its own log; it doesn't share data with the web or Android versions.

## Sign in with Apple

The first screen offers **Sign in with Apple** or **Continue without an account**. Signing in fills in your name for the
top line; the log still stays on the iPhone (there is no server). To make the Apple button work you need a paid Apple
Developer account: in Xcode, target → **Signing & Capabilities** → **+ Capability** → **Sign in with Apple**.
With a free Apple ID the button shows a short note instead, and "Continue without an account" works as normal.
