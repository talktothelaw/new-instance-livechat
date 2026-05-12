import SwiftUI

/// Concrete colour palette consumed by the SDK SwiftUI views. Each field
/// maps to a named appearance token from ``OrgAppearance``; defaults are
/// the spec defaults so the UI looks right before the merchant config
/// resolves.
public struct ChatColors: Equatable {
    public var primary: Color
    public var background: Color
    public var text: Color
    public var textSecondary: Color
    public var border: Color
    public var inputBg: Color
    public var inputBorder: Color
    public var inputText: Color
    public var inputPlaceholder: Color

    // Header
    public var headerBackground: Color
    public var headerPrimaryText: Color
    public var headerSecondaryText: Color
    public var headerIcon: Color
    public var closeButton: Color

    // Bubbles
    public var sentBubble: Color
    public var sentText: Color
    public var sentTimestamp: Color
    public var receivedBubble: Color
    public var receivedText: Color
    public var receivedTimestamp: Color
    public var systemMessageText: Color

    // Day separator + footer
    public var daySeparatorBg: Color
    public var daySeparatorText: Color
    public var footerContainer: Color

    // Buttons / status / badges
    public var sendButtonBg: Color
    public var sendButtonIcon: Color
    public var attachmentButton: Color
    public var typingBg: Color
    public var typingDot: Color
    public var unreadBadgeBg: Color
    public var unreadBadgeText: Color
    public var scrollToBottomBg: Color
    public var scrollToBottomIcon: Color
    public var onlineStatus: Color
    public var offlineStatus: Color
    public var errorColor: Color
    public var successColor: Color
    public var warningColor: Color

    /// Spec-default light palette — matches the JSON in the user-facing
    /// spec and the gql-server `appearanceDefaults.ts`.
    public static let lightDefault: ChatColors = ChatColors(
        primary: hex("#9333EA"),
        background: hex("#F7F7FB"),
        text: hex("#111827"),
        textSecondary: hex("#6B7280"),
        border: hex("#E5E7EB"),
        inputBg: hex("#F9FAFB"),
        inputBorder: hex("#E5E7EB"),
        inputText: hex("#111827"),
        inputPlaceholder: hex("#9CA3AF"),
        headerBackground: hex("#9333EA"),
        headerPrimaryText: .white,
        headerSecondaryText: hex("#E9D5FF"),
        headerIcon: .white,
        closeButton: .white,
        sentBubble: hex("#9333EA"),
        sentText: .white,
        sentTimestamp: hex("#E9D5FF"),
        receivedBubble: .white,
        receivedText: hex("#111827"),
        receivedTimestamp: hex("#6B7280"),
        systemMessageText: hex("#6B7280"),
        daySeparatorBg: hex("#EDE9FE"),
        daySeparatorText: hex("#6D28D9"),
        footerContainer: .white,
        sendButtonBg: hex("#9333EA"),
        sendButtonIcon: .white,
        attachmentButton: hex("#6B7280"),
        typingBg: hex("#F3F4F6"),
        typingDot: hex("#9CA3AF"),
        unreadBadgeBg: hex("#9333EA"),
        unreadBadgeText: .white,
        scrollToBottomBg: hex("#9333EA"),
        scrollToBottomIcon: .white,
        onlineStatus: hex("#22C55E"),
        offlineStatus: hex("#9CA3AF"),
        errorColor: hex("#EF4444"),
        successColor: hex("#22C55E"),
        warningColor: hex("#F59E0B")
    )

    /// Spec-default dark palette. Used when the merchant hasn't shipped
    /// an explicit `appearance` config and the iOS system is in dark
    /// mode. Mirrors the light palette inversion: deep neutral grays
    /// for backgrounds, brand purple slightly desaturated to reduce
    /// eye strain at low ambient brightness, near-white text.
    public static let darkDefault: ChatColors = ChatColors(
        primary: hex("#A855F7"),
        background: hex("#0F0F14"),
        text: hex("#F3F4F6"),
        textSecondary: hex("#9CA3AF"),
        border: hex("#374151"),
        inputBg: hex("#1F2937"),
        inputBorder: hex("#374151"),
        inputText: hex("#F3F4F6"),
        inputPlaceholder: hex("#6B7280"),
        headerBackground: hex("#7E22CE"),
        headerPrimaryText: .white,
        headerSecondaryText: hex("#E9D5FF"),
        headerIcon: .white,
        closeButton: .white,
        sentBubble: hex("#9333EA"),
        sentText: .white,
        sentTimestamp: hex("#E9D5FF"),
        receivedBubble: hex("#1F2937"),
        receivedText: hex("#F3F4F6"),
        receivedTimestamp: hex("#9CA3AF"),
        systemMessageText: hex("#9CA3AF"),
        daySeparatorBg: hex("#3B0764"),
        daySeparatorText: hex("#D8B4FE"),
        footerContainer: hex("#111827"),
        sendButtonBg: hex("#A855F7"),
        sendButtonIcon: .white,
        attachmentButton: hex("#9CA3AF"),
        typingBg: hex("#1F2937"),
        typingDot: hex("#9CA3AF"),
        unreadBadgeBg: hex("#A855F7"),
        unreadBadgeText: .white,
        scrollToBottomBg: hex("#A855F7"),
        scrollToBottomIcon: .white,
        onlineStatus: hex("#34D399"),
        offlineStatus: hex("#6B7280"),
        errorColor: hex("#F87171"),
        successColor: hex("#34D399"),
        warningColor: hex("#FBBF24")
    )

