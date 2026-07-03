import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if os(iOS)
import AVFoundation
import AudioToolbox
import UIKit
#endif

/// Schedules the "3, 2, 1, horn" rest-end cue as local notifications so it
/// still fires on the Lock Screen or with the app in the background. This is
/// the documented fallback path (fallbackMode = notificationSoundAndHaptics):
/// iOS does not let a backgrounded app play arbitrary countdown audio, while
/// notification sound + vibration is always available.
public enum RestCueScheduler {
    public static let cueIdentifiers = [
        "nextset.restcue.3",
        "nextset.restcue.2",
        "nextset.restcue.1",
        "nextset.restcue.horn"
    ]

    /// UNUserNotificationCenter traps in processes without a bundle identifier
    /// (e.g. the SwiftPM shell executable), so notification work is skipped there.
    private static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public static func requestAuthorization() {
        #if canImport(UserNotifications)
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
    }

    /// Schedules the countdown at resumeAt-3s/-2s/-1s and the horn at resumeAt.
    /// Steps already in the past are skipped; re-scheduling with the same
    /// resumeAt is idempotent because the identifiers are fixed.
    public static func scheduleRestEndCue(resumeAt: Date, upcomingExercise: String?, now: Date = Date()) {
        #if canImport(UserNotifications)
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: cueIdentifiers)

        let steps: [(id: String, title: String, offset: TimeInterval)] = [
            (cueIdentifiers[0], "3", -3),
            (cueIdentifiers[1], "2", -2),
            (cueIdentifiers[2], "1", -1),
            (cueIdentifiers[3], "Next set — go!", 0)
        ]
        for step in steps {
            let interval = resumeAt.addingTimeInterval(step.offset).timeIntervalSince(now)
            guard interval > 0.5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = step.title
            if step.offset == 0, let upcomingExercise {
                content.body = upcomingExercise
            }
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: step.id, content: content, trigger: trigger))
        }
        #endif
    }

    public static func cancelPendingCues() {
        #if canImport(UserNotifications)
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: cueIdentifiers)
        #endif
    }
}

/// Plays the ideal in-app rest-end cue while the app is foregrounded: spoken
/// "3, 2, 1" over ducked music, then a horn system sound with haptics. Music
/// keeps playing (ducked) via AVAudioSession .playback + .duckOthers and is
/// restored with notifyOthersOnDeactivation. Off-iOS this is a no-op shell so
/// callers compile everywhere.
public final class InAppRestCuePlayer {
    #if os(iOS)
    private let synthesizer = AVSpeechSynthesizer()
    #endif
    private var lastAnnouncedSecond: Int?

    public init() {}

    /// Feed once per second while resting; announces at 3/2/1 and horns at 0.
    public func handleRestTick(remainingSeconds: Int) {
        guard remainingSeconds <= 3, remainingSeconds != lastAnnouncedSecond else { return }
        lastAnnouncedSecond = remainingSeconds
        #if os(iOS)
        switch remainingSeconds {
        case 1...3:
            duckAudioSession()
            speak("\(remainingSeconds)")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case 0:
            AudioServicesPlaySystemSound(1005)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            restoreAudioSessionSoon()
        default:
            break
        }
        #endif
    }

    /// Call when a new rest begins or the workout moves on, so the next
    /// countdown announces again.
    public func reset() {
        lastAnnouncedSecond = nil
    }

    #if os(iOS)
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func duckAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func restoreAudioSessionSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
    #endif
}
