import SwiftUI

public struct ChatThemeOverride: Equatable, Sendable {
    public enum Mode: String, Sendable { case light, dark }

    public var mode: Mode?
    public var chatBackground: String?
    public var headerBackground: String?
    public var headerPrimaryText: String?
    public var headerSecondaryText: String?
    public var headerIcon: String?
    public var closeButton: String?
    public var receivedBubble: String?
    public var receivedText: String?
    public var receivedTimestamp: String?
    public var sentBubble: String?
    public var sentText: String?
    public var sentTimestamp: String?
    public var systemMessageText: String?
    public var daySeparatorBackground: String?
    public var daySeparatorText: String?
    public var footerContainer: String?
    public var chatInputBackground: String?
    public var chatInputText: String?
    public var chatInputPlaceholder: String?
    public var chatInputBorder: String?
    public var sendButtonBackground: String?
    public var sendButtonIcon: String?
    public var attachmentButton: String?
    public var unreadBadgeBackground: String?
    public var unreadBadgeText: String?

    public init(
        mode: Mode? = nil,
        chatBackground: String? = nil,
        headerBackground: String? = nil,
        headerPrimaryText: String? = nil,
        headerSecondaryText: String? = nil,
        headerIcon: String? = nil,
        closeButton: String? = nil,
        receivedBubble: String? = nil,
        receivedText: String? = nil,
        receivedTimestamp: String? = nil,
        sentBubble: String? = nil,
        sentText: String? = nil,
        sentTimestamp: String? = nil,
        systemMessageText: String? = nil,
        daySeparatorBackground: String? = nil,
        daySeparatorText: String? = nil,
        footerContainer: String? = nil,
        chatInputBackground: String? = nil,
        chatInputText: String? = nil,
        chatInputPlaceholder: String? = nil,
        chatInputBorder: String? = nil,
        sendButtonBackground: String? = nil,
        sendButtonIcon: String? = nil,
        attachmentButton: String? = nil,
        unreadBadgeBackground: String? = nil,
        unreadBadgeText: String? = nil
    ) {
        self.mode = mode
        self.chatBackground = chatBackground
        self.headerBackground = headerBackground
        self.headerPrimaryText = headerPrimaryText
        self.headerSecondaryText = headerSecondaryText
        self.headerIcon = headerIcon
        self.closeButton = closeButton
        self.receivedBubble = receivedBubble
        self.receivedText = receivedText
        self.receivedTimestamp = receivedTimestamp
        self.sentBubble = sentBubble
        self.sentText = sentText
        self.sentTimestamp = sentTimestamp
        self.systemMessageText = systemMessageText
        self.daySeparatorBackground = daySeparatorBackground
        self.daySeparatorText = daySeparatorText
        self.footerContainer = footerContainer
        self.chatInputBackground = chatInputBackground
        self.chatInputText = chatInputText
        self.chatInputPlaceholder = chatInputPlaceholder
        self.chatInputBorder = chatInputBorder
        self.sendButtonBackground = sendButtonBackground
        self.sendButtonIcon = sendButtonIcon
        self.attachmentButton = attachmentButton
        self.unreadBadgeBackground = unreadBadgeBackground
        self.unreadBadgeText = unreadBadgeText
    }

    public static func fromDictionary(_ dict: [String: String]) -> ChatThemeOverride {
        func v(_ key: String) -> String? {
            guard let value = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        return ChatThemeOverride(
            mode: v("mode").flatMap { Mode(rawValue: $0.lowercased()) },
            chatBackground: v("chatBackground"),
            headerBackground: v("headerBackground"),
            headerPrimaryText: v("headerPrimaryText"),
            headerSecondaryText: v("headerSecondaryText"),
            headerIcon: v("headerIcon"),
            closeButton: v("closeButton"),
            receivedBubble: v("receivedBubble"),
            receivedText: v("receivedText"),
            receivedTimestamp: v("receivedTimestamp"),
            sentBubble: v("sentBubble"),
            sentText: v("sentText"),
            sentTimestamp: v("sentTimestamp"),
            systemMessageText: v("systemMessageText"),
            daySeparatorBackground: v("daySeparatorBackground"),
            daySeparatorText: v("daySeparatorText"),
            footerContainer: v("footerContainer"),
            chatInputBackground: v("chatInputBackground"),
            chatInputText: v("chatInputText"),
            chatInputPlaceholder: v("chatInputPlaceholder"),
            chatInputBorder: v("chatInputBorder"),
            sendButtonBackground: v("sendButtonBackground"),
            sendButtonIcon: v("sendButtonIcon"),
            attachmentButton: v("attachmentButton"),
            unreadBadgeBackground: v("unreadBadgeBackground"),
            unreadBadgeText: v("unreadBadgeText")
        )
    }
}

public extension ChatColors {
    func applying(_ override: ChatThemeOverride?) -> ChatColors {
        guard let o = override else { return self }
        var c = self
        func set(_ keyPath: WritableKeyPath<ChatColors, Color>, _ value: String?) {
            guard let value else { return }
            c[keyPath: keyPath] = ChatColors.hex(value)
        }
        set(\.background, o.chatBackground)
        set(\.primary, o.headerBackground)
        set(\.headerBackground, o.headerBackground)
        set(\.headerPrimaryText, o.headerPrimaryText)
        set(\.headerSecondaryText, o.headerSecondaryText)
        set(\.headerIcon, o.headerIcon)
        set(\.closeButton, o.closeButton)
        set(\.receivedBubble, o.receivedBubble)
        set(\.receivedText, o.receivedText)
        set(\.text, o.receivedText)
        set(\.receivedTimestamp, o.receivedTimestamp)
        set(\.textSecondary, o.receivedTimestamp)
        set(\.sentBubble, o.sentBubble)
        set(\.sentText, o.sentText)
        set(\.sentTimestamp, o.sentTimestamp)
        set(\.systemMessageText, o.systemMessageText)
        set(\.daySeparatorBg, o.daySeparatorBackground)
        set(\.daySeparatorText, o.daySeparatorText)
        set(\.footerContainer, o.footerContainer)
        set(\.inputBg, o.chatInputBackground)
        set(\.inputText, o.chatInputText)
        set(\.inputPlaceholder, o.chatInputPlaceholder)
        set(\.inputBorder, o.chatInputBorder)
        set(\.border, o.chatInputBorder)
        set(\.sendButtonBg, o.sendButtonBackground)
        set(\.sendButtonIcon, o.sendButtonIcon)
        set(\.attachmentButton, o.attachmentButton)
        set(\.unreadBadgeBg, o.unreadBadgeBackground)
        set(\.unreadBadgeText, o.unreadBadgeText)
        return c
    }

    static func resolve(
        appearance: OrgAppearance?,
        override: ChatThemeOverride?,
        colorScheme: ColorScheme
    ) -> ChatColors {
        let dark = resolveDarkMode(appearance: appearance, override: override, systemDark: colorScheme == .dark)
        let base = (dark ? ChatColors.darkDefault : ChatColors.lightDefault).applying(override)
        guard let appearance else { return base }
        return base.merging(appearance)
    }

    static func resolveDarkMode(
        appearance: OrgAppearance?,
        override: ChatThemeOverride?,
        systemDark: Bool
    ) -> Bool {
        switch appearance?.themeMode {
        case "dark": return true
        case "light": return false
        default: break
        }
        switch override?.mode {
        case .dark: return true
        case .light: return false
        case nil: return systemDark
        }
    }
}
