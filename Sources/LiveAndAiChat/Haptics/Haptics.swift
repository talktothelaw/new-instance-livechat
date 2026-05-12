#if canImport(UIKit)
import UIKit

/// Centralised haptic feedback helpers. Each method is a no-op on
/// devices without a haptic engine (older iPads, Mac Catalyst), so
/// callers don't need to guard.
///
/// Patterns chosen to match what feels natural in modern chat apps:
///   - send  → light impact (single thump)
///   - inbound message → soft selection click (subtle, ambient)
///   - failed send → error notification (longer tritone-style buzz)
///   - tap-to-retry → light impact echo (mirrors the original send)
///
/// All generators are constructed lazily, prepared on first use to
/// minimise the latency between the call and the actual haptic.
enum Haptics {

    /// Customer-facing send. Light impact — one quick thump as the
    /// bubble flies upward.
    static func send() {
        Self.lightImpact.prepare()
        Self.lightImpact.impactOccurred(intensity: 0.7)
    }

    /// Inbound message from agent / AI. Soft selection click so it
    /// doesn't compete with the notification chirp. Suppressed
    /// automatically if the user has their phone on silent — we don't
    /// override that.
    static func inbound() {
        Self.selection.prepare()
        Self.selection.selectionChanged()
    }

    /// Send / upload failure. Standard system "error" haptic — same
    /// vocabulary as Mail, Messages, etc.
    static func failure() {
        Self.notification.prepare()
        Self.notification.notificationOccurred(.error)
    }

    /// Confirmation pulses for non-failure flows (handoff requested,
    /// retry queued, attachment uploaded). Light impact at 0.5
    /// intensity — present but not pushy.
    static func confirm() {
        Self.lightImpact.prepare()
        Self.lightImpact.impactOccurred(intensity: 0.5)
    }

    // MARK: - Generators (lazy, retained for fast re-fire)
    //
    // UIKit's recommendation is to retain a generator and prepare it
    // before use so the Taptic Engine spins up ahead of the actual
    // fire. Recreating per-call adds 50–80ms of "prepared" latency.

    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()
}
#endif
