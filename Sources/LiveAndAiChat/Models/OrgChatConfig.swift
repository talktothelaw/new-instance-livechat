import Foundation

// MARK: - Legacy branding palette

public struct OrgBranding: Codable, Equatable, Sendable {
    public let primaryColor: String
    public let secondaryColor: String
    public let accentColor: String
    public let backgroundColor: String
    public let textColor: String
    public let fontFamily: String
    public let logoUrl: String?
    public let companyName: String

    public init(
        primaryColor: String = "#7C3AED",
        secondaryColor: String = "#A78BFA",
        accentColor: String = "#7C3AED",
        backgroundColor: String = "#FFFFFF",
        textColor: String = "#111827",
        fontFamily: String = "system-ui, -apple-system, sans-serif",
        logoUrl: String? = nil,
        companyName: String = ""
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.fontFamily = fontFamily
        self.logoUrl = logoUrl
        self.companyName = companyName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryColor = try c.decodeIfPresent(String.self, forKey: .primaryColor) ?? "#7C3AED"
        secondaryColor = try c.decodeIfPresent(String.self, forKey: .secondaryColor) ?? "#A78BFA"
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? "#7C3AED"
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor) ?? "#FFFFFF"
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor) ?? "#111827"
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? "system-ui, -apple-system, sans-serif"
        logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? ""
    }
}

// MARK: - Fine-grained appearance (new spec)

/// Every property maps to a specific visible element of the chat widget.
/// Defaults are the spec defaults — also seeded server-side by
/// `gql-server/.../appearanceDefaults.ts`.
public struct OrgAppearanceColors: Codable, Equatable, Sendable {
    public var chatBackground: String = "#F7F7FB"
    public var headerBackground: String = "#9333EA"
    public var headerPrimaryText: String = "#FFFFFF"
    public var headerSecondaryText: String = "#E9D5FF"
    public var headerIcon: String = "#FFFFFF"
    public var closeButton: String = "#FFFFFF"
    public var receivedBubble: String = "#FFFFFF"
    public var receivedText: String = "#111827"
    public var receivedTimestamp: String = "#6B7280"
    public var sentBubble: String = "#9333EA"
    public var sentText: String = "#FFFFFF"
    public var sentTimestamp: String = "#E9D5FF"
    public var systemMessageText: String = "#6B7280"
    public var daySeparatorBackground: String = "#EDE9FE"
    public var daySeparatorText: String = "#6D28D9"
    public var footerContainer: String = "#FFFFFF"
    public var chatInputBackground: String = "#F9FAFB"
    public var chatInputText: String = "#111827"
    public var chatInputPlaceholder: String = "#9CA3AF"
    public var chatInputBorder: String = "#E5E7EB"
    public var sendButtonBackground: String = "#9333EA"
    public var sendButtonIcon: String = "#FFFFFF"
    public var attachmentButton: String = "#6B7280"
    public var emojiButton: String = "#6B7280"
    public var typingIndicatorBackground: String = "#F3F4F6"
    public var typingIndicatorDot: String = "#9CA3AF"
    public var unreadBadgeBackground: String = "#9333EA"
    public var unreadBadgeText: String = "#FFFFFF"
    public var scrollToBottomButtonBackground: String = "#9333EA"
    public var scrollToBottomButtonIcon: String = "#FFFFFF"
    public var onlineStatus: String = "#22C55E"
    public var offlineStatus: String = "#9CA3AF"
    public var error: String = "#EF4444"
    public var success: String = "#22C55E"
    public var warning: String = "#F59E0B"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = OrgAppearanceColors()
        if let v = try c.decodeIfPresent(String.self, forKey: .chatBackground) { d.chatBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .headerBackground) { d.headerBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .headerPrimaryText) { d.headerPrimaryText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .headerSecondaryText) { d.headerSecondaryText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .headerIcon) { d.headerIcon = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .closeButton) { d.closeButton = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .receivedBubble) { d.receivedBubble = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .receivedText) { d.receivedText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .receivedTimestamp) { d.receivedTimestamp = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .sentBubble) { d.sentBubble = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .sentText) { d.sentText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .sentTimestamp) { d.sentTimestamp = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .systemMessageText) { d.systemMessageText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .daySeparatorBackground) { d.daySeparatorBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .daySeparatorText) { d.daySeparatorText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .footerContainer) { d.footerContainer = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .chatInputBackground) { d.chatInputBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .chatInputText) { d.chatInputText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .chatInputPlaceholder) { d.chatInputPlaceholder = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .chatInputBorder) { d.chatInputBorder = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .sendButtonBackground) { d.sendButtonBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .sendButtonIcon) { d.sendButtonIcon = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .attachmentButton) { d.attachmentButton = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .emojiButton) { d.emojiButton = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .typingIndicatorBackground) { d.typingIndicatorBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .typingIndicatorDot) { d.typingIndicatorDot = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .unreadBadgeBackground) { d.unreadBadgeBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .unreadBadgeText) { d.unreadBadgeText = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .scrollToBottomButtonBackground) { d.scrollToBottomButtonBackground = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .scrollToBottomButtonIcon) { d.scrollToBottomButtonIcon = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .onlineStatus) { d.onlineStatus = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .offlineStatus) { d.offlineStatus = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .error) { d.error = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .success) { d.success = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .warning) { d.warning = v }
        self = d
    }
}

