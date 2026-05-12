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
        let colors = ChatColors.from(sdk.orgConfig?.appearance)
        let companyName = sdk.orgConfig?.branding.companyName ?? ""
        let title = store.conversation?.assignedAgentName
            ?? (companyName.isEmpty ? "Chat" : companyName)
        let subtitle = subtitleText
        let attachmentsAllowed = sdk.orgConfig?.settings.enableFileUpload ?? true
        let typingAllowed = sdk.orgConfig?.settings.enableTypingIndicator ?? true

        VStack(spacing: 0) {
            ChatHeader(title: title, subtitle: subtitle, onClose: onClose)
                .environment(\.chatColors, colors)

            switch sdk.connectionState {
            case .offline:
                ConnectionBanner(
                    text: sdk.orgConfig?.settings.offlineMessage.isEmpty == false
                        ? sdk.orgConfig!.settings.offlineMessage
                        : "You appear to be offline"
                )
                .environment(\.chatColors, colors)
            case .disconnected:
                ConnectionBanner(text: "Reconnecting…")
                    .environment(\.chatColors, colors)
            default:
                EmptyView()
            }

            ZStack {
                colors.background
                if store.messages.isEmpty {
                    let welcome = sdk.orgConfig?.settings.welcomeMessage
                    if let welcome, !welcome.isEmpty {
                        VStack(alignment: .leading) {
                            EmptyState(welcomeMessage: welcome)
                                .environment(\.chatColors, colors)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    } else {
                        Color.clear
                    }
                } else {
                    MessageList(
                        messages: store.messages,
                        agentTyping: typingAllowed && store.agentTyping,
                        onRetry: { sdk.retryMessage(messageId: $0) },
                        onImageTap: { att in viewerAttachment = att }
                    )
                    .environment(\.chatColors, colors)
                }
            }
            .frame(maxHeight: .infinity)

            Composer(
                placeholderText: sdk.orgConfig?.settings.placeholderText.isEmpty == false
                    ? sdk.orgConfig!.settings.placeholderText
                    : "Type a message",
                pendingAttachments: attachmentQueue.items,
                attachmentsAllowed: attachmentsAllowed,
                enabled: sdk.lifecycle == .ready,
                onPickFile: onPickFile,
                onRemoveAttachment: { attachmentQueue.remove(id: $0) },
                onSend: { sdk.sendMessage($0) },
                onTyping: { typing in
                    if typing { sdk.sendTypingStart() } else { sdk.sendTypingStop() }
                }
            )
            .environment(\.chatColors, colors)
        }
        .background(colors.background.ignoresSafeArea(edges: .bottom))
        .fullScreenCover(item: $viewerAttachment) { att in
            ImageViewerView(attachment: att, onClose: { viewerAttachment = nil })
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
        case .handoffPending: return "Waiting for an agent…"
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

struct ChatHeader: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @Environment(\.chatColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.headerPrimaryText)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.headerSecondaryText)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.closeButton)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.001)))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.headerBackground)
    }
}

struct ConnectionBanner: View {
    let text: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.typingBg)
    }
}

struct EmptyState: View {
    let welcomeMessage: String
    @Environment(\.chatColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AI")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textSecondary)
                .padding(.leading, 4)
            HStack {
                Text(welcomeMessage)
                    .foregroundColor(colors.receivedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedCorners(tl: 16, tr: 16, bl: 4, br: 16)
                            .fill(colors.receivedBubble)
                    )
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
