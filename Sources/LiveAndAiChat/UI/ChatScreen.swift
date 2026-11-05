import Foundation

enum WaitingCopy {
    static let title = "Waiting for an agent…"

    static func detail(queuePosition: Int?, estimatedWaitSeconds: Int?) -> String? {
        var parts: [String] = []
        if let position = queuePosition, position > 0 {
            parts.append("Position in queue: \(position)")
        }
        if let seconds = estimatedWaitSeconds, seconds >= 0 {
            parts.append("Estimated wait: \(max(1, (seconds + 59) / 60)) min")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#if canImport(UIKit)
import SwiftUI
import Combine

/// Top-level SwiftUI view shipped by the SDK. Hosts can use this directly
/// (e.g. inside their own `NavigationStack`) or rely on
/// ``LiveAndAiChat/openChat()`` which presents it modally.
///
/// Behavioural parity with the Android `ChatScreen` Composable + the web
/// SDK's `ChatWidget`:
///   - Header with company name / agent name + status subtitle + close button
///   - Connection banner on offline / disconnected
///   - Reverse-anchored message list (no animated scroll on first paint)
///   - Composer with attachment chip strip, send button, FAILED-retry on bubble tap
///   - Welcome bubble surfaced from `orgConfig.settings.welcomeMessage` (no
///     hardcoded fallback — matches the web/Android decision)
public struct ChatScreen: View {

    @ObservedObject var sdk: LiveAndAiChat
    @ObservedObject var store: ChatStore
    @ObservedObject var attachmentQueue: AttachmentQueue
    let onClose: () -> Void
    let onPickFile: () -> Void

    @State private var viewerAttachment: MessageAttachment?
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        sdk: LiveAndAiChat,
        onClose: @escaping () -> Void,
        onPickFile: @escaping () -> Void = {}
    ) {
        self.sdk = sdk
        self.store = sdk._store
        self.attachmentQueue = sdk._attachmentQueue
        self.onClose = onClose
        self.onPickFile = onPickFile
    }

    public var body: some View {
        let colors = ChatColors.resolve(
            appearance: sdk.orgConfig?.appearance,
            override: sdk.themeOverride,
            colorScheme: systemColorScheme
        )
        let companyName = sdk.orgConfig?.branding.companyName ?? ""
        let title = store.conversation?.assignedAgentName
            ?? (companyName.isEmpty ? "Chat" : companyName)
        let subtitle = subtitleText
        let attachmentsAllowed = sdk.orgConfig?.settings.enableFileUpload ?? true
        let typingAllowed = sdk.orgConfig?.settings.enableTypingIndicator ?? true
        let logoUrl = sdk.orgConfig?.branding.logoUrl
        let showOnlineStatus = sdk.orgConfig?.widget.showOnlineStatus ?? true
        let canRequestHandoff = store.flowState == .botConversation && sdk.lifecycle == .ready
        let hero = sdk.lifecycle == .ready && store.messages.isEmpty
        let subtitleIcon: HeaderSubtitleIcon = {
            switch store.flowState {
            case .botConversation: return .bot
            case .liveChat: return .agent
            default: return .none
            }
        }()

        VStack(spacing: 0) {
            ChatHeader(
                title: title,
                subtitle: subtitle,
                subtitleIcon: subtitleIcon,
                logoUrl: logoUrl,
                showOnlineStatus: showOnlineStatus,
                isOnline: sdk.connectionState == .connected,
                showHandoffButton: canRequestHandoff,
                hero: hero,
                welcomeMessage: sdk.orgConfig?.settings.welcomeMessage ?? "",
                onRequestHandoff: { sdk.requestHandoff(reason: "user_requested") },
                onClose: onClose
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hero)

            switch sdk.connectionState {
            case .offline:
                ConnectionBanner(
                    text: sdk.orgConfig?.settings.offlineMessage.isEmpty == false
                        ? sdk.orgConfig!.settings.offlineMessage
                        : "You appear to be offline",
                    iconName: "wifi.slash"
                )
            case .disconnected:
                ConnectionBanner(text: "Reconnecting…", iconName: "arrow.triangle.2.circlepath")
            default:
                EmptyView()
            }

            if store.flowState == .handoffPending && sdk.lifecycle == .ready {
                WaitingCard(
                    queuePosition: store.assignment?.queuePosition,
                    estimatedWaitSeconds: store.assignment?.estimatedWaitTime
                )
            }

            ZStack {
                colors.background
                body(for: sdk.lifecycle, typingAllowed: typingAllowed)
            }
            .frame(maxHeight: .infinity)

            if let rating = store.pendingRating {
                RatingCard(
                    rating: rating,
                    onSubmit: { score, comment in sdk.submitRating(score: score, comment: comment) },
                    onSkip: { sdk.skipRating() }
                )
                .id(rating.conversationId)
            }

            Composer(
                placeholderText: sdk.orgConfig?.settings.placeholderText.isEmpty == false
                    ? sdk.orgConfig!.settings.placeholderText
                    : "Type a message",
                pendingAttachments: attachmentQueue.items,
                attachmentsAllowed: attachmentsAllowed,
                // Composer stays usable when the conversation has ended
                // — sending in that state runs recoverFromClosedAndResend
                // server-side, which silently starts a fresh chat with
                // the customer's message as the first one. (Matches
                // Android.) Only `.unavailable` truly blocks input.
                enabled: sdk.lifecycle == .ready
                    || sdk.lifecycle == .notStarted
                    || store.flowState == .ended,
                onPickFile: onPickFile,
                onRemoveAttachment: { sdk.removeAttachment(id: $0) },
                onRetryAttachment: { sdk.retryAttachment(id: $0) },
                onSend: { sdk.sendMessage($0) },
                onTyping: { typing in
                    if typing { sdk.sendTypingStart() } else { sdk.sendTypingStop() }
                },
                text: Binding(
                    get: { sdk.draftText },
                    set: { sdk.updateDraft($0) }
                )
            )
        }
        .environment(\.chatColors, colors)
        // Clamp to a readable column width on iPad / landscape / wide
        // splits (≤ 640pt). On iPhone portrait this is a no-op because
        // the screen is already narrower. The outer HStack centres the
        // clamped content and fills the side gutters with the chat
        // background colour so the header / composer still appear
        // edge-to-edge inside the column.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(colors.background.ignoresSafeArea(.container, edges: .bottom))
        .fullScreenCover(item: $viewerAttachment) { att in
            ImageViewerView(attachment: att, onClose: { viewerAttachment = nil })
                .environment(\.chatColors, colors)
        }
    }

    @ViewBuilder
    private func body(
        for lifecycle: ChatSdkLifecycle,
        typingAllowed: Bool
    ) -> some View {
        switch lifecycle {
        case .initializing, .notStarted:
            ConnectingPlaceholder(text: "Connecting to chat service…")
        case .unavailable:
            SystemNoticeBlock(
                text: "Chat is currently unavailable",
                iconName: "moon.zzz",
                actionLabel: nil,
                onAction: nil
            )
        case .failed:
            SystemNoticeBlock(
                text: "Could not start chat. Check your connection and try again.",
                iconName: "wifi.exclamationmark",
                actionLabel: "Retry",
                onAction: { sdk.initialize() }
            )
        case .ready:
            if store.messages.isEmpty {
                Color.clear
            } else {
                MessageList(
                    messages: store.messages,
                    agentTyping: typingAllowed && store.agentTyping,
                    ended: store.flowState == .ended,
                    onRetry: { sdk.retryMessage(messageId: $0) },
                    onImageTap: { att in viewerAttachment = att },
                    onAnswer: { id, action, content in
                        try await sdk.answerElicitation(messageId: id, action: action, content: content)
                    },
                    onOpenStep: { sdk.openSecurePage($0) },
                    backgroundImage: sdk.orgConfig?.appearance?.backgroundImage
                )
            }
        }
    }

    private var subtitleText: String {
        switch sdk.lifecycle {
        case .initializing, .notStarted: return "Connecting to chat service…"
        case .unavailable: return "Chat unavailable"
        case .failed: return "Failed to start chat"
        case .ready: break
        }
        switch store.flowState {
        case .handoffPending: return WaitingCopy.title
        case .liveChat: return "Live agent"
        case .botConversation: return "AI Assistant"
        case .ended: return "Conversation ended"
        default: break
        }
        switch sdk.connectionState {
        case .connected: return "Online"
        case .connecting: return "Connecting…"
        case .disconnected: return "Reconnecting…"
        case .offline: return "Offline"
        case .idle: return ""
        }
    }
}

/// Need Identifiable conformance so `.fullScreenCover(item:)` can drive the
/// viewer presentation. Attachments are already Equatable; URL is unique
/// per attachment within a conversation so it's a fine identifier.
extension MessageAttachment: Identifiable {
    public var id: String { url }
}

// MARK: - Subviews

/// Flow-state icon shown alongside the header subtitle. `bot` for AI
/// conversations, `agent` for live-chat. Mirrors the lucide Bot /
/// Headphones icons from the web `ChatHeader.tsx`.
enum HeaderSubtitleIcon { case none, bot, agent }

struct ChatHeader: View {
    let title: String
    let subtitle: String
    let subtitleIcon: HeaderSubtitleIcon
    let logoUrl: String?
    let showOnlineStatus: Bool
    let isOnline: Bool
    let showHandoffButton: Bool
    var hero: Bool = false
    var welcomeMessage: String = ""
    let onRequestHandoff: () -> Void
    let onClose: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        Group {
            if hero { heroBody } else { compactBody }
        }
        .frame(maxWidth: .infinity)
        .background(HeaderBackdrop().ignoresSafeArea(edges: .top))
    }

    private var logo: String? {
        guard let url = logoUrl, !url.isEmpty else { return nil }
        return url
    }

    private var compactBody: some View {
        HStack(alignment: .center, spacing: 8) {
            closeChip
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    if let url = logo {
                        HeaderLogo(url: url, size: 24)
                    }
                    Text(ChatHeader.titleCase(title))
                        .font(.headline.weight(.bold))
                        .foregroundColor(colors.headerPrimaryText)
                        .lineLimit(1)
                }
                statusLine(font: .footnote)
            }
            .frame(maxWidth: .infinity)
            if showHandoffButton {
                handoffChip
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                closeChip
                Spacer(minLength: 8)
                if showHandoffButton { handoffChip }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let url = logo {
                    HeaderLogo(url: url, size: 40)
                        .padding(.bottom, 4)
                }
                Text(ChatHeader.titleCase(title))
                    .font(.title.weight(.heavy))
                    .tracking(-0.5)
                    .foregroundColor(colors.headerPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !welcomeMessage.isEmpty {
                    Text(welcomeMessage)
                        .font(.callout)
                        .foregroundColor(colors.headerSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statusLine(font: .footnote.weight(.semibold))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.top, 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusLine(font: Font) -> some View {
        if !subtitle.isEmpty {
            HStack(spacing: 6) {
                if showOnlineStatus {
                    Circle()
                        .fill(isOnline ? colors.onlineStatus : colors.offlineStatus)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)  // subtitle text conveys this
                }
                if let iconName = subtitleIconName {
                    Image(systemName: iconName)
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(ChatHeader.titleCase(subtitle))
                    .lineLimit(1)
            }
            .font(font)
            .foregroundColor(colors.headerSecondaryText)
            .accessibilityElement(children: .combine)
        }
    }

    private var closeChip: some View {
        HeaderIconButton(systemName: "chevron.down", fill: colors.closeChip, color: colors.closeButton, action: onClose)
            .accessibilityLabel("Close")
    }

    private var handoffChip: some View {
        HeaderIconButton(systemName: "headphones", fill: colors.iconChip, color: colors.headerIcon, action: onRequestHandoff)
            .accessibilityLabel("Talk to a live agent")
    }

    private var subtitleIconName: String? {
        switch subtitleIcon {
        case .none: return nil
        case .bot: return "sparkles"
        case .agent: return "headphones"
        }
    }

    /// Title-case every word — "live agent" → "Live Agent". Acronyms
    /// already in uppercase ≤4 chars (AI, FAQ, etc.) are preserved.
    /// Matches the `titleCase` helper in the web SDK.
    static func titleCase(_ s: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: false)
        let mapped: [String] = words.map { raw in
            let word = String(raw)
            if word.isEmpty { return word }
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return mapped.joined(separator: " ")
    }
}

struct HeaderBackdrop: View {
    @Environment(\.chatColors) private var colors

    var body: some View {
        let stops = colors.headerStops
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let points = HeaderBackdrop.gradientPoints(width: w, height: h)
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [colors.headerBackground, stops.deep]),
                    startPoint: points.start,
                    endPoint: points.end
                )
                RadialGradient(
                    gradient: Gradient(colors: [stops.glow, stops.glow.opacity(0)]),
                    center: .center,
                    startRadius: 0,
                    endRadius: 0.6 * 1.2 * w
                )
                .frame(width: 2.4 * w, height: 2.4 * w)
                .scaleEffect(x: 1, y: (1.4 * h) / (1.2 * w))
                .position(x: w, y: 0)
            }
        }
        .clipped()
        .overlay(Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1), alignment: .bottom)
        .accessibilityHidden(true)
    }