public struct OrgAppearanceBackgroundImage: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var url: String? = nil
    public var opacity: Double = 1
    public var position: String = "center"
    public var size: String = "cover"
    public var repeatStyle: String = "no-repeat"
    public var overlayColor: String = "#000000"
    public var overlayOpacity: Double = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = OrgAppearanceBackgroundImage()
        if let v = try c.decodeIfPresent(Bool.self, forKey: .enabled) { d.enabled = v }
        d.url = try c.decodeIfPresent(String.self, forKey: .url)
        if let v = try c.decodeIfPresent(Double.self, forKey: .opacity) { d.opacity = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .position) { d.position = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .size) { d.size = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .repeatStyle) { d.repeatStyle = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .overlayColor) { d.overlayColor = v }
        if let v = try c.decodeIfPresent(Double.self, forKey: .overlayOpacity) { d.overlayOpacity = v }
        self = d
    }

    enum CodingKeys: String, CodingKey {
        case enabled, url, opacity, position, size, overlayColor, overlayOpacity
        // The GraphQL field is named `repeat`, which is a Swift keyword.
        // We expose it as `repeatStyle` while decoding/encoding the
        // server-side name.
        case repeatStyle = "repeat"
    }
}

public struct OrgAppearance: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var fontFamily: String = "Inter, sans-serif"
    public var themeMode: String = "auto"
    public var colors: OrgAppearanceColors = OrgAppearanceColors()
    public var backgroundImage: OrgAppearanceBackgroundImage = OrgAppearanceBackgroundImage()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = OrgAppearance()
        if let v = try c.decodeIfPresent(Int.self, forKey: .version) { d.version = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .fontFamily) { d.fontFamily = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .themeMode) { d.themeMode = v }
        if let v = try c.decodeIfPresent(OrgAppearanceColors.self, forKey: .colors) { d.colors = v }
        if let v = try c.decodeIfPresent(OrgAppearanceBackgroundImage.self, forKey: .backgroundImage) { d.backgroundImage = v }
        self = d
    }
}

// MARK: - Settings + Widget + Feature toggles

public struct OrgSettings: Codable, Equatable, Sendable {
    public var welcomeMessage: String
    public var offlineMessage: String
    public var placeholderText: String
    public var enableFileUpload: Bool
    public var enableEmojis: Bool
    public var enableTypingIndicator: Bool
    public var requireCustomerEmail: Bool