    /// Build a palette from the server-provided appearance object. When
    /// `appearance` is nil we return ``lightDefault`` — callers in dark
    /// mode should use ``from(_:colorScheme:)`` instead to get the
    /// dark fallback.
    public static func from(_ appearance: OrgAppearance?) -> ChatColors {
        guard let a = appearance else { return .lightDefault }
        let c = a.colors
        return ChatColors(
            primary: hex(c.headerBackground),
            background: hex(c.chatBackground),
            text: hex(c.receivedText),
            textSecondary: hex(c.receivedTimestamp),
            border: hex(c.chatInputBorder),
            inputBg: hex(c.chatInputBackground),
            inputBorder: hex(c.chatInputBorder),
            inputText: hex(c.chatInputText),
            inputPlaceholder: hex(c.chatInputPlaceholder),
            headerBackground: hex(c.headerBackground),
            headerPrimaryText: hex(c.headerPrimaryText),
            headerSecondaryText: hex(c.headerSecondaryText),
            headerIcon: hex(c.headerIcon),
            closeButton: hex(c.closeButton),
            sentBubble: hex(c.sentBubble),
            sentText: hex(c.sentText),
            sentTimestamp: hex(c.sentTimestamp),
            receivedBubble: hex(c.receivedBubble),
            receivedText: hex(c.receivedText),
            receivedTimestamp: hex(c.receivedTimestamp),
            systemMessageText: hex(c.systemMessageText),
            daySeparatorBg: hex(c.daySeparatorBackground),
            daySeparatorText: hex(c.daySeparatorText),
            footerContainer: hex(c.footerContainer),
            sendButtonBg: hex(c.sendButtonBackground),
            sendButtonIcon: hex(c.sendButtonIcon),
            attachmentButton: hex(c.attachmentButton),
            typingBg: hex(c.typingIndicatorBackground),
            typingDot: hex(c.typingIndicatorDot),
            unreadBadgeBg: hex(c.unreadBadgeBackground),
            unreadBadgeText: hex(c.unreadBadgeText),
            scrollToBottomBg: hex(c.scrollToBottomButtonBackground),
            scrollToBottomIcon: hex(c.scrollToBottomButtonIcon),
            onlineStatus: hex(c.onlineStatus),
            offlineStatus: hex(c.offlineStatus),
            errorColor: hex(c.error),
            successColor: hex(c.success),
            warningColor: hex(c.warning)
        )
    }

    /// Colour-scheme-aware factory. Picks `lightDefault` / `darkDefault`
    /// based on the system's current `colorScheme` when the merchant
    /// hasn't shipped an explicit `appearance` config. Pass-through
    /// otherwise (merchant config wins regardless of system mode).
    public static func from(_ appearance: OrgAppearance?, colorScheme: ColorScheme) -> ChatColors {
        if appearance == nil {
            return colorScheme == .dark ? .darkDefault : .lightDefault
        }
        return from(appearance)
    }

    /// Lenient hex parser — `#RRGGBB` or `#AARRGGBB`. Returns black on
    /// parse failure rather than crashing so a single bad merchant value
    /// can't break the UI.
    static func hex(_ value: String) -> Color {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var hexValue: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&hexValue) else { return .black }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((hexValue & 0xFF0000) >> 16) / 255.0
            g = Double((hexValue & 0x00FF00) >> 8) / 255.0
            b = Double(hexValue & 0x0000FF) / 255.0
            a = 1.0
        case 8:
            // #AARRGGBB
            a = Double((hexValue & 0xFF000000) >> 24) / 255.0
            r = Double((hexValue & 0x00FF0000) >> 16) / 255.0
            g = Double((hexValue & 0x0000FF00) >> 8) / 255.0
            b = Double(hexValue & 0x000000FF) / 255.0
        default:
            return .black
        }
        return Color(red: r, green: g, blue: b).opacity(a)
    }
}

// MARK: - Environment injection

private struct ChatColorsKey: EnvironmentKey {
    static let defaultValue: ChatColors = .lightDefault
}

public extension EnvironmentValues {
    var chatColors: ChatColors {
        get { self[ChatColorsKey.self] }
        set { self[ChatColorsKey.self] = newValue }
    }
}