    static func gradientPoints(width w: CGFloat, height h: CGFloat) -> (start: UnitPoint, end: UnitPoint) {
        let angle = CGFloat.pi * 160 / 180
        let dx = sin(angle), dy = -cos(angle)
        let span = abs(w * dx) + abs(h * dy)
        let ux = dx * span / (2 * w), uy = dy * span / (2 * h)
        return (UnitPoint(x: 0.5 - ux, y: 0.5 - uy), UnitPoint(x: 0.5 + ux, y: 0.5 + uy))
    }
}

/// 44-pt round icon button used by the header for handoff / close.
private struct HeaderIconButton: View {
    let systemName: String
    let fill: Color
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Cached rounded logo tile in the header. Falls back to a tinted
/// silhouette when the URL fails to load.
struct HeaderLogo: View {
    let url: String
    var size: CGFloat = 32
    @Environment(\.chatColors) private var colors

    var body: some View {
        CachedAsyncImage(
            url: URL(string: url),
            content: { image in
                image.resizable().aspectRatio(contentMode: .fit)
            },
            placeholder: { fallback }
        )
        .frame(width: size, height: size)
        .background(colors.logoTile)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: size * 0.45))
            .foregroundColor(colors.headerPrimaryText.opacity(0.7))
    }
}

/// Centered notice rendered inside the conversation area when chat is
/// unavailable or initialization failed. Mirrors the web SDK's
/// SystemNotice layout: muted glyph, message, optional inline action
/// pill.
struct SystemNoticeBlock: View {
    let text: String
    let iconName: String
    let actionLabel: String?
    let onAction: (() -> Void)?
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.systemMessageText)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 56 * 0.22, style: .continuous).fill(colors.receivedBubble))
            Text(text)
                .font(.callout)
                .foregroundColor(colors.systemMessageText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let label = actionLabel, let action = onAction {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(label)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(colors.sendButtonIcon)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(colors.sendButtonBg))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Connecting to chat service…" placeholder shown while the SDK is
/// bootstrapping the session. Composer is disabled at the call site;
/// this just communicates *why*.
struct ConnectingPlaceholder: View {
    let text: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: colors.sendButtonBg))
            Text(text)
                .font(.footnote)
                .foregroundColor(colors.systemMessageText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConnectionBanner: View {
    let text: String
    var iconName: String = "wifi.slash"
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.footnote.weight(.semibold))
                .foregroundColor(colors.warningColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundColor(colors.receivedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colors.warnTint)
        .overlay(Rectangle().fill(colors.hairline).frame(height: 1), alignment: .bottom)
    }
}

struct WaitingCard: View {
    let queuePosition: Int?
    let estimatedWaitSeconds: Int?
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colors.sendButtonBg)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(colors.background))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: WaitingCopy.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(colors.receivedText)
                    if let detail = WaitingCopy.detail(queuePosition: queuePosition, estimatedWaitSeconds: estimatedWaitSeconds) {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundColor(colors.systemMessageText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            IndeterminateBar()
                .frame(height: 4)
        }
        .padding(.top, 14)
        .background(colors.receivedBubble)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(colors.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(colors.background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct IndeterminateBar: View {
    @Environment(\.chatColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var moving = false

    var body: some View {
        GeometryReader { geo in
            let segment = geo.size.width * 0.38
            ZStack(alignment: .leading) {
                colors.hairline
                Capsule()
                    .fill(colors.sendButtonBg)
                    .frame(width: segment)
                    .offset(x: reduceMotion ? geo.size.width * 0.22 : (moving ? geo.size.width : -segment))
            }
        }
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { moving = true }
        }
        .accessibilityHidden(true)
    }
}

#endif