    public init(
        welcomeMessage: String = "",
        offlineMessage: String = "",
        placeholderText: String = "",
        enableFileUpload: Bool = true,
        enableEmojis: Bool = true,
        enableTypingIndicator: Bool = true,
        requireCustomerEmail: Bool = false
    ) {
        self.welcomeMessage = welcomeMessage
        self.offlineMessage = offlineMessage
        self.placeholderText = placeholderText
        self.enableFileUpload = enableFileUpload
        self.enableEmojis = enableEmojis
        self.enableTypingIndicator = enableTypingIndicator
        self.requireCustomerEmail = requireCustomerEmail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            welcomeMessage: (try c.decodeIfPresent(String.self, forKey: .welcomeMessage)) ?? "",
            offlineMessage: (try c.decodeIfPresent(String.self, forKey: .offlineMessage)) ?? "",
            placeholderText: (try c.decodeIfPresent(String.self, forKey: .placeholderText)) ?? "",
            enableFileUpload: (try c.decodeIfPresent(Bool.self, forKey: .enableFileUpload)) ?? true,
            enableEmojis: (try c.decodeIfPresent(Bool.self, forKey: .enableEmojis)) ?? true,
            enableTypingIndicator: (try c.decodeIfPresent(Bool.self, forKey: .enableTypingIndicator)) ?? true,
            requireCustomerEmail: (try c.decodeIfPresent(Bool.self, forKey: .requireCustomerEmail)) ?? false
        )
    }
}

public struct OrgWidget: Codable, Equatable, Sendable {
    public var position: String
    public var size: String
    public var theme: String
    public var showOnlineStatus: Bool
    public var enableSounds: Bool

    public init(
        position: String = "bottom-right",
        size: String = "medium",
        theme: String = "light",
        showOnlineStatus: Bool = true,
        enableSounds: Bool = true
    ) {
        self.position = position
        self.size = size
        self.theme = theme
        self.showOnlineStatus = showOnlineStatus
        self.enableSounds = enableSounds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            position: (try c.decodeIfPresent(String.self, forKey: .position)) ?? "bottom-right",
            size: (try c.decodeIfPresent(String.self, forKey: .size)) ?? "medium",
            theme: (try c.decodeIfPresent(String.self, forKey: .theme)) ?? "light",
            showOnlineStatus: (try c.decodeIfPresent(Bool.self, forKey: .showOnlineStatus)) ?? true,
            enableSounds: (try c.decodeIfPresent(Bool.self, forKey: .enableSounds)) ?? true
        )
    }
}

public struct OrgFeatureToggle: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool = true) { self.enabled = enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
    }
}

public struct OrgChatConfig: Codable, Equatable, Sendable {
    public var branding: OrgBranding
    public var appearance: OrgAppearance?
    public var settings: OrgSettings
    public var widget: OrgWidget
    public var chatInterface: OrgFeatureToggle
    public var aiChatbot: OrgFeatureToggle
    public var liveChatModule: OrgFeatureToggle

    public init(
        branding: OrgBranding = OrgBranding(),
        appearance: OrgAppearance? = nil,
        settings: OrgSettings = OrgSettings(),
        widget: OrgWidget = OrgWidget(),
        chatInterface: OrgFeatureToggle = OrgFeatureToggle(),
        aiChatbot: OrgFeatureToggle = OrgFeatureToggle(),
        liveChatModule: OrgFeatureToggle = OrgFeatureToggle()
    ) {
        self.branding = branding
        self.appearance = appearance
        self.settings = settings
        self.widget = widget
        self.chatInterface = chatInterface
        self.aiChatbot = aiChatbot
        self.liveChatModule = liveChatModule
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        branding = (try c.decodeIfPresent(OrgBranding.self, forKey: .branding)) ?? OrgBranding()
        appearance = try c.decodeIfPresent(OrgAppearance.self, forKey: .appearance)
        settings = (try c.decodeIfPresent(OrgSettings.self, forKey: .settings)) ?? OrgSettings()
        widget = (try c.decodeIfPresent(OrgWidget.self, forKey: .widget)) ?? OrgWidget()
        chatInterface = (try c.decodeIfPresent(OrgFeatureToggle.self, forKey: .chatInterface)) ?? OrgFeatureToggle()
        aiChatbot = (try c.decodeIfPresent(OrgFeatureToggle.self, forKey: .aiChatbot)) ?? OrgFeatureToggle()
        liveChatModule = (try c.decodeIfPresent(OrgFeatureToggle.self, forKey: .liveChatModule)) ?? OrgFeatureToggle()
    }
}
