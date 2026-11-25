import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

/// The rest countdown. It runs off an end time, so it stays right while the app is in the background;
/// a local notification covers the case where the phone is locked when rest ends.
@MainActor
@Observable
final class RestTimer {
    enum Phase { case idle, running, done }

    var phase: Phase = .idle
    var end = Date()
    var duration = 90

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var chime = true
    @ObservationIgnored private var task: Task<Void, Never>?

    var remaining: Int { max(0, Int(ceil(end.timeIntervalSinceNow))) }

    func start(seconds: Int, chime: Bool) {
        self.chime = chime
        duration = seconds
        end = Date().addingTimeInterval(Double(seconds))
        phase = .running
        Notifier.requestPermissionOnce()
        arm()
    }

    func adjust(_ delta: Int) {
        if phase == .done {
            if delta > 0 { start(seconds: delta, chime: chime) }
            return
        }
        guard phase == .running else { return }
        end = end.addingTimeInterval(Double(delta))
        duration = max(1, duration + delta)
        arm()
    }

    func stop() {
        task?.cancel()
        Notifier.cancel()
        phase = .idle
    }

    /// Picks up a countdown that was running when the app was closed.
    func resume(end: Date?, duration: Int?) {
        guard let end, end > Date() else { return }
        self.end = end
        self.duration = duration ?? 90
        phase = .running
        arm()
    }

    private func arm() {
        task?.cancel()
        Notifier.schedule(at: end)
        let target = end
        task = Task { [weak self] in
            let wait = max(0, target.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.finish(late: Date().timeIntervalSince(target) > 3)
        }
    }

    private func finish(late: Bool) {
        phase = .done
        onFinish?()
        if !late {  // back from the background after the alarm: the notification already told them
            if chime { Chime.play() }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        Notifier.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, self.phase == .done else { return }
            self.phase = .idle
        }
    }
}

/// Local "rest over" notification, so the timer still alerts when the phone is locked.
enum Notifier {
    private static let id = "rest-timer"
    private static var asked = false

    static func requestPermissionOnce() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(at date: Date) {
        cancel()
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

/// Short sounds, synthesised so the app ships no audio files.
/// They play alongside the user's music and respect the silent switch.
enum Audio {
    static func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    static func wav(_ samples: [Int16], rate: Int = 44_100) -> Data {
        var d = Data()
        func text(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + samples.count * 2)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(samples.count * 2))
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}

/// A soft two-note chime for the end of rest.
enum Chime {
    private static var player: AVAudioPlayer?

    static func play() {
        Audio.prepare()
        if player == nil { player = try? AVAudioPlayer(data: Audio.wav(samples())) }
        player?.currentTime = 0
        player?.play()
    }

    private static func samples() -> [Int16] {
        let rate = 44_100.0, seconds = 1.6
        let count = Int(rate * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for (freq, start) in [(659.25, 0.0), (987.77, 0.16)] {
            for i in Int(start * rate)..<count {
                let t = Double(i) / rate - start
                let envelope = min(1, t / 0.02) * exp(-t * 3.2)
                let v = Int(sin(2 * .pi * freq * t) * envelope * 0.22 * 32_767)
                samples[i] = samples[i] &+ Int16(clamping: v)
            }
        }
        return samples
    }
}
